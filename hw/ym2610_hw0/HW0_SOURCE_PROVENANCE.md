# YM2610 HW-0 source provenance

This directory defines a lab-only MiSTer project for the completed standard
YM2610 standalone path. It is isolated from `VGM_MD_MiSTer.qsf`, `files.qip`,
and production `rtl/emu.sv`.

## JT10 authority

- Upstream JT10 baseline: jotego/jt12 commit
  `6d51e0b6f64728c73408079b2f5ffe911bfd88a9`.
- Immutable pin: `tb/jt10_pinned/6d51e0b6/` (15 files), checked against
  `tb/jt10_compat/pristine_blobs.tsv` by Git blob and SHA-256.
- Formal PC-GATE authority:
  `rtl/genesis_audio/jt10_ym2610/PC_GATE_PROVENANCE.md`.
- The five formal overlay files are compiled directly:
  `jt10_adpcm_div.v`, `jt10_adpcm_drvB.v`, `jt10_adpcmb_cnt.v`,
  `jt10_adpcmb_gain.v`, and `jt10_adpcmb_interpol.v` under
  `rtl/genesis_audio/jt10_ym2610/adpcm/`.
- Seven unchanged pin leaves are compiled directly:
  `jt10_adpcm.v`, `jt10_adpcm_acc.v`, `jt10_adpcm_cnt.v`,
  `jt10_adpcm_dbrom.v`, `jt10_adpcma_lut.v`, `jt10_adpcmb.v`, and
  `jt10_cen_burst.v`.

The direct `tb/` references are temporary and HW-0-only. A future production
NeoGeo profile must promote every selected pristine source into a maintained
`rtl/` location. The pristine pin must not be edited. A formal overlay module
and the pristine same-name module must never be compiled together.

## Name-separated compatibility derivatives

The local JT12 fork is not interface-compatible with pristine upstream JT10.
Existing tracked generators establish the verified Phase 0–4 compatibility
tree; they were not changed for HW-0. The following synthesis sources are
name-separated derivatives of that tree so they cannot collide with production
JT12 modules:

| HW-0 module | Authority and allowed difference |
|---|---|
| `ym2610_hw0_jt12_top` | local `jt12_top.v` after `apply_local_interface_compat.py` and declaration-order compatibility; module/child names changed, plus status-only taps |
| `ym2610_hw0_jt12_reg` | local `jt12_reg.v` after `apply_jt10_counter_reset_compat.py`; module name changed |
| `ym2610_hw0_jt12_mmr` | local `jt12_mmr.v`; module and register-child names changed only |
| `ym2610_hw0_jt10_acc` | pristine standard YM2610 four-FM-channel accumulator after the existing local reset-port transform; module name changed |
| `ym2610_hw0_jt10_adpcm_drvA` | pristine driver logic; module and gain-child names changed only |
| `ym2610_hw0_jt10_adpcm_gain` | pristine logic after declaration-order-only compatibility; module name changed |

This is not a YM2610B accumulator: the standard four-audible-FM-channel
mapping remains intact. The ADPCM-A mask is fixed to `6'h3f`; the ADPCM-B MMR
command-update pulse, resettable standard accumulator, and JT10 FM sequencer
reset are the existing compatibility contract. No existing compatibility
source was modified.

## PC-GATE lifecycle

PC-GATE remains the only ADPCM-B lifecycle overlay. It resets cold-start
interpolator state, qualifies requests with active/restart ownership, clears
stale pipeline ownership on accepted START, stops request/audio ownership when
inactive, and retains the verified natural-end and command-RESET behavior.
PC-CLEAR is absent.

## HW-0 startup and pacing boundary

Human-facing timing is owned only by the HW-0 top/sequencer. The public JT10
sample-valid output remains six CENs wide and repeats every 144 CENs. HW-0
converts its rising edge into one `clk_sys`-cycle `sample_tick`; boot,
announcement, audible dwell, zero verification, inter-source silence, and
final silence counters consume only that tick. No JT10, JT49, formal PC-GATE,
ROM, gain, pan, or register value is changed by pacing.

The shell reset is `RESET | status[0] | !pll_locked`; asynchronous assertion
and a three-stage synchronous release are local to the HW-0 top. PLL unlock
also owns the separately synchronized video-timing reset. Soft reset changes
the explicit display phase to navy but does not reset the native-video pixel
counters. The final audio mute is after the complete JT10 left/right output.
It is asserted during reset, pre-ready, boot, pre-roll, and silence only.
After a stop write it stays deasserted until 32 consecutive public samples
prove internal left/right zero; ADPCM-B additionally requires request and
active status clear. A timeout halts, mutes, and selects red.

FM retains the old ordered write stream with only its final key-on scheduled
as START after the explicit pre-roll. SSG retains its old single continuous
four-write period/mixer/volume program and schedules that complete program
after pre-roll. Because the JT49 tone divider remains free-running while
muted, HW-0 also waits for `chip_cycle_mod432=428` and the established
128-public-sample tone phase before launching those writes. The ADPCM scheduler
alignment values, all register data, ROM byte rule, measurement windows, and
expected audio hashes remain unchanged.

## ROM authority

Both small combinational ROM functions reproduce the Phase 3A/4A primary byte
rule:

`byte = ((address[7:0] * 73) + (address[15:8] * 29) + 41) mod 256`

The RTL expresses 73 and 29 as shifts/adds. ADPCM-A forms the 24-bit logical
address from `{bank,address}`; ADPCM-B consumes its native 24-bit address. The
response is zero-wait-state and known for every valid request.

## MiSTer project adapter

`sys_ym2610_hw0.tcl` is a mechanical copy of `sys/sys.tcl`. Device, pin, I/O,
HPS, audio, video, and timing assignments are byte-identical. Only these
project-location changes are permitted and automatically checked:

- post-flow script: `sys/build_id.tcl` → `../../sys/build_id.tcl`;
- shell QIP: `sys/sys.qip` → `sys_ym2610_hw0.qip`;
- the production `jtag.cdf` assignment is omitted because that optional file
  is absent from this repository and is not part of RBF generation.

`sys_ym2610_hw0.qip` is the same MiSTer shell source list with paths rebased to
`../../sys/` and the existing production `../../rtl/pll.qip`. The static audit
checks both adapters mechanically, checks every path, and rejects absolute or
production-audio dependencies.

Production `sys/sys.qip` selects `sys/pll_q17.qip` for Quartus 17. That bundle
registers four `QIP_FILE` authorities: `rtl/pll.qip`, `sys/pll_hdmi.qip`,
`sys/pll_audio.qip`, and `sys/pll_cfg.qip`. The HW-0 sys adapter already owns
the first. The HW-0 QSF registers the remaining three with project-relative
paths. Their generated Verilog and nested constraint QIPs remain owned by the
outer QIPs and are not registered a second time. `sys/sys_top.sdc`, including
`derive_pll_clocks` and the HDMI/audio clock groups, remains supplied exactly
once by `sys_ym2610_hw0.qip`. No Intel-generated source is modified.
