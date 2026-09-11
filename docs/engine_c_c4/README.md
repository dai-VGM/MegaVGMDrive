# Engine C C4 — common transport candidate

Dedicated branch/worktree: `engine-c-phase-c4` /
`/Users/daizo/Projects/MegaVGMPlayer_EngineC_PhaseC4`.
Base: C3 `41a7a96ec057bfe243cefb7b83faff508682caf4` (includes C2 capacity
`c9fc9a1b35740c616f72af5116359ee41db944e7`).

This is a **simulation-verified transport candidate, not a hardware-validated
production Engine C**. No Supervisor/Profile C registration, host classifier,
controller, Remote, Main, importer, converter or production A/B changes.
No macOS Quartus invocation and no RBF produced here.

## Rooted residual audit

| Boundary | C3 lab | C4 adaptation |
| --- | --- | --- |
| index 1 | Direct upload/profile reset | Production owner admits only after replacement reaches zero |
| index 2 | Ignored by stream loader | Existing `MV/02` policy and FADE_ONLY parser |
| Session/status | No published production session | Exact B compatibility adapter and reference status v2 publisher |
| Parser EOF | `busy=0` immediately gates audio | Parser stops writes; SID keeps clocking, common fade completes first |
| Raw qualified audio | AND parser busy | Independent of parser busy; final mix goes through common gain |
| Transport END | Raw scheduler done | Owner finish, profile terminal latch, session-qualified ENDED |
| DDR timeout | VGM backend can synthesize byte `0x66` | C4 detects fabricated raw responses and publishes explicit I/O FATAL |

## Architecture and ownership

```text
HPS index 1/2
    |
    +-- exact A/B megavgm_transport_owner (single fade owner)
    |       | admitted index 1; ioctl_wait during replacement
    |       v
    |   golden_shell_transport ----> reference status v2 ----> HPS/Main
    |       | session/load owner
    |       v
    |   frozen physical upload / C2 DDR arbiter + record store
    |       |
    |   C4 profile -> frozen C3 strict loader -> C4 scheduler admission
    |                                            |
    |                                      frozen C3 CE arithmetic
    |                                            |
    |                                      frozen SID wrapper/RTL
    |                                            |
    +-- gain 0..256 ---------------------- qualified final mono mix
                                                 |
                                         common signed gain -> emu L/R
```

The compatibility transport owns the sole 32-bit session counter, load begin /
complete / accepted / session-start / playback-start, and sticky session-qualified
done. The C4 profile does not invent a second session or fade engine.
Legacy VGM-specific debug/PC ports not used by SID remain inert; the meaningful
load/start/end/session counters are connected. Main observes the real status v2
record, not those legacy VGM debug fields.

### Index 1 and replacement

An admitted rising index-1 download increments the resident session exactly once
and clears old completion ownership. The publisher first observes that new
session as LOADING. A post-acceptance validation/init failure belongs to this
session as FATAL, with no rollback. Reset-rejected and non-index-1 transfers do
not allocate a session.

During an audible replacement, the unmodified common owner asserts ioctl_wait
and withholds both download and write from the physical upload/profile. SID
continues consuming its old stream and clocking during the existing fade.
Only at gain zero is the new download admitted. Profile reset/validation/model
latching/qualification then follow the unchanged C3 path. A pure replacement
does not manufacture an old-session ENDED; an EOF/FADE_ONLY join uses the exact
owner's completion rule, with new-load priority in the compatibility adapter.

### Index 2

Exactly the existing four-byte records (committed at transfer falling edge):

```text
4D 56 02 00    policy off
4D 56 02 01    policy two loops
4D 56 02 02    FADE_ONLY
```

No index-2 download/write reaches the stream upload, SID reset, session counter,
model/clock latch or audio-ready lifecycle. Policy transfer completion cannot
re-arm gain. In C4, native-loop signals are tied inactive: LOOP_VALID files are
strictly rejected, so the unchanged loop-policy parser has no SID loop to act on.
Malformed/unknown index-2 records retain the existing ignored-command behavior.

### EOF / FADE_ONLY

Raw `parser_done` is distinct from `profile_done` and published `player_done`.
Natural EOF halts new WRITE events, **not SID CE or pipeline publication**.
The profile remains playback-active through the common tail. Capture-limit EOF
has the same transport behavior without changing its MVGMSID metadata.

