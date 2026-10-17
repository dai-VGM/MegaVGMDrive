#!/usr/bin/env python3
"""Drive repeatable A/C and B/C profile switches and collect monotonic timings."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import statistics
import subprocess
import time
import urllib.request


TRACKS = {
    "A": "/media/fat/MegaVGMDrive/01_Arcade/After_Burner_II_(Sega_X)/02 Final Take Off.vgm",
    "B": "/media/fat/MegaVGMDrive/vgm_cache/Darius_II_(Arcade)/03 Olga Breeze.vgm",
    "C": "/media/fat/MegaVGMDrive/SID/1Commando.sid",
}
PROFILES = {name: f"PROFILE_{name}" for name in TRACKS}
CTL = "/media/fat/Scripts/megavgm_ctl"
REMOTE_STATUS = "http://127.0.0.1:8183/api/megavgm/status"
SUPERVISOR_LOG = Path("/tmp/megavgm_supervisor.log")
LOAD_ACK = Path("/tmp/megavgm_load_file.status")
MAIN_EVENTS = Path("/tmp/megavgm-rbf-bench/main-events.log")


def now_us() -> int:
    return time.monotonic_ns() // 1000


def remote_status() -> dict:
    with urllib.request.urlopen(REMOTE_STATUS, timeout=2) as response:
        return json.load(response)


def read_text(path: Path) -> str:
    try:
        return path.read_text(errors="replace")
    except FileNotFoundError:
        return ""


def parse_main_events(started: int, profile: str, source: str) -> dict[str, int]:
    result: dict[str, int] = {}
    suffix = f"MegaVGMDrive_{profile}.rbf"
    last_open = None
    for line in read_text(MAIN_EVENTS).splitlines():
        values = dict(field.split("=", 1) for field in line.split()
                      if "=" in field)
        if values.get("source") != source or not values.get("path", "").endswith(suffix):
            continue
        stamp = int(values.get("t_us", 0))
        if stamp < started:
            continue
        event = values["event"]
        if event == "t13_rbf_open_success":
            last_open = stamp
        elif event == "source_read_complete":
            if last_open is not None:
                result["source_open"] = last_open
            result[event] = stamp
        elif event in ("configuration_return", "post_configuration_sync"):
            result[event] = stamp
    return result


def parse_latency_events(generation: str) -> dict[str, int]:
    result: dict[str, int] = {}
    for line in read_text(MAIN_EVENTS).splitlines():
        if not (line.startswith("SWITCH_LATENCY ") or line.startswith("RBF_BENCH ")):
            continue
        values = dict(field.split("=", 1) for field in line.split()
                      if "=" in field)
        if values.get("switch_id") != generation:
            continue
        event = values.get("event")
        if event and event not in result:
            result[event] = int(values["t_us"])
    return result


def supervisor_ready(generation: str) -> int | None:
    needle = f"generation={generation} "
    for line in reversed(read_text(SUPERVISOR_LOG).splitlines()):
        if "PHASE2A_SWITCH" not in line or needle not in line or "state=READY" not in line:
            continue
        for field in line.split():
            if field.startswith("timestamp_ms="):
                return int(field.split("=", 1)[1]) * 1000
    return None


def controller_ready(generation: str) -> bool:
    content = read_text(LOAD_ACK)
    return (f"generation={generation}\n" in content and
            "phase=TRANSFER_SUCCESS\n" in content and "index=1\n" in content)


def invoke(profile: str, source: str, timeout: float) -> dict:
    before = remote_status()
    before_transport = before["transport"]
    from_profile = before_transport["currentProfile"]
    expected = PROFILES[profile]
    if from_profile == expected:
        raise RuntimeError(f"same-profile invocation excluded: {profile}")
    requested = now_us()
    command = subprocess.run([CTL, "play", TRACKS[profile]], text=True,
                             capture_output=True)
    returned = now_us()
    if command.returncode:
        raise RuntimeError(f"control failed: {command.stdout} {command.stderr}")

    deadline = time.monotonic() + timeout
    stamps: dict[str, int | None] = {
        "request_us": requested,
        "control_return_us": returned,
        "t0_request_accepted_us": None,
        "t1_supervisor_request_observed_us": None,
        "t1_switching_us": None,
        "t2_supervisor_enters_switching_us": None,
        "t3_target_profile_resolved_us": None,
        "t4_target_rbf_path_resolved_us": None,
        "t5_old_session_quiesce_begin_us": None,
        "drain_stable_zero_begin_us": None,
        "drain_stable_zero_complete_us": None,
        "t6_old_session_quiesce_complete_us": None,
        "start_modified_main_begin_us": None,
        "start_modified_main_complete_us": None,
        "verify_modified_main_begin_us": None,
        "verify_modified_main_complete_us": None,
        "t7_fifo_dispatch_begin_us": None,
        "t8_fifo_write_complete_us": None,
        "t9_main_receives_load_core_us": None,
        "t12_rbf_open_begin_us": None,
        "t13_rbf_open_success_us": None,
        "t2_source_open_us": None,
        "t3_source_read_complete_us": None,
        "t4_configuration_start_proxy_us": None,
        "t5_configuration_return_us": None,
        "post_configuration_sync_us": None,
        "t6_core_ready_us": None,
        "t7_controller_rebind_us": None,
        "t8_playing_us": None,
        "remote_playing_us": None,
    }
    generation = None
    final = None
    while time.monotonic() < deadline:
        observed = now_us()
        status = remote_status()
        transport = status.get("transport") or {}
        current_generation = transport.get("switchGeneration")
        if current_generation and current_generation != before_transport["switchGeneration"]:
            generation = current_generation
            if stamps["t0_request_accepted_us"] is None:
                stamps["t0_request_accepted_us"] = observed
            if transport.get("switchState") == "SWITCHING" and stamps["t1_switching_us"] is None:
                stamps["t1_switching_us"] = observed
        events = parse_main_events(requested, profile, source)
        mapping = {
            "source_open": "t2_source_open_us",
            "source_read_complete": "t3_source_read_complete_us",
            "configuration_return": "t5_configuration_return_us",
            "post_configuration_sync": "post_configuration_sync_us",
        }
        for event, key in mapping.items():
            if event in events:
                stamps[key] = events[event]
        if stamps["t3_source_read_complete_us"] is not None:
            stamps["t4_configuration_start_proxy_us"] = stamps["t3_source_read_complete_us"]
        if generation:
            latency = parse_latency_events(generation)
            latency_mapping = {
                "t0_controller_request_accepted": "t0_request_accepted_us",
                "t1_supervisor_request_observed": "t1_supervisor_request_observed_us",
                "t2_supervisor_enters_switching": "t2_supervisor_enters_switching_us",
                "t3_target_profile_resolved": "t3_target_profile_resolved_us",
                "t4_target_rbf_path_resolved": "t4_target_rbf_path_resolved_us",
                "t5_old_session_quiesce_begin": "t5_old_session_quiesce_begin_us",
                "drain_stable_zero_begin": "drain_stable_zero_begin_us",
                "drain_stable_zero_complete": "drain_stable_zero_complete_us",
                "t6_old_session_quiesce_complete": "t6_old_session_quiesce_complete_us",
                "start_modified_main_begin": "start_modified_main_begin_us",
                "start_modified_main_complete": "start_modified_main_complete_us",
                "verify_modified_main_begin": "verify_modified_main_begin_us",
                "verify_modified_main_complete": "verify_modified_main_complete_us",
                "t7_fifo_dispatch_begin": "t7_fifo_dispatch_begin_us",
                "t8_fifo_write_complete": "t8_fifo_write_complete_us",
                "t9_main_receives_load_core": "t9_main_receives_load_core_us",
                "t12_rbf_open_begin": "t12_rbf_open_begin_us",
                "t13_rbf_open_success": "t13_rbf_open_success_us",
            }
            for event, key in latency_mapping.items():
                if event in latency:
                    stamps[key] = latency[event]
            ready = supervisor_ready(generation)
            if ready is not None:
                stamps["t6_core_ready_us"] = ready
            # The controller's stdout is fully buffered on this hardware. The
            # Main-mediated, generation-bound index-1 acknowledgment is the
            # first durable proof that rebind completed and the new session was
            # issued, so it is the T7 authority rather than a buffered trace.
            if stamps["t7_controller_rebind_us"] is None and controller_ready(generation):
                stamps["t7_controller_rebind_us"] = observed
        if (status.get("state") == "PLAYING" and status.get("path") == TRACKS[profile]
                and transport.get("currentProfile") == expected
                and generation == current_generation):
            if stamps["t8_playing_us"] is None:
                stamps["t8_playing_us"] = observed
            stamps["remote_playing_us"] = now_us()
            final = status
            break
        time.sleep(0.005)
    if final is None:
        raise TimeoutError(f"{from_profile}->{expected} did not reach PLAYING")
    required = [key for key, value in stamps.items()
                if key not in ("t1_switching_us",) and value is None]
    if required:
        raise RuntimeError(f"missing timestamps: {required}")
    base = int(stamps["t0_request_accepted_us"])
    stamp = lambda key: int(stamps[key])
    result = {
        "source": source,
        "from": from_profile.removeprefix("PROFILE_"),
        "to": profile,
        "generation": generation,
        "track": TRACKS[profile],
        "timestamps_us": stamps,
        "durations_ms": {
            "request_to_accept": (base - requested) / 1000,
            "accept_to_open": (stamp("t13_rbf_open_success_us") - base) / 1000,
            "t0_to_t13": (stamp("t13_rbf_open_success_us") - base) / 1000,
            "request_observation": (stamp("t1_supervisor_request_observed_us") - base) / 1000,
            "fade_and_tick_to_switching": (stamp("t2_supervisor_enters_switching_us") -
                                             stamp("t1_supervisor_request_observed_us")) / 1000,
            "switching_to_quiesce": (stamp("t5_old_session_quiesce_begin_us") -
                                       stamp("t2_supervisor_enters_switching_us")) / 1000,
            "stop_to_zero": (stamp("drain_stable_zero_begin_us") -
                              stamp("t5_old_session_quiesce_begin_us")) / 1000,
            "stable_zero": (stamp("drain_stable_zero_complete_us") -
                             stamp("drain_stable_zero_begin_us")) / 1000,
            "quiesce_total": (stamp("t6_old_session_quiesce_complete_us") -
                               stamp("t5_old_session_quiesce_begin_us")) / 1000,
            "start_modified_main": (stamp("start_modified_main_complete_us") -
                                     stamp("start_modified_main_begin_us")) / 1000,
            "verify_modified_main": (stamp("verify_modified_main_complete_us") -
                                      stamp("verify_modified_main_begin_us")) / 1000,
            "quiesce_to_fifo": (stamp("t7_fifo_dispatch_begin_us") -
                                 stamp("t6_old_session_quiesce_complete_us")) / 1000,
            "fifo_write": (stamp("t8_fifo_write_complete_us") -
                            stamp("t7_fifo_dispatch_begin_us")) / 1000,
            "fifo_delivery": (stamp("t9_main_receives_load_core_us") -
                               stamp("t8_fifo_write_complete_us")) / 1000,
            "main_dispatch_to_open": (stamp("t12_rbf_open_begin_us") -
                                      stamp("t9_main_receives_load_core_us")) / 1000,
            "rbf_open_syscall": (stamp("t13_rbf_open_success_us") -
                                 stamp("t12_rbf_open_begin_us")) / 1000,
            "rbf_read": (int(stamps["t3_source_read_complete_us"]) - int(stamps["t2_source_open_us"])) / 1000,
            "configuration": (int(stamps["t5_configuration_return_us"]) - int(stamps["t4_configuration_start_proxy_us"])) / 1000,
            "post_config_sync": (int(stamps["post_configuration_sync_us"]) - int(stamps["t5_configuration_return_us"])) / 1000,
            "post_config_ready": (int(stamps["t6_core_ready_us"]) - int(stamps["t5_configuration_return_us"])) / 1000,
            "ready_to_rebind": (int(stamps["t7_controller_rebind_us"]) - int(stamps["t6_core_ready_us"])) / 1000,
            "rebind_to_playing": (int(stamps["t8_playing_us"]) - int(stamps["t7_controller_rebind_us"])) / 1000,
            "accept_to_playing": (int(stamps["t8_playing_us"]) - base) / 1000,
            "request_to_remote_playing": (int(stamps["remote_playing_us"]) - requested) / 1000,
        },
    }
    print(json.dumps(result, sort_keys=True), flush=True)
    return result


def ensure_profile(profile: str, source: str, timeout: float) -> None:
    status = remote_status()
    if status.get("transport", {}).get("currentProfile") == PROFILES[profile] and \
            status.get("state") == "PLAYING" and status.get("path") == TRACKS[profile]:
        return
    if status.get("transport", {}).get("currentProfile") == PROFILES[profile]:
        subprocess.run([CTL, "play", TRACKS[profile]], check=True)
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            status = remote_status()
            if status.get("state") == "PLAYING" and status.get("path") == TRACKS[profile]:
                return
            time.sleep(0.01)
        raise TimeoutError("same-profile setup did not reach PLAYING")
    invoke(profile, source, timeout)


def metric_stats(values: list[float]) -> dict[str, float]:
    ordered = sorted(values)
    return {
        "min": min(values),
        "median": statistics.median(values),
        "mean": statistics.mean(values),
        "p95": ordered[max(0, math.ceil(len(ordered) * 0.95) - 1)],
        "stdev": statistics.pstdev(values),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", choices=("fat", "tmp"), required=True)
    parser.add_argument("--trials", type=int, default=10)
    parser.add_argument("--timeout", type=float, default=30)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.trials < 10:
        raise SystemExit("at least 10 trials are required")
    for path in TRACKS.values():
        candidate = Path(path)
        if not candidate.is_file() or candidate.is_symlink():
            raise RuntimeError(f"invalid benchmark track: {path}")
    # Prevent a short benchmark selection from auto-advancing between samples.
    # Every explicit play below still exercises the normal switch owner.
    subprocess.run([CTL, "repeat", "one"], check=True)
    subprocess.run([CTL, "shuffle", "off"], check=True)

    results = []
    for left in ("A", "B"):
        ensure_profile(left, args.source, args.timeout)
        for _ in range(args.trials):
            results.append(invoke("C", args.source, args.timeout))
            results.append(invoke(left, args.source, args.timeout))

    summary: dict[str, object] = {}
    for pair in ("A-C", "C-A", "B-C", "C-B"):
        source, target = pair.split("-")
        selected = [item for item in results if item["from"] == source and item["to"] == target]
        if len(selected) != args.trials:
            raise RuntimeError(f"wrong trial count for {pair}: {len(selected)}")
        summary[pair] = {
            key: metric_stats([item["durations_ms"][key] for item in selected])
            for key in selected[0]["durations_ms"]
        }
    document = {
        "schema": "MegaVGMPlayer-RBF-benchmark-v1",
        "clock": "CLOCK_MONOTONIC",
        "source": args.source,
        "trials_each_direction": args.trials,
        "tracks": TRACKS,
        "results": results,
        "summary": summary,
    }
    args.output.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    args.output.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n")
    print(args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
