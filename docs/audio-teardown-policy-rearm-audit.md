# Ended-session audio re-opened by index-2 completion

Functional baseline: `4c4a77c3c67045cb295b8d7ed3d747ce80f29033`.

## Finding

**PROVEN in source and RTL simulation: classification C.** An ended session
can emit audio again after reaching zero, before the next accepted backend
`mode5_load_begin_pulse`. This is not a first-new-session-sample problem.
Hardware audible-noise elimination still requires the new Windows RBF test.

`playlist.cpp` issues the loop policy on index 2 before each index-1 load.
The old transition owner's re-arm branch tested the falling edge of **any**
host `ioctl_download`. Therefore:

1. Natural/loop-limit fade finishes: gain=0, released=1, ENDED.
2. Index-2 policy transfer finishes: released=0, gain=256 (wrong owner).
3. Next index-1 **request** sees audio_ever_open=1 and starts another fade.
4. `fade_active` overrides the busy/done audio gate, reopening the old lane.
5. Only after that extra 100 ms fade does the backend accept LOAD_BEGIN.

Thus the host transfer request precedes the pop, but the actual backend load
and new session follow it. This distinction explains apparent “pop then load”.
Prior stale-lane tests did not include index 2 between ENDED and the next load.

## Actual Credit VGM capture

Input: `/Users/daizo/Music/Space_Harrier_(Hang-On)/01 Credit.vgm`

- SHA-256: `3c69c76a7328bc6f0818e101fdf4dafb91038e92a19057e31587fb3fbb0d9656`
- Size 2983 bytes; header indicates YM2203 4 MHz, no loop.
- Actual consumed waits: 57595.
- Unforced production sound modules, production macros, DDR backend=1,
  single-outstanding DDR response model. Clock interpreted as 20 MHz.
- Natural/manual fade is the real 2,000,000 SYS-cycle parameter (rounded
  to 2,000,128 cycles by the existing 256-step implementation).
- This is a top-level RTL simulation, not a capture of physical I2S/analog
  audio. Outer startup timing is bypassed in this repeated-handoff harness.

Before fix, Natural EOF with the real index-2/index-1 sequence:

| Event | SYS cycle | Session | Gain | Final L/R |
|---|---:|---:|---:|---:|
| Parser EOF | 26131546 | 1 | 256 | 0 / 0 |
| Fade complete / ENDED | 28131675 | 1 | 0 | 0 / 0 |
| Index-2 completion wrongly re-arms | 28131687 | 1 | 256 | 0 / 0 |
| Next request starts a second fade | 28151689 | 1 | 256 | 0 / 0 |
| First cycle with reappearing output | 28190288 | 1 | 252 | 173 / 173 |
| Backend LOAD_BEGIN | 30151817 | 1→2 next edge | 0 | 0 / 0 |

Last muted / first emitted / next raw-valid samples:

| Ordinal | Cycle | Mixer L/R | Gain | Output L/R | Delta L/R |
|---:|---:|---:|---:|---:|---:|
| 87972 | 28190140 | 0 / 0 | 252 | 0 / 0 | 0 / 0 |
| 87973 | 28190460 | 176 / 176 | 252 | 173 / 173 | +173 / +173 |
| 87974 | 28190780 | 176 / 176 | 251 | 172 / 172 | -1 / -1 |

Maximum raw-valid delta **after zero and before LOAD_BEGIN**: 173 L/R.
The signal is the current session's YM2203 held contribution (704 before
arcade normalization), not new-session data. A smaller 0→176 step also
exists just after EOF during the first legitimate fade; that is distinct
from the proven post-zero, second-fade re-opening.

Without the intervening index-2 transfer, the old RTL stays silent. With it,
980276 SYS cycles violate the zero-until-next-load invariant. Fixed RTL:
20014 observed cycles, zero violations, no second fade.

## Minimal production correction

Only `rtl/mister_vgm_md_top.sv` is functionally changed: re-arm on falling
`mode5_ioctl_download` using its existing delayed register, i.e. completion
of an **accepted index-1** VGM transfer, rather than any host download.

No additional register, state machine, comparator array, ramp, mute delay,
chip modification, or host change. The existing internal-repeat branch is
unchanged. Index-2 updates still apply, but cannot release an ended session's
zero-gain transition owner.

## Validation and scope

- Focused policy re-arm A/B: old FAIL reproduced; fixed PASS.
- Real Credit Natural EOF: post-zero output held at zero until backend load.
- Real Credit Manual Next: 100 ms fade, no post-zero leak, one next load.
- Loop-limit comparison uses an explicitly **derived** Credit fixture whose
  loop starts at its data offset. Original file is not modified. Its 57595
  sample loop is shorter than two seconds, so the existing clamp applies.
  Before: 973440 leaking cycles; after: 20027 checked cycles, zero violations.
- Natural capture: all 87790 raw-valid samples through fade are bit-identical
  before/after. Derived-loop capture: all 163182 samples through fade are
  bit-identical. Predictor, fade start, duration, and curve are unchanged.
- 50-session transition stress: 50 loads/resets/starts, 39 ENDs, PASS for
  fixed RTL and historical 04910c0 comparison.
- Existing `run_mode5_audio_handoff_samples_ab.sh` nine profile/path cases
  PASS; lane qualification unit PASS. These injected stale-lane tests remain
  separate evidence from the unforced Credit capture.
- `run_mode5_cold_start_regressions.sh` PASS: cold handoff, actual-ready and
  early-load boundary, sound reset, mute gate, 50-session sequence, repeat
  policy, and v1/v2 playlist status export. Host sources were not modified.
- This real-track waveform test is YM2203, not a claim that three separate
  YM2151/YM2612/SegaPCM hardware waveforms were captured. The defective
  transition owner/gate and its correction are common to all sound lanes.

Commands:

```sh
bash tests/run_mode5_transition_stress_ab.sh --policy-rearm
bash tests/run_mode5_audio_handoff_samples_ab.sh --teardown \
  /absolute/output/directory '/absolute/path/01 Credit.vgm' NATURAL_EOF
python3 tools/analyze_mode5_teardown.py /absolute/output/directory/NATURAL_EOF.log \
  --expect-silent --csv-dir /absolute/output/directory/csv
```

Use `MANUAL_NEXT` or `LOOP_LIMIT` as the final argument for the other paths.
The analyzer exports the last 64 samples before EOF/zero and the entire
zero-to-load window; the observer also checks zero on every SYS cycle.

Local evidence: `/Users/daizo/Projects/audio-credit-teardown-policy-4c4a77c/`
(before) and `/Users/daizo/Projects/audio-credit-teardown-fixed/` (after).

## Windows handoff

Full Compilation: `MegaVGMPlayer_PlaylistLoopLab_MiSTer.qpf`.
Expected output: `MegaVGMPlayer_PlaylistLoopLab_MiSTer.rbf`.
QSF inheritance resolved 81 HDL assignments with no missing files; functional
top occurs once. Quartus was not run on macOS.

Retest Credit → automatic next, a real >2-second loop track → automatic next,
and manual Next, then Repeat/Shuffle. Verify the post-fade pop is gone and
the next track head remains intact. Main/Remote/controller artifacts do not
need changes for this correction.