FADE_ONLY addresses the current PLAYING session; it does not alter/reset the
parser/stream/session while fading. At owner completion, a terminal profile latch
stops further event consumption and publishes done once. This is the scheduler's
new `halt` admission input, not a reset or a clock pause. It is inactive during
ordinary playback and the fade. SID CE/filter/publication continue after halt;
the ended session remains inaudible until the next accepted index-1 load.

Duplicate FADE_ONLY never restarts the ramp. EOF joining FADE_ONLY, replacement
joining a fade, and policy after END all retain the imported owner semantics.

### Exact fade timing

No envelope arithmetic was changed. At the existing 20 MHz system clock:

```text
MODE5_TRACK_FADE_CYCLES = 20,000,000 / 10 = 2,000,000
step cycles = ceil(2,000,000 / 256) = 7,813
full ramp = 256 * 7,813 = 2,000,128 SYS cycles = 100.0064 ms
```

When parser EOF arrives during an already active clock-paced fade, the reference
owner consumes one additional clock for that join: 2,000,129 cycles = 100.00645 ms.
The tests assert both values; they do not substitute an idealized 100.000 ms.
Empty/no-audio EOF retains the production owner's immediate zero/END path.

### Audio qualification

The C3 SID reset/filter/pipeline cleanup and sample-commit one-shot are unchanged.
No `state==15` level-valid, extra wait, sample-count warmup, attack ramp or mute
delay is added. `audio_ready` and profile/session permission qualify the raw mix;
the common owner supplies final signed gain (unity 256). As in B, the product is
arithmetic-shifted by 8. The existing signed SID 18-to-16-bit width adaptation
and emu output stage remain unchanged. Reset/load/FATAL immediately force zero.

PAL/NTSC CE and WRITE phase are inherited: native cycle is authoritative, WRITE
at cycle n is consumed on that cycle's edge, new register affects subsequent
oscillator evaluation. Model/clock latch only after strict preflight validation.
PAL 985248 Hz and NTSC 1022727 Hz (including equivalent rational declarations)
remain C3-exact. No 44.1 kHz quantization is introduced.

### Stop and FATAL

Stop uses the existing emu core reset request (`RESET | status[0] | !pll_locked`)
and reset hold. It immediately mutes, clears transport to IDLE/session 0 and
creates no ENDED. The existing power-on/reset hold is unchanged; begin lab
commands only after fresh valid status is available.

Validation errors keep C3 error codes; scheduler underflow is 0x80, descriptor
corruption/watchdog is 0x81. Common upload overflow is F2. C4 I/O faults enter the
unmodified publisher's higher-priority common load/I/O error F1. Thus a native
0x80 fault may later be superseded by F1 if the physical return never arrives;
it remains the same session's FATAL, not ENDED.

The C4 I/O observer has no normal-path ready/CE feedback:

- Raw `mem_rd_valid` must follow a real upload-client DDR return. The backend's
  synthetic timeout/out-of-range `0x66` is detected by return provenance, **not
  by comparing the byte value**; a genuine data byte 0x66 remains legal.
- Physical raw read response budget is the existing backend's 1024 clocks.
- Descriptor response and stuck-BUSY budgets use the existing C2 store's one-SYS-
  second watchdog, not a shorter arbitrary startup latency bound.
- On explicit I/O failure only, remaining host bytes are discarded and backend
  wait is masked, allowing Main to finish its transaction and observe FATAL.
- Outstanding DDR transactions are not silently reset/rebound by a new session;
  the existing arbiter retains drain ownership. A permanently failed external
  memory transaction requires core reset/recovery, not a fabricated success.

The logical limit remains exactly 4 MiB. No address packing/capacity expansion.

## Frozen reference provenance

The following sources are copied **byte-for-byte** from production B lineage
`c59009f320f2e1d8db9e3582ee04a61ed18d47a3`:

| C4 source | Original source | SHA-256 |
| --- | --- | --- |
| `rtl/transport_v1_3/megavgm_transport_owner.sv` | same path | `4f441e86e5fa191c592ad40f895510a52b2bbb8d7ddd6af46e99d066bb02bd68` |
| `rtl/transport_v1_3/owner_body.svh` | same path | `79ca0c96ff2e1b59798ac734a706bfa0f80a3f9915b87523e4642e305748b7c4` |
| `rtl/engine_c_c4/transport.sv` | `rtl/golden_player_shell_v1_2_compat/transport.sv` | `8b46ebae3be5b2d4d25fc0e87b1ca83bf47a0f9305a29ffce9ec36a4257fa564` |
| `rtl/engine_c_c4/megavgm_playlist_status_export.sv` | `rtl/megavgm_playlist_status_export.sv` | `f9c81037075270b5a7e51d9913cc49f2966a0327ea6c3501456209839ef3d72b` |

