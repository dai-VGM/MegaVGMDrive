# Genesis Audio HDL Dependencies

This directory contains the minimal Genesis/Mega Drive audio HDL files copied
from the Genesis_MiSTer project for local experiments with `rtl/md_sound_module.sv`.

Source:
- Repository: https://github.com/MiSTer-devel/Genesis_MiSTer
- Local source path used for this copy: `/private/tmp/Genesis_MiSTer/rtl/`

Layout:
- `jt12/`: YM2612/YM3438-compatible FM core files
- `jt12/mixer/`: jt12 mixer and rate-conversion files
- `jt12/adpcm/`: jt12 ADPCM helper dependency
- `jt89/`: SN76489-compatible PSG core files
- `filters/`: Genesis audio filter files

The copied source files are kept as upstream-derived dependencies. Keep their
original headers and consult the upstream Genesis_MiSTer project for licensing
and attribution details.
