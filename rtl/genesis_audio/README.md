# Genesis Audio HDL Dependencies

This directory contains the minimal Genesis/Mega Drive audio HDL files copied
from the Genesis_MiSTer project for local experiments with `rtl/md_sound_module.sv`.

Source:
- Repository: https://github.com/MiSTer-devel/Genesis_MiSTer
- Local source path used for this copy: `/private/tmp/Genesis_MiSTer/rtl/`

Layout:
- `jt12/`: YM2612/YM3438-compatible FM core files
- `jt49/`: YM2149-compatible SSG files used by the YM2203 configuration
- `jt12/mixer/`: jt12 mixer and rate-conversion files
- `jt12/adpcm/`: jt12 ADPCM helper dependency
- `jt89/`: SN76489-compatible PSG core files
- `filters/`: Genesis audio filter files

The copied source files are kept as upstream-derived dependencies. Keep their
original headers and consult the upstream Genesis_MiSTer project for licensing
and attribution details.

## YM2203 dependency provenance

The YM2203-only dependencies are based on the revisions used together by
upstream JT12. Their original license headers are unchanged.

- `jt12/jt03_acc.v`
  - repository: https://github.com/jotego/jt12
  - commit: `6d51e0b6f64728c73408079b2f5ffe911bfd88a9`
  - upstream base Git blob: `32ace148af6e21cf430647edcef218e492a210b6`
  - local change: connect the existing active-high `rst` input to an opt-in
    resettable `jt12_single_acc` so the YM2203 mono accumulator cannot retain
    an unknown simulation value across reset
- `jt12/jt12_single_acc.v`
  - local change: add a default-disabled active-high reset parameter and input
  - reset is enabled only by `jt03_acc`; the existing YM2612 accumulator keeps
    the pre-existing arithmetic path with reset disabled
- `jt49/`
  - repository: https://github.com/jotego/jt49
  - commit: `9d097f1eefad3530567b71f13016f6e8546a4bb5`
  - upstream base Git blobs:
    - `jt49.v`: `d91dbf6a075a5923a65d8d9977706244af7da994`
    - `jt49_bus.v`: `b7639d9fc121e43ee691336edb3c39802d9b8b4f`
    - `jt49_div.v`: `ac4564ce9add8056387d35c6ee7cf4643459ef11`
    - `jt49_cen.v`: `671eceb232251302bc063fc9168a9566a5a9ae64`
    - `jt49_eg.v`: `46dd62ace1f080bce6678469ca0b8b99b0c2b74e`
    - `jt49_exp.v`: `412a3f8aedb7967d24a7cfe2b1ffcf48580433fb`
    - `jt49_noise.v`: `ffc1fb978e55157d7d36ca11e2feea6b3229fd63`
  - local reset-only changes for deterministic startup without requiring
    `clk_en` pulses while reset is asserted:
    - `jt49.v`: reset `Amix`, `Bmix`, `Cmix`, `logA`, `logB`, `logC`, and
      `log`
    - `jt49_cen.v`: reset `cen16` and `cen256`
    - `jt49_eg.v`: reset `env`, `last_step`, and `rst_latch`
    - `jt49_exp.v`: add and connect `rst_n`, and reset the LUT output `dout`
    - `jt49_noise.v`: reset `noise` and `last_en`
  - the LUT contents, divider ratios, mixer arithmetic/order, volume model,
    output widths/scaling, and post-reset sample timing are unchanged
  - `jt49_bus.v` and `jt49_div.v` remain byte-identical to their upstream
    base blobs above

## YM2203 deterministic FM startup reset

The FM pipeline is based on JT12 commit
`6d51e0b6f64728c73408079b2f5ffe911bfd88a9`.  The local Genesis fork now
enables an architectural startup reset only when `num_ch == 3`,
`use_pcm == 0`, and `use_adpcm == 0`; `use_ssg` is intentionally not part of
the condition.  The reset uses the existing active-high `rst` and does not
require chip-CEN priming while reset is asserted.

Modified upstream-derived files and their JT12 base blobs:

- `jt12/jt12_top.v`: `c1a0c3377e6822c1db4a35319721a9cc79d5a8ed`
- `jt12/jt12_mmr.v`: `9f3642949aebd508c4f4ea4daa71568109ce091b`
- `jt12/jt12_reg.v`: `89b2017c42c72655c331cf3cbda3af9a149c9782`
- `jt12/jt12_kon.v`: `db4b82cbb266ed906e0cde90ef44fa1b533068e6`
- `jt12/jt12_pg.v`: `913a7398105a3620bf7811f3acb2016481a60e0f`
- `jt12/jt12_eg.v`: `fbf10640de335d243112568afe0ada9b0fa5151a`
- `jt12/jt12_op.v`: `d0d29816219c851c5969ac2b98ba26705d5d0bdf`
- `jt12/jt12_logsin.v`: `897437544d5e7d52bb8f1744886aac0f1f67ac07`
- `jt12/jt12_exprom.v`: `beca296362fe2af78fc51e931cd811334fcc9c50`

Before this reset change, the Genesis-fork baseline blobs at local commit
`24c4a0cdb8b0ae1940593fd26ec547c16bd9a8cf` differed from the JT12 base for
`jt12_top.v` (`37dc34c41b8deebc33750365bb260d23418f30b7`), `jt12_mmr.v`
(`90b70b2284aea427c7cb390bb421697765dc2108`), `jt12_reg.v`
(`857fd95bfbaa3d12ed4ebce4d3aee06f9c2b941e`), `jt12_kon.v`
(`3a0328d017ceb779d00fac0dcd49dfc8b79d99a2`), and `jt12_op.v`
(`060b215c896f3e985c21e5d77dbff6e69f79d26d`).  These files are therefore
not byte-identical to the JT12 base even before the startup reset change.

The YM2203-only reset covers the three-channel sequencer and feedback/key-on
pipeline, PG keycode/detune/increment registers, EG rate/step/attack/SSG and
inactive-envelope pipeline, resetless EG counter delay, operator feedback,
phase-modulation, mantissa/exponent and result pipeline, and the registered
log-sine/exponential outputs.  Reset values are zero except for the inactive
envelope and its top-level delay, which use `10'h3ff` to match the existing
envelope-state reset convention.

The ROM tables, FM arithmetic, widths, slot scheduling, feedback calculation,
scaling, and pipeline stage count are unchanged.  The compile-time reset
branch is disabled for the existing six-channel YM2612 configuration, so its
startup and normal audio path retain the pre-existing implementation.