The owner body also matches A `67d7fa2922114852d315536daac79f83a0c40f1b`.
No shared A/B source is edited. Legacy owner and status ABI testbenches are
copied from the same B worktree into the C4 test directory, without behavioral
changes (`tb_legacy_owner`, `tb_fade_only_owner`, `tb_abi`, `tb_status`).

SID source/license/reset provenance remains in
[C2 provenance](../engine_c_c2/PROVENANCE.md) and
[reset audit](../engine_c_c2/RESET_AUDIT.md). C4 makes no new claim that unresolved
upstream license provenance is cleared for redistribution.

## Reproduction and Windows project

From the C4 worktree, using existing C3 test artifacts (or regenerate them in a
separate scratch output directory with the frozen C3 test tool):

```sh
python3 tools/engine_c_c4/run_tests.py --only all
python3 tools/engine_c_c4/audit.py
python3 -m unittest discover -s tools/engine_c_c0 -p 'test_*.py'
MVGMSID_C1_NATIVE_HELPER=/path/to/c1/sid_capture python3 -m unittest discover -s tools/engine_c_c1 -p 'test_*.py'
```

Results and generated original synthetic/PCM artifacts default to
`/Users/daizo/Projects/MegaVGMPlayer_EngineC_PhaseC4_Artifacts/`.
C3 WAVs and real SID artifacts are not modified or committed.

Windows QPF:
`hw/engine_c_c4/MegaVGMPlayer_EngineC_C4_Transport_MiSTer.qpf`.

Run on **Windows only**, from that directory after synchronizing the complete
C4 worktree:

```text
quartus_sh --flow compile MegaVGMPlayer_EngineC_C4_Transport_MiSTer
```

Expected output (not generated/verified on macOS):
`hw/engine_c_c4/output_files/MegaVGMPlayer_EngineC_C4_Transport_MiSTer.rbf`.

QSF is self-contained, with no remove/subtract overlay. C3 device/pins/PLL/SDC/
platform assignments are unchanged. Only versioned SID adapter source selection
and the established transport/status macros differ. Do not overwrite A/B/C3
PASS RBFs or rename this candidate to a production engine filename.

## Hardware checklist — all C4 items still unverified

1. Windows Full Compilation, resource/timing report review, record RBF SHA.
2. Load this distinct candidate manually in the lab; confirm a fresh status v2
   IDLE baseline. Do not register Profile C or use production automatic routing.
3. Repeat C3's PAL/6581, PAL/8580, NTSC/6581, NTSC/8580 files. Return to Commando
   PAL/6581 and compare; include the already-owned digi/high-density SID files
   within the unchanged 4 MiB limit.
4. Natural/capture-limit EOF: SID tail remains audible through the common fade,
   then zero and same-session ENDED once. No premature busy-edge cut or pop.
5. For command tests, confirm **modified `MiSTer.megavgm` is actually running**
   with the C4 candidate resident under a manual lab launch. Stock Main's
   `/dev/MiSTer_cmd` existence alone does not prove custom `load_file` support.
   No ordinary playlist controller should race these manual tests.
6. Send `4D 56 02 02` through existing Main `load_file 2`; check transfer log,
   ~100 ms common tail, same-session ENDED once, then >100 ms zero. Repeat the
   command and policy 00/01; verify no gain/reset/session rearm.
7. Replacement using existing `load_file 1 <file.mvg>`: Main waits for zero,
   then one new LOADING/session and qualified PLAYING. Repeat model/timing changes.
8. Stop during play/fade: immediate silence, no phantom END; next load clean.
9. Malformed/unsupported/LOOP_VALID/>4 MiB: new accepted session FATAL, no sound.
10. Repeated small/max-size loads: no stale sound, permanent mute or duplicate
    load/reset/END. Restore the previous lab/PASS RBF after testing.

Do not change Supervisor routes, Main, controller or Player to run this phase.
Automatic Profile C selection and mixed A/B/C playlists are a later phase.
