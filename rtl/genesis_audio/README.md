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
