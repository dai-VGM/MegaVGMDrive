# MD Sound Module Hardware Bring-up Plan

This note records the first synthesizable hardware bring-up step after the RTL
simulation success.

The goal is not to build a full SD-card VGM player yet. The goal is only to
embed a tiny fixed VGM-like region in FPGA logic, stream it once into
`md_sound_module`, and confirm that `audio_l` / `audio_r` can produce sound on
real hardware.

## New HDL

```text
rtl/vgm_region_player.sv
```

This file contains two modules:

```text
vgm_region_player
md_sound_fixed_region_test
```

## vgm_region_player

`vgm_region_player` is a small synthesizable sequencer. It does not instantiate
the sound cores by itself. It only generates command handshakes compatible with
`md_sound_module`.

Inputs:

```text
clk
reset
start
audio_sample_valid
ym_cmd_ready
psg_cmd_ready
```

Outputs:

```text
ym_cmd_valid
ym_cmd_port
ym_cmd_reg
ym_cmd_data
psg_cmd_valid
psg_cmd_data
busy
done
pc_debug
last_cmd_debug
```

The sequencer supports only the small command subset needed by the built-in
test region:

```text
0x52 rr dd   YM2612 port 0 write
0x53 rr dd   YM2612 port 1 write
0x50 dd      SN76489 write
0x61 ll hh   wait n samples
0x62         wait 735 samples
0x63         wait 882 samples
0x70-0x7f    short wait 1..16 samples
0xe0 oooo    tiny PCM seek for local built-in PCM bytes
0x80-0x8f    generate YM2612 reg 0x2A DAC write, then wait low nibble
0x66         end
```

Wait timing counts `audio_sample_valid` rising edges from `md_sound_module`.

## Built-in Region

The fixed region is intentionally small, around a few thousand audio samples.
It is based on already successful simulation sequences:

- Simple YM2612 channel-1 FM tone setup from `TEST_YM_TONE`.
- Simple SN76489 channel-0 tone setup from `TEST_PSG_TONE`.
- Tiny DAC exercise using YM register `0x2B` enable and generated `0x2A` writes.

This is not a real song player. It is a smoke test for:

```text
fixed ROM commands
  -> vgm_region_player
  -> md_sound_module YM/PSG command inputs
  -> JT12 / JT89 / mixer
  -> audio_l / audio_r
```

## Convenience Wrapper

`md_sound_fixed_region_test` instantiates both:

```text
vgm_region_player
md_sound_module
```

This wrapper is meant for the first MiSTer/top-level experiment. A top-level can
instantiate it and route:

```text
clk/reset/start -> md_sound_fixed_region_test
audio_l/audio_r -> platform audio output
```

For a more complete design, instantiate `vgm_region_player` and
`md_sound_module` separately and keep the same command wiring.

## No Simulation-only Features

`rtl/vgm_region_player.sv` does not use:

```text
$fopen
$display
$dumpfile
/tmp paths
WAV dump logic
```

Those remain in the testbench only.

## Syntax Check

Standalone player check:

```sh
iverilog -g2012 -Wall -s vgm_region_player \
  -o /tmp/vgm_region_player_check.vvp \
  rtl/vgm_region_player.sv
```

Wrapper plus sound-core dependency check:

```sh
iverilog -g2012 -Wall -DSIMULATION -s md_sound_fixed_region_test \
  -o /tmp/md_sound_fixed_region_test_check.vvp \
  rtl/vgm_region_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v
```

Both checks passed. Remaining warnings are the existing JT12/timescale style
warnings already seen in earlier simulation work.

## Fixed Region Wrapper Simulation

Before moving to MiSTer hardware, the hardware wrapper can be exercised in a
small simulation testbench:

```text
tb/tb_md_sound_fixed_region_test.sv
```

This testbench instantiates `md_sound_fixed_region_test`, pulses `start`, waits
for `audio_sample_valid` rising edges, and writes 5000 stereo samples to:

```text
/tmp/md_sound_fixed_region_test_5k.txt
```

Build/run:

```sh
iverilog -g2012 -Wall -DSIMULATION -s tb_md_sound_fixed_region_test \
  -o /tmp/tb_md_sound_fixed_region_test.vvp \
  tb/tb_md_sound_fixed_region_test.sv \
  rtl/vgm_region_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v

vvp /tmp/tb_md_sound_fixed_region_test.vvp \
  > /tmp/tb_md_sound_fixed_region_test.log
```

WAV conversion:

```sh
python3 tools/audio_txt_to_wav/audio_txt_to_wav.py \
  /tmp/md_sound_fixed_region_test_5k.txt \
  /tmp/md_sound_fixed_region_test_5k.wav \
  --gain 2
```

Successful 5k result:

```text
wav_written_samples=5000
audio_sample_valid_edges=5000
pc=126
last_cmd=66
samples=5000
min=-2513
max=6022
nonzero=9916
rms=1856.53
clip_count=0
```

## MiSTer Bring-up Notes

- Feed `clk` with the same master-clock style expected by `md_sound_module`.
- Hold `reset` long enough for the existing JT12 reset stretcher to run.
- Tie `start` high for auto-play once after reset, or pulse it high manually.
- Observe `player_done` to confirm the fixed region has ended.
- Route `audio_l` / `audio_r` to the MiSTer audio path using the same signed
  sample convention expected by the surrounding top-level.

## Minimal MiSTer Top Wrapper

The project does not currently include a Quartus or MiSTer project skeleton:

```text
no .qpf
no .qsf
no .sdc
no MiSTer emu top-level yet
```

The first hardware-facing wrapper is:

```text
rtl/mister_vgm_md_top.sv
```

It instantiates:

```text
md_sound_fixed_region_test
  -> vgm_region_player
  -> md_sound_module
  -> JT12 / JT89 / mixer
```

Top-level ports:

```text
input  clk
input  reset_n
output signed [15:0] audio_l
output signed [15:0] audio_r
output audio_sample_valid
output player_busy
output player_done
output [9:0] player_pc_debug
output [7:0] player_last_cmd_debug
```

Behavior:

- `reset_n` is synchronized and converted to the active-high internal reset.
- After reset is released, the wrapper generates a one-clock `start` pulse.
- The fixed region plays once.
- `player_done` indicates that the built-in region has ended.
- No SD card, OSD, HPS bridge, or VGM file selection exists yet.

Syntax check:

```sh
iverilog -g2012 -Wall -DSIMULATION -s mister_vgm_md_top \
  -o /tmp/mister_vgm_md_top_check.vvp \
  rtl/mister_vgm_md_top.sv \
  rtl/vgm_region_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v
```

This check passed. The remaining warnings are the same existing JT12/Icarus
simulation warnings seen in previous checks.

## Minimal Top Wrapper Simulation

Before connecting `mister_vgm_md_top` to a MiSTer skeleton, it can be simulated
directly with:

```text
tb/tb_mister_vgm_md_top.sv
```

This testbench:

- Instantiates `mister_vgm_md_top`.
- Generates `clk`.
- Holds `reset_n` low, then releases it.
- Relies on `mister_vgm_md_top` to auto-start the fixed region.
- Dumps 5000 stereo samples on `audio_sample_valid` rising edges.
- Writes the dump to:

```text
/tmp/mister_vgm_md_top_5k.txt
```

Build/run:

```sh
iverilog -g2012 -Wall -DSIMULATION -s tb_mister_vgm_md_top \
  -o /tmp/tb_mister_vgm_md_top.vvp \
  tb/tb_mister_vgm_md_top.sv \
  rtl/mister_vgm_md_top.sv \
  rtl/vgm_region_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v

vvp /tmp/tb_mister_vgm_md_top.vvp \
  > /tmp/tb_mister_vgm_md_top.log
```

WAV conversion:

```sh
python3 tools/audio_txt_to_wav/audio_txt_to_wav.py \
  /tmp/mister_vgm_md_top_5k.txt \
  /tmp/mister_vgm_md_top_5k.wav \
  --gain 2
```

Successful result:

```text
wav_written_samples=5000
audio_sample_valid_edges=5000
pc=126
last_cmd=66
busy=0
done=0
samples=5000
min=-2513
max=6022
nonzero=9916
rms=1856.18
clip_count=0
```

## Next MiSTer Core Skeleton Step

To build an `.rbf`, a real MiSTer/Quartus skeleton still needs to be added.
The minimum next pieces are:

```text
MiSTer top-level, usually emu.sv or a core-specific top
Quartus .qpf
Quartus .qsf
pin assignments / platform constraints from a known MiSTer template
clock/reset wiring
audio output wiring
file list including rtl/mister_vgm_md_top.sv and all Genesis audio dependencies
```

At the MiSTer skeleton boundary, connect roughly:

```text
MiSTer/core clock      -> mister_vgm_md_top.clk
MiSTer reset signal    -> mister_vgm_md_top.reset_n
mister_vgm_md_top.audio_l -> MiSTer AUDIO_L path
mister_vgm_md_top.audio_r -> MiSTer AUDIO_R path
```

The exact MiSTer audio port names depend on the skeleton being used. Common
MiSTer cores expose 16-bit signed or wider mixed audio paths, so verify the
target skeleton's expected width and sign convention before wiring directly.

Recommended next workflow:

1. Start from a small known-working MiSTer core template.
2. Add `rtl/mister_vgm_md_top.sv`.
3. Add `rtl/vgm_region_player.sv`.
4. Add `rtl/md_sound_module.sv`.
5. Add all files under `rtl/genesis_audio/`.
6. Wire clock/reset/audio in the skeleton top.
7. Build in Quartus.
8. If the build succeeds, load the `.rbf` and listen for the fixed region.

## MiSTer Core Skeleton Proposal

Current local project state:

```text
no .qpf
no .qsf
no .sdc
no sys/ framework directory
no emu.sv wrapper
```

According to the MiSTer developer documentation, a normal MiSTer core is not
built by making the user core module the direct Quartus top. Quartus uses the
MiSTer `sys/sys_top` wrapper, and that wrapper calls a core-provided module
named `emu`. The MiSTer documentation also shows that `emu` exposes MiSTer
framework ports such as `CLK_50M`, `RESET`, `HPS_BUS`, video signals, and
`AUDIO_L` / `AUDIO_R`.

References:

```text
https://mister-devel.github.io/MkDocs_MiSTer/developer/emu/
https://mister-devel.github.io/MkDocs_MiSTer/developer/porting/
https://mister-devel.github.io/MkDocs_MiSTer/developer/hps_io/
```

Therefore the recommended structure is:

```text
mister-vgm-work/
  VGM_MD_MiSTer.qpf
  VGM_MD_MiSTer.qsf
  VGM_MD_MiSTer.sdc
  sys/                         copied from a known MiSTer template/core
  rtl/
    emu.sv                     new MiSTer-facing core wrapper
    mister_vgm_md_top.sv       existing fixed-region sound top
    vgm_region_player.sv
    md_sound_module.sv
    genesis_audio/
      ...
```

For the first hardware test, `emu.sv` should be a very small wrapper:

```text
MiSTer sys_top
  -> emu
     -> PLL / clock generation
     -> reset/status handling
     -> minimal video placeholder
     -> mister_vgm_md_top
        -> md_sound_fixed_region_test
        -> audio_l/audio_r
```

`mister_vgm_md_top` should remain the sound experiment sub-top. It should not
replace `emu` or `sys_top`.

## Minimal emu.sv Connection Plan

For the first no-OSD/no-file test, `emu.sv` only needs enough wiring for MiSTer
to build and expose audio.

Important MiSTer-side signals:

```text
CLK_50M       master input clock from the MiSTer framework
RESET         framework reset
HPS_BUS       pass to hps_io if the skeleton requires it
AUDIO_L       16-bit audio output
AUDIO_R       16-bit audio output
AUDIO_S       signed/unsigned selector
AUDIO_MIX     MiSTer mono mix selector
CLK_VIDEO     video clock, even for a blank test screen
CE_PIXEL      video pixel clock enable
VGA_R/G/B     video color outputs
VGA_HS/VGA_VS sync outputs
VGA_DE        active video
VIDEO_ARX/Y   aspect ratio
LED_USER      optional debug
```

For this fixed-region audio-only bring-up:

```text
mister_vgm_md_top.clk      <- clk_sys from PLL
mister_vgm_md_top.reset_n  <- ~(RESET | soft_reset)
AUDIO_L                    <- mister_vgm_md_top.audio_l
AUDIO_R                    <- mister_vgm_md_top.audio_r
AUDIO_S                    <- 1'b1, signed audio
AUDIO_MIX                  <- 2'b00, no forced mono mix
```

Video can be a placeholder at first, but MiSTer still expects valid video-style
signals. Use a known template's simple video path, or output a blank active
frame with stable timing if the selected skeleton supports that.

## Proposed Quartus Files

Use a known MiSTer template/core as the base. Do not hand-write a DE10-Nano
pinout from scratch unless absolutely necessary.

`VGM_MD_MiSTer.qpf`:

```text
PROJECT_REVISION = "VGM_MD_MiSTer"
```

`VGM_MD_MiSTer.qsf` should:

```text
set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE <DE10-Nano device from template>
set_global_assignment -name TOP_LEVEL_ENTITY sys_top
include or list sys/ framework files from the template
list rtl/emu.sv
list rtl/mister_vgm_md_top.sv
list rtl/vgm_region_player.sv
list rtl/md_sound_module.sv
list all rtl/genesis_audio/**/*.v dependencies
```

`VGM_MD_MiSTer.sdc` should start from the template/sys timing constraints.
The important point from the MiSTer docs is that the PLL naming and instance
used by the framework should match what `sys_top.sdc` expects.

## Minimal emu.sv Sketch

This is a connection sketch, not yet a committed source file:

```systemverilog
module emu (
    input         CLK_50M,
    input         RESET,
    inout  [48:0] HPS_BUS,

    output        CLK_VIDEO,
    output        CE_PIXEL,
    output [12:0] VIDEO_ARX,
    output [12:0] VIDEO_ARY,
    output  [7:0] VGA_R,
    output  [7:0] VGA_G,
    output  [7:0] VGA_B,
    output        VGA_HS,
    output        VGA_VS,
    output        VGA_DE,

    input         CLK_AUDIO,
    output [15:0] AUDIO_L,
    output [15:0] AUDIO_R,
    output        AUDIO_S,
    output  [1:0] AUDIO_MIX
    // plus the remaining ports required by the selected template
);

    wire clk_sys;
    wire pll_locked;

    pll pll (
        .refclk   (CLK_50M),
        .rst      (1'b0),
        .outclk_0 (clk_sys),
        .locked   (pll_locked)
    );

    wire signed [15:0] md_audio_l;
    wire signed [15:0] md_audio_r;

    mister_vgm_md_top md_test (
        .clk       (clk_sys),
        .reset_n   (pll_locked && !RESET),
        .audio_l   (md_audio_l),
        .audio_r   (md_audio_r)
        // debug outputs can be left open or routed to LEDs
    );

    assign AUDIO_L   = md_audio_l;
    assign AUDIO_R   = md_audio_r;
    assign AUDIO_S   = 1'b1;
    assign AUDIO_MIX = 2'b00;

    // TODO: supply valid blank/video timing from the chosen template.
endmodule
```

The real `emu.sv` must match the exact port list expected by the copied MiSTer
template's `sys_top`.

## Practical Next Step

Recommended next action:

1. Copy a current minimal MiSTer template repository into this project, or start
   a sibling project from the template and copy this `rtl/` tree into it.
2. Keep the template's `sys/`, `.qsf`, `.qpf`, and `.sdc`.
3. Rename the project/revision.
4. Add `rtl/mister_vgm_md_top.sv` and all MD sound files to the `.qsf`.
5. Create `rtl/emu.sv` using the template's exact port list.
6. Wire only clock/reset/audio first.
7. Build once in Quartus.
8. If Quartus succeeds, then iterate on audio/video polish.

## Not Yet Implemented

- SD card / HPS VGM loading.
- VGZ decompression.
- Large PCM data banks in BRAM.
- Full VGM loop/end handling in hardware.
- DAC Stream Control `0x90`-`0x95`.
- A real hardware VGM parser for arbitrary songs.
- Clock-domain crossing or FIFO buffering for external command sources.

## Added Minimal emu Wrapper

The first MiSTer-facing core wrapper has been added:

```text
rtl/emu.sv
```

This file is still a bring-up wrapper, not a complete polished MiSTer core.
It instantiates:

```text
emu
  -> mister_vgm_md_top
     -> md_sound_fixed_region_test
        -> vgm_region_player
        -> md_sound_module
```

Current behavior:

- Uses `CLK_50M` directly as `clk_sys`.
- Synchronizes the MiSTer `RESET` input and passes active-low reset to
  `mister_vgm_md_top`.
- Routes `mister_vgm_md_top.audio_l` / `audio_r` to `AUDIO_L` / `AUDIO_R`.
- Sets `AUDIO_S=1` for signed samples.
- Sets `AUDIO_MIX=2'b00` so stereo is not forced to mono.
- Generates a simple blank 640x480-style video signal using a 25 MHz pixel
  enable derived from `CLK_50M`.
- Leaves HPS, SD, OSD, SDRAM, DDRAM, UART, and user ports idle.

Debug/status mapping:

```text
LED_USER       <- player_busy || player_done
LED_DISK[0]    <- audio_sample_valid
player_pc_debug / player_last_cmd_debug are internal for now
```

The debug signals are intentionally not exposed through HPS or OSD yet. They
can be routed to spare LEDs or SignalTap later if hardware bring-up needs more
visibility.

Important TODO before a production `.rbf`:

- Replace the direct `CLK_50M` clock use with the PLL/clocking style from the
  selected MiSTer template.
- Make sure `rtl/emu.sv` port names exactly match the copied template's
  `sys_top` instantiation.
- Decide whether the blank video generator is sufficient or whether to copy the
  template's video helper path.
- Add `hps_io` only when OSD or file loading becomes necessary.

## emu.sv Syntax Check

The new wrapper was checked with Icarus Verilog:

```sh
iverilog -g2012 -Wall -DSIMULATION -s emu \
  -o /tmp/emu_check.vvp \
  rtl/emu.sv \
  rtl/mister_vgm_md_top.sv \
  rtl/vgm_region_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v
```

Result:

```text
compile passed
```

Remaining warnings are the already-known JT12/Icarus warnings:

- implicit `op_result_hd` warning in `jt12_top.v`
- LUT sensitivity warnings in `jt12_pm.v`
- `jt12_comb.v` simulation out-of-bounds warning
- `unique case` ignored by Icarus warnings

No new compile error was introduced by `rtl/emu.sv`.

## Quartus Project Skeleton Plan

This repository still does not contain a real MiSTer `sys_top` framework or a
Quartus project. The next practical step is to copy a known-working MiSTer
template/core skeleton and then add this project's RTL.

Minimum project-level files:

```text
VGM_MD_MiSTer.qpf
VGM_MD_MiSTer.qsf
VGM_MD_MiSTer.sdc
sys/                  copied from a known MiSTer template/core
rtl/emu.sv            added in this project
rtl/mister_vgm_md_top.sv
rtl/vgm_region_player.sv
rtl/md_sound_module.sv
rtl/genesis_audio/...
```

Recommended `VGM_MD_MiSTer.qpf` skeleton:

```text
PROJECT_REVISION = "VGM_MD_MiSTer"
```

Recommended `VGM_MD_MiSTer.qsf` skeleton:

```text
set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE <copy DE10-Nano device from template>
set_global_assignment -name TOP_LEVEL_ENTITY sys_top
set_global_assignment -name SDC_FILE VGM_MD_MiSTer.sdc

# Include the template's sys_top/sys framework files here.
# Keep these copied from a known working MiSTer template rather than
# hand-writing DE10-Nano pin assignments.
```

Then add this project's RTL file list below.

## QSF RTL File List

Register these files in the `.qsf`. The order below keeps wrappers first and
then lists all JT12/JT89/filter dependencies explicitly so they are not missed.

```text
set_global_assignment -name SYSTEMVERILOG_FILE rtl/emu.sv
set_global_assignment -name SYSTEMVERILOG_FILE rtl/mister_vgm_md_top.sv
set_global_assignment -name SYSTEMVERILOG_FILE rtl/vgm_region_player.sv
set_global_assignment -name SYSTEMVERILOG_FILE rtl/md_sound_module.sv

set_global_assignment -name VERILOG_FILE rtl/genesis_audio/filters/audio_iir_filter.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/filters/genesis_lpf.v

set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/adpcm/jt10_adpcm_div.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_acc.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_csr.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_div.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_dout.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_eg.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_eg_cnt.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_eg_comb.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_eg_ctrl.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_eg_final.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_eg_pure.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_eg_step.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_exprom.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_kon.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_lfo.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_logsin.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_mmr.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_mod.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_op.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_pcm_interpol.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_pg.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_pg_comb.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_pg_dt.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_pg_inc.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_pg_sum.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_pm.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_reg.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_rst.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_sh.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_sh24.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_sh_rst.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_single_acc.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_sumch.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_timers.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/jt12_top.v

set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/mixer/jt12_comb.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/mixer/jt12_decim.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/mixer/jt12_fm_uprate.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/mixer/jt12_genmix.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt12/mixer/jt12_interpol.v

set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt89/jt89.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt89/jt89_mixer.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt89/jt89_noise.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt89/jt89_tone.v
set_global_assignment -name VERILOG_FILE rtl/genesis_audio/jt89/jt89_vol.v
```

## SDC Plan

Start from the template's `.sdc` / `sys_top.sdc`.

For this minimal bring-up, the important clocking assumptions are:

```text
CLK_50M enters sys_top from the DE10-Nano board.
sys_top/template normally creates the clocks expected by emu.
emu currently uses CLK_50M directly as clk_sys.
```

When a PLL is added, the PLL instance name and generated clock names should be
kept compatible with the copied MiSTer template's constraints. Do not invent
new DE10-Nano pin or timing constraints until the template has been copied and
the expected names are known.

## Minimal Quartus Skeleton Added

The project now includes a minimal standalone Quartus skeleton:

```text
VGM_MD_MiSTer.qpf
VGM_MD_MiSTer.qsf
VGM_MD_MiSTer.sdc
sys/sys_top.sv
rtl/emu.sv
```

This is meant as the first Quartus compile target. It is deliberately smaller
than a complete MiSTer framework checkout.

Current hierarchy:

```text
sys_top
  -> emu
     -> mister_vgm_md_top
        -> md_sound_fixed_region_test
           -> vgm_region_player
           -> md_sound_module
              -> JT12 / JT89 / mixer / filters
```

Current `sys/sys_top.sv` behavior:

- Accepts `CLK_50M` and active-low `RESET_N`.
- Instantiates `emu`.
- Exposes `AUDIO_L`, `AUDIO_R`, `AUDIO_S`, and `AUDIO_MIX`.
- Exposes the simple blank video outputs generated by `emu`.
- Exposes `LED_USER` as a minimal player status indicator.
- Stubs unused HPS/SDRAM/DDR/SD/UART-style inputs inside the wrapper.

Important limitation:

```text
sys/sys_top.sv is not the full MiSTer framework sys_top.
```

It is good enough to give Quartus a concrete top-level and to catch missing RTL
dependencies. Before treating the generated `.rbf` as a normal MiSTer core,
replace or merge it with a known-working MiSTer template `sys/` directory and
its real board pin assignments / framework glue.

## Minimal Skeleton Syntax Check

The skeleton was checked with Icarus Verilog:

```sh
iverilog -g2012 -Wall -DSIMULATION -s sys_top \
  -o /tmp/sys_top_check.vvp \
  sys/sys_top.sv \
  rtl/emu.sv \
  rtl/mister_vgm_md_top.sv \
  rtl/vgm_region_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v
```

Result:

```text
compile passed
```

Remaining warnings are the existing JT12/Icarus warnings already tracked in
earlier simulation checks.

## Quartus Build Command

If Quartus is installed and available in `PATH`, try:

```sh
quartus_sh --flow compile VGM_MD_MiSTer
```

Equivalent step-by-step commands:

```sh
quartus_map VGM_MD_MiSTer
quartus_fit VGM_MD_MiSTer
quartus_asm VGM_MD_MiSTer
quartus_sta VGM_MD_MiSTer
```

Expected output location:

```text
output_files/VGM_MD_MiSTer.sof
output_files/VGM_MD_MiSTer.rbf
```

This local session could not run Quartus because `quartus_sh` / `quartus_map`
were not found in `PATH`.

## Quartus Log Checkpoints

If compilation fails, check these logs first:

```text
output_files/VGM_MD_MiSTer.map.rpt
output_files/VGM_MD_MiSTer.fit.rpt
output_files/VGM_MD_MiSTer.asm.rpt
output_files/VGM_MD_MiSTer.sta.rpt
```

Useful searches:

```sh
grep -R "Error" output_files
grep -R "Can't elaborate" output_files
grep -R "Can't find" output_files
grep -R "Critical Warning" output_files
grep -R "Timing requirements not met" output_files
```

Common failure categories:

- Missing RTL file in `VGM_MD_MiSTer.qsf`
- SystemVerilog parsing issue in Quartus that Icarus tolerated
- Top-level port mismatch between `sys_top` and the selected MiSTer template
- Missing or incompatible pin assignments after importing a real template
- PLL/clock name mismatch between the template `.sdc` and copied `sys_top`
- Timing failure inside JT12/JT89 after fitter placement

For dependency problems, compare `VGM_MD_MiSTer.qsf` against the explicit RTL
file list in this document. The JT12/JT89 files are intentionally listed one by
one so a missing dependency is easy to spot.

## Migration To Real MiSTer Framework

When moving from this minimal compile skeleton to an actual MiSTer core:

1. Copy a known-working MiSTer template/core `sys/` directory.
2. Keep the template's board pin assignments and timing constraints.
3. Keep `rtl/emu.sv` as the core-facing wrapper, but adjust its port list if
   the selected template expects a different `emu` signature.
4. Merge the `VGM_MD_MiSTer.qsf` RTL file list into the template `.qsf`.
5. Re-run Quartus.
6. Only after the fixed-region audio works on hardware, add HPS/OSD/SD loading.

## Hardware Symptom: Minimal sys_top Failed On MiSTer

The first `.rbf` built from the hand-written minimal `sys/sys_top.sv` did not
behave like a valid MiSTer core on hardware.

Observed symptom:

```text
VGM_MD_MiSTer.rbf starts
monitor loses video signal / goes to no-signal state
screen remains black
core name does not appear
MiSTer menu cannot be opened or returned to
```

Conclusion:

```text
This is a sys_top / MiSTer framework / video problem before it is an audio problem.
```

The old hand-written `sys/sys_top.sv` was only useful as a temporary Quartus
entry point. It did not provide the real MiSTer framework behavior needed for:

- HDMI/video output handling
- HPS bus communication
- OSD/menu handling
- core configuration string visibility
- normal MiSTer menu return

Therefore it must not be used as the real hardware top.

## Template_MiSTer Framework Import

The project has been switched to the official Template_MiSTer style structure.

Reference source:

```text
https://github.com/MiSTer-devel/Template_MiSTer
```

Imported framework:

```text
sys/
  sys_top.v
  sys.qip
  sys.tcl
  sys_analog.tcl
  emu_ports.vh
  hps_io.sv
  osd.v
  video_mixer.sv
  audio_out.sv
  ...other Template_MiSTer sys files
```

The old hand-written `sys/sys_top.sv` has been removed from the active project.
The real Quartus top is now:

```text
sys/sys_top.v
```

The core wrapper is:

```text
rtl/emu.sv
```

and it now uses:

```systemverilog
module emu (
    `include "sys/emu_ports.vh"
);
```

This matches the Template_MiSTer pattern where `sys_top` instantiates a
core-provided `emu` module.

## Current Hardware Debug Video

The updated `rtl/emu.sv` prioritizes video/framework sanity before audio.

It instantiates `hps_io` only for basic MiSTer menu/config/reset support:

```text
hps_io
  -> CONF_STR / core name
  -> status reset bit
  -> buttons
  -> forced_scandoubler
```

No SD card loading, OSD file selection, or VGM file browsing is implemented.

Debug colors:

```text
reset               black
running             blue
audio_seen_latched  red
player_done_latched green
```

Priority:

```text
reset > player_done_latched > audio_seen_latched > running
```

Expected first hardware result:

- monitor keeps video sync
- a fixed color screen appears
- MiSTer menu can open/return
- core name `VGM_MD` appears
- after the fixed region finishes, the screen should become green

Audio is still connected, but it is not the primary pass/fail condition for
this step.

## Active Quartus Project Files

The active project files now follow Template_MiSTer style:

```text
VGM_MD_MiSTer.qpf
VGM_MD_MiSTer.qsf
VGM_MD_MiSTer.sdc
files.qip
sys/sys_top.v
rtl/emu.sv
```

`VGM_MD_MiSTer.qsf` now uses:

```text
source sys/sys.tcl
source sys/sys_analog.tcl
source files.qip
```

`files.qip` contains only this project's local RTL:

```text
rtl/emu.sv
rtl/mister_vgm_md_top.sv
rtl/vgm_region_player.sv
rtl/md_sound_module.sv
rtl/genesis_audio/filters/*
rtl/genesis_audio/jt12/*
rtl/genesis_audio/jt12/mixer/*
rtl/genesis_audio/jt12/adpcm/*
rtl/genesis_audio/jt89/*
```

The Template_MiSTer framework files are registered through `sys/sys.qip`, which
is sourced by `sys/sys.tcl`.

## Rebuild Command After Template Import

Run from the project root:

```sh
quartus_sh --flow compile VGM_MD_MiSTer
```

If building step-by-step:

```sh
quartus_map VGM_MD_MiSTer
quartus_fit VGM_MD_MiSTer
quartus_asm VGM_MD_MiSTer
quartus_sta VGM_MD_MiSTer
```

Expected `.rbf`:

```text
output_files/VGM_MD_MiSTer.rbf
```

This local environment still does not have `quartus_sh` in `PATH`, so the
Quartus build was not run here.

## Log Checks For Video/Menu Bring-up

After Quartus build failure, check:

```text
output_files/VGM_MD_MiSTer.map.rpt
output_files/VGM_MD_MiSTer.fit.rpt
output_files/VGM_MD_MiSTer.asm.rpt
output_files/VGM_MD_MiSTer.sta.rpt
```

Useful searches:

```sh
grep -R "Error" output_files
grep -R "Critical Warning" output_files
grep -R "Can't find" output_files
grep -R "Can't elaborate" output_files
grep -R "Timing requirements not met" output_files
```

For this specific bring-up, focus first on:

- `sys/sys_top.v` is the `TOP_LEVEL_ENTITY`
- `sys/sys.tcl` and `sys/sys.qip` are sourced
- `rtl/emu.sv` compiles with `sys/emu_ports.vh`
- `hps_io.sv` is included through `sys/sys.qip`
- `files.qip` includes all local MD sound RTL
- no old `sys/sys_top.sv` is being used as hardware top

## Simulation Notes After Template Import

The existing sound simulations still build because they instantiate
`mister_vgm_md_top` or `md_sound_fixed_region_test` directly and do not depend
on MiSTer `sys_top`.

Checked:

```sh
iverilog -g2012 -Wall -DSIMULATION -s tb_mister_vgm_md_top ...
iverilog -g2012 -Wall -DSIMULATION -s tb_md_sound_fixed_region_test ...
```

Both still compile with the same existing JT12/timescale/Icarus warnings.

Do not use Icarus as the final checker for Template_MiSTer `hps_io.sv`.
`hps_io.sv` uses SystemVerilog constructs that Icarus does not elaborate cleanly
in this local check, while the framework is intended for Quartus.

## Quartus Warning: Missing rtl/pll.qip

After switching to the Template_MiSTer framework, Quartus reported:

```text
Warning (125092): Tcl Script File rtl/pll.qip not found
Info (125063): set_global_assignment -name QIP_FILE rtl/pll.qip -qip sys/pll_q17.qip
```

Cause:

```text
sys/sys.tcl selects sys/pll_q17.qip for Quartus 17.
sys/pll_q17.qip references rtl/pll.qip.
rtl/pll.qip had not been copied from Template_MiSTer.
```

The missing file was not in `VGM_MD_MiSTer.qsf` directly. It was pulled in
through the Template_MiSTer framework path:

```text
VGM_MD_MiSTer.qsf
  -> source sys/sys.tcl
     -> set_global_assignment -name QIP_FILE sys/sys.qip
     -> set_global_assignment -name QIP_FILE sys/pll_q17.qip
        -> set_global_assignment -name QIP_FILE rtl/pll.qip
```

Fix:

```text
Copied Template_MiSTer rtl PLL files into this project:

rtl/pll.qip
rtl/pll.v
rtl/pll/pll_0002.qip
rtl/pll/pll_0002.v
rtl/pll/pll_0002_q13.qip
```

Current `.qip` files present:

```text
files.qip
rtl/pll.qip
rtl/pll/pll_0002.qip
rtl/pll/pll_0002_q13.qip
sys/pll.13.qip
sys/pll_audio.13.qip
sys/pll_audio.qip
sys/pll_audio/pll_audio_0002.qip
sys/pll_cfg.qip
sys/pll_hdmi.13.qip
sys/pll_hdmi.qip
sys/pll_hdmi/pll_hdmi_0002.qip
sys/pll_q13.qip
sys/pll_q17.qip
sys/sys.qip
```

Clock path status after this fix:

```text
sys/sys_top.v remains the Quartus TOP_LEVEL_ENTITY.
sys/sys_top.v instantiates emu.
rtl/emu.sv currently uses CLK_50M directly as clk_sys.
rtl/emu.sv drives CLK_VIDEO = clk_sys and CE_PIXEL as a divided pixel enable.
```

Important note:

```text
The missing rtl/pll.qip warning must be fixed first because it means the
Template_MiSTer framework PLL dependency set was incomplete.
```

If video still fails after this fix, the next things to check are:

- Whether Quartus reports any remaining missing `.qip`, `.v`, or `.sv` files.
- Whether `sys/sys_top.v` is definitely the compiled top.
- Whether `rtl/emu.sv` should instantiate the Template core PLL, like
  `Template.sv`, instead of using `CLK_50M` directly.
- Whether debug video timing from `rtl/emu.sv` is accepted by the MiSTer video
  mixer path.

For the current step, no sound RTL was changed.

## Quartus Error 15836: Raw CLK_50M Drove Video Clock Select

Quartus Full Compilation later failed with:

```text
Error (15836): inclk[3] port of Clock Select Block "hdmi_clk_sw" is driven by FPGA_CLK2_50~input, but must be driven by a PLL's output clock; clock pins should be moved to inclk[0] or inclk[1]
Error (15836): inclk[3] port of Clock Select Block "vga_clk_sw" is driven by FPGA_CLK2_50~input, but must be driven by a PLL's output clock; clock pins should be moved to inclk[0] or inclk[1]
```

Cause:

```text
sys/sys_top.v uses cyclonev_clkselect for HDMI/VGA clocks:

  .inclk({clk_vid, hdmi_clk_out, 2'b00})

That means clk_vid is connected to inclk[3].
Quartus requires inclk[3] of this clock select block to be a PLL output.
```

The previous `rtl/emu.sv` had:

```systemverilog
wire clk_sys = CLK_50M;
assign CLK_VIDEO = clk_sys;
```

So the path became:

```text
FPGA_CLK2_50 raw input
  -> emu.CLK_50M
  -> emu.CLK_VIDEO
  -> sys_top clk_vid
  -> hdmi_clk_sw/vga_clk_sw inclk[3]
```

That violates the Cyclone V clock select rule and explains Error 15836.

Fix:

`rtl/emu.sv` now follows the Template_MiSTer pattern and instantiates the core
PLL:

```systemverilog
wire clk_sys;
wire pll_locked;

pll pll (
    .refclk   (CLK_50M),
    .rst      (1'b0),
    .outclk_0 (clk_sys),
    .locked   (pll_locked)
);

wire reset = RESET | status[0] | buttons[1] | !pll_locked;
assign CLK_VIDEO = clk_sys;
```

Now the video clock path is:

```text
FPGA_CLK2_50 raw input
  -> emu pll
  -> pll outclk_0
  -> emu.CLK_VIDEO
  -> sys_top clk_vid
  -> hdmi_clk_sw/vga_clk_sw inclk[3]
```

This should satisfy Quartus because `inclk[3]` is now driven by a PLL output.

No sound RTL was changed:

```text
rtl/md_sound_module.sv unchanged
rtl/vgm_region_player.sv unchanged
rtl/mister_vgm_md_top.sv unchanged
rtl/genesis_audio/ unchanged
```

Rebuild:

```sh
quartus_sh --flow compile VGM_MD_MiSTer
```

First pass/fail target:

```text
Error (15836) should disappear.
Monitor should keep a valid video signal.
Debug fixed color should appear.
MiSTer menu/core name should be reachable.
```

## Strategy Change: Video-only Template Baseline First

After the custom/minimal bring-up attempts, Quartus Full Compilation could pass
but the MiSTer hardware still behaved like this:

```text
core loads
monitor loses signal
screen remains black
core name is not visible
MiSTer menu cannot be opened/returned to
```

New conclusion:

```text
Do not continue debugging this as an audio problem.
Do not keep adding fixes to a custom sys_top.
First prove the Template_MiSTer outer shell on hardware.
```

New staged plan:

1. Use the Template_MiSTer `sys/` framework as-is as much as possible.
2. Build a video-only `emu.sv` baseline.
3. Confirm on hardware:
   - monitor keeps sync
   - fixed color appears
   - core name appears
   - MiSTer menu can return
4. Only after that, connect `mister_vgm_md_top` inside `emu.sv`.
5. Then restore the sound RTL file list into `files.qip`.

Active video-only baseline:

```text
sys/sys_top.v       Template_MiSTer hardware top
rtl/emu.sv          video-only core wrapper
files.qip           only registers rtl/emu.sv plus local SDC
```

`rtl/emu.sv` currently:

- uses `module emu ( \`include "sys/emu_ports.vh" );`
- instantiates `hps_io`
- instantiates Template core `pll`
- drives `CLK_VIDEO` from PLL output `clk_sys`
- generates a simple fixed-color 640x480-style raster
- drives audio as zero:

```systemverilog
assign AUDIO_L = 16'sd0;
assign AUDIO_R = 16'sd0;
```

`files.qip` is intentionally reduced to:

```text
set_global_assignment -name SDC_FILE VGM_MD_MiSTer.sdc
set_global_assignment -name SYSTEMVERILOG_FILE rtl/emu.sv
```

The sound RTL is not deleted. It is only excluded from the active MiSTer
hardware baseline until video/menu is proven.

Sound files intentionally unchanged:

```text
rtl/mister_vgm_md_top.sv
rtl/vgm_region_player.sv
rtl/md_sound_module.sv
rtl/genesis_audio/
```

Existing simulation checks still compile because they instantiate the sound
subtops directly and do not depend on `files.qip`:

```sh
iverilog -g2012 -Wall -DSIMULATION -s tb_mister_vgm_md_top ...
iverilog -g2012 -Wall -DSIMULATION -s tb_md_sound_fixed_region_test ...
```

Hardware pass/fail for this phase:

```text
PASS:
  fixed color visible
  monitor does not lose signal
  MiSTer menu opens/returns
  core name VGM_MD appears

FAIL:
  black/no-signal
  menu cannot return
  core name missing
```

Only after PASS should `mister_vgm_md_top` be reconnected to `emu.sv`.

## Video-only Baseline Passed On Hardware

The InputTest-style video-only baseline was tested on MiSTer hardware and
passed.

Confirmed:

```text
green background displayed
monitor did not lose signal
MiSTer menu could be opened/returned to
```

This proves the current InputTest-derived outer shell is fundamentally valid:

```text
sys/sys_top.v
rtl/emu.sv
hps_io
PLL/video clock path
MiSTer menu path
```

At this point, the project can safely move one step forward: instantiate
`mister_vgm_md_top` inside `emu.sv`, but keep external audio muted.

## Player-status Baseline

Current hardware baseline:

```text
InputTest-style outer shell
  -> rtl/emu.sv
     -> mister_vgm_md_top
```

Still muted externally:

```systemverilog
assign AUDIO_L = 16'd0;
assign AUDIO_R = 16'd0;
```

The goal is only to prove that `mister_vgm_md_top` runs on hardware and exposes
player status without breaking video/menu.

Signals observed from `mister_vgm_md_top`:

```text
player_busy
player_done
audio_sample_valid
player_pc_debug
player_last_cmd_debug
```

Latched signals:

```text
done_latched       <= player_done
audio_seen_latched <= audio_sample_valid
```

Debug colors:

```text
idle/running background : green
player_busy             : red
done_latched            : blue
audio_seen_latched      : white
```

Priority:

```text
audio_seen_latched > done_latched > player_busy > idle
```

Expected hardware behavior:

```text
green  : outer shell and video are alive, player idle/not visibly active
red    : fixed region player is busy
blue   : fixed region reached done
white  : md_sound_module produced audio_sample_valid at least once
```

Audio should still be silent in this phase. If video/menu fails now, the issue
is likely the reintroduced sound/player logic causing a hardware-side problem,
not the MiSTer outer shell.

## InputTest_MiSTer Reference Analysis

Reference core:

```text
/Users/daizo/Projects/InputTest_MiSTer
```

This core is a known-good MiSTer Utility core on the target hardware. Its `.rbf`
boots, keeps video sync, shows a core/menu, and can return to the MiSTer menu.

Important structural difference from the current VGM baseline:

```text
InputTest_MiSTer uses its own known-working sys/ framework copy and an explicit
emu port list in InputTest.sv.
```

InputTest active project structure:

```text
InputTest.qsf
  -> source sys/sys.tcl
  -> source sys/sys_analog.tcl
  -> source files.qip

files.qip
  -> InputTest.sv
  -> sys/sys.qip
  -> core RTL dependencies
```

By contrast, the VGM baseline was using a newer Template_MiSTer `sys/` copy and
an `emu.sv` using:

```systemverilog
module emu (
    `include "sys/emu_ports.vh"
);
```

That version can compile, but still fails on hardware with no video signal.
Since InputTest is proven on the same hardware, the next step is to align the
VGM baseline with InputTest's outer shell instead of continuing to debug the
newer/custom shell.

### sys_top / emu Port Shape

InputTest `emu` uses an explicit port list:

```text
CLK_50M
RESET
HPS_BUS[48:0]
CLK_VIDEO
CE_PIXEL
VIDEO_ARX/VIDEO_ARY
VGA_R/G/B
VGA_HS/VGA_VS/VGA_DE
VGA_F1/VGA_SL/VGA_SCALER/VGA_DISABLE
HDMI_WIDTH/HDMI_HEIGHT
HDMI_FREEZE/HDMI_BLACKOUT
AUDIO_L/AUDIO_R/AUDIO_S/AUDIO_MIX
ADC/SD/DDR/SDRAM/UART/USER/OSD_STATUS
```

The newer Template_MiSTer `emu_ports.vh` copy in the VGM project used a
different framework shape, including `HPS_BUS[45:0]` and some newer ports.
For this hardware test, matching the proven InputTest port shape is safer than
mixing framework generations.

### CONF_STR / Core Name / OSD

InputTest:

```text
localparam CONF_STR = {
    "InputTest;;",
    ...
    "R0,Reset;",
    ...
    "V,v",`BUILD_DATE
};
```

For the VGM baseline, the equivalent should be:

```text
"VGM_MD;;"
```

plus minimal reset/menu entries. The key point is that `hps_io` must be wired
like InputTest so the core name and menu path are visible.

### hps_io

InputTest connects many `hps_io` outputs even if the core does not use all of
them:

```text
buttons
status
status_menumask({direct_video})
forced_scandoubler
video_rotated
direct_video
ioctl_* signals
joystick_* signals
analog/paddle/spinner
ps2_key/ps2_mouse
TIMESTAMP
```

The VGM baseline should copy this style for video-only bring-up. It can leave
most signals unused internally, but the `hps_io` instance should look like the
known-good core rather than a minimal partial connection.

### Video

InputTest video path:

```text
pll -> clk_sys
jtframe_cen24 -> ce_pix
system core -> RGB + HBlank/VBlank/HSync/VSync
arcade_video -> final MiSTer-facing VGA_* signals
```

For VGM video-only baseline, the internal `system` can be replaced by a simple
fixed-color raster, but the external contract should stay close:

```text
CLK_VIDEO = clk_sys
CE_PIXEL = ce_pix
VGA_DE = active video
VGA_HS/VGA_VS = stable sync
VGA_R/G/B = fixed color
```

### Clock

InputTest:

```systemverilog
pll pll (
    .refclk(CLK_50M),
    .rst(0),
    .outclk_0(clk_sys)
);

jtframe_cen24 divider (
    .clk(clk_sys),
    .cen6(ce_pix),
    .cen2(...)
);

assign CLK_VIDEO = clk_sys;
```

The key part is that `CLK_VIDEO` comes from the core PLL output, not raw
`CLK_50M`.

### Audio

InputTest sets:

```text
AUDIO_S = 1
AUDIO_MIX = 0
```

and lets its internal `system` drive `AUDIO_L/R`.

For VGM video-only baseline:

```text
AUDIO_L = 0
AUDIO_R = 0
AUDIO_S = 1
AUDIO_MIX = 0
```

Audio remains intentionally disabled until video/menu pass.

### Reset

InputTest reset:

```systemverilog
wire reset = RESET | status[0] | rom_download;
```

For video-only VGM:

```systemverilog
wire reset = RESET | status[0] | !pll_locked;
```

No sound block reset is relevant in this phase.

### Action From Analysis

Change the VGM hardware baseline to:

1. Use the proven InputTest `sys/` framework copy.
2. Use an InputTest-style explicit `emu` port list instead of `sys/emu_ports.vh`.
3. Keep `files.qip` minimal for video-only:
   - `rtl/emu.sv`
   - `sys/sys.qip`
   - `rtl/pll.qip`
   - a tiny clock-enable helper if needed
4. Keep sound RTL in the repository but out of the active hardware build.
5. Reconnect `mister_vgm_md_top` only after the video-only baseline passes on
   real hardware.

## 2026-06-04: InputTest-Based Player Status Baseline

The InputTest-style MiSTer shell was tested on real hardware with
`mister_vgm_md_top` instantiated inside `emu.sv`, while keeping `AUDIO_L/R`
muted to zero.

Observed result:

- The screen changed to white.
- White means `audio_seen_latched` became active.
- Therefore `mister_vgm_md_top.audio_sample_valid` is being generated on the
  real MiSTer FPGA.
- The monitor kept a valid video signal.
- The MiSTer menu could still be opened and returned from.

This confirms that the InputTest-derived video/HPS shell is stable enough, and
that the fixed-region player and sound clock path are alive on hardware. The
remaining step is routing the generated audio samples to MiSTer audio output.

## 2026-06-04: First Real Audio Connection

`rtl/emu.sv` now connects the signed 16-bit output from `mister_vgm_md_top` to
MiSTer audio:

```systemverilog
wire signed [15:0] md_audio_l;
wire signed [15:0] md_audio_r;
wire signed [15:0] audio_l_safe = md_audio_l >>> 2;
wire signed [15:0] audio_r_safe = md_audio_r >>> 2;

assign AUDIO_S = 1'b1;
assign AUDIO_L = audio_l_safe;
assign AUDIO_R = audio_r_safe;
assign AUDIO_MIX = 2'b00;
```

The `>>> 2` shift is intentional for the first hardware audio test. It keeps
the output at a conservative level, roughly one quarter of the internal sample
amplitude, so the first `.rbf` is less likely to clip or produce an unexpectedly
loud signal.

The debug color screen remains active:

- green: idle/running baseline
- red: `player_busy`
- blue: `player_done` latched
- white: `audio_sample_valid` seen

The sound core itself was not changed. `md_sound_module`, JT12, JT89,
`vgm_region_player`, and `mister_vgm_md_top` remain the same. If audio is
audible but too quiet, the next safe experiment is changing the shift from
`>>> 2` to `>>> 1`. If audio is distorted or too loud, keep `>>> 2` or reduce
further.

## 2026-06-04: First MiSTer Audio Output Success

The first real-audio `.rbf` was tested on MiSTer hardware.

Observed result:

- The screen became white, so `audio_seen_latched` still works.
- A continuous tone was audible from MiSTer audio output.
- The MiSTer menu could still be opened and returned from.
- Therefore both `mister_vgm_md_top.audio_sample_valid` and the `AUDIO_L/R`
  connection are working on real hardware.

This is the first confirmed hardware audio output from the fixed-region Mega
Drive sound path.

## 2026-06-04: Fixed-Region Silence At End

The first audio build kept producing sound after the fixed region ended. For
bring-up, the safest first fix is to stop the sound sources inside the fixed
region itself rather than changing JT12, JT89, or `md_sound_module`.

`rtl/vgm_region_player.sv` now appends an explicit silence sequence before
`0x66 end`:

```text
52 28 00   YM key off for ch1
52 2A 00   YM DAC data = 0
52 2B 00   YM DAC disable
50 9F      PSG ch0 mute
50 BF      PSG ch1 mute
50 DF      PSG ch2 mute
50 FF      PSG noise mute
61 00 04   short settle wait
66         end
```

The debug color screen and conservative `AUDIO_L/R >>> 2` level are unchanged.
The sound core RTL remains unchanged:

- `rtl/md_sound_module.sv`
- JT12/JT89 files under `rtl/genesis_audio/`
- `rtl/mister_vgm_md_top.sv`

Alternative considered: gate `AUDIO_L/R` to zero after `player_done_latched`.
That is still a useful emergency mute for future bring-up, but the current
change keeps the player behavior closer to real VGM command playback by sending
explicit chip writes.

## 2026-06-05: Longer Hardware Bring-Up Tone

After adding the first silence sequence, the real MiSTer build still reached
the white debug screen and the menu remained usable, but audio was only a short
pop at reset. Before the silence sequence was added, the same path produced a
continuous tone. This strongly suggests that the fixed region was ending and
silencing the chips before the test tone was comfortably audible on real
hardware.

For bring-up, `rtl/vgm_region_player.sv` was changed from a very short sound
snippet to an intentionally long audible test:

```text
FM ch1 key-on
61 44 AC   wait 44100 samples, about 1 second
61 44 AC   wait 44100 samples, about 1 second
FM key-off / DAC zero / DAC off
short settle wait
PSG ch0 tone on
61 44 AC   wait 44100 samples, about 1 second
61 44 AC   wait 44100 samples, about 1 second
FM key-off / DAC zero / DAC off / PSG mute
short settle wait
66 end
```

This gives a clear hardware checklist:

1. Hear an FM tone for about two seconds.
2. Hear a PSG tone for about two seconds.
3. Confirm the output becomes silent after the final silence sequence.
4. Confirm the white debug screen and MiSTer menu behavior remain stable.

`AUDIO_L/R` scaling remains conservative at `>>> 2`. `emu.sv`,
`mister_vgm_md_top.sv`, `md_sound_module.sv`, JT12, and JT89 were not changed.

## 2026-06-05: Longer Bring-Up Tone Hardware Pass

The longer fixed-region hardware bring-up was tested on a real MiSTer.

Observed result:

- The white debug screen appears.
- The MiSTer menu can still be opened and returned from.
- Audio is audible from the real hardware output.
- The sequence plays as intended:
  - FM tone for about two seconds
  - PSG tone for about two seconds
  - silence
  - end
- The final silence sequence stops the sound.

This confirms that the current InputTest-based MiSTer shell, fixed-region
player, `mister_vgm_md_top`, `md_sound_module`, JT12, JT89, and `AUDIO_L/R`
connection are working together on hardware for the basic bring-up path.

Current hardware pass condition:

1. Video stays locked.
2. MiSTer menu remains usable.
3. `audio_seen_latched` reaches the white debug screen.
4. FM and PSG test tones are audible.
5. Audio becomes silent after the explicit stop sequence.

## 2026-06-05: Short VGM Snippet Region

After the fixed bring-up tone passed on real MiSTer hardware, the next step is
to move from a hand-written long test tone toward a short VGM-style command
region.

`rtl/vgm_region_player.sv` now has two selectable fixed regions:

```text
REGION_MODE = 0   BRINGUP_TONE, default and proven on hardware
REGION_MODE = 1   VGM_SNIPPET, short YM/PSG VGM-style command sequence
```

The default remains `REGION_MODE=0`, so the proven hardware bring-up tone is not
changed unless the build explicitly selects the snippet mode.

The VGM snippet currently includes:

- YM2612 port 0 writes using VGM opcode `0x52`
- SN76489 writes using VGM opcode `0x50`
- VGM waits using `0x61`
- no DAC stream or PCM block yet
- an explicit final silence sequence:
  - YM key off
  - DAC data zero
  - DAC disable
  - PSG mute for all channels
  - short wait
  - `0x66 end`

Simulation command for the default bring-up tone:

```sh
iverilog -g2012 -Wall -DSIMULATION -s tb_md_sound_fixed_region_test \
  -o /tmp/tb_md_sound_fixed_region_check.vvp \
  tb/tb_md_sound_fixed_region_test.sv \
  rtl/vgm_region_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v
vvp /tmp/tb_md_sound_fixed_region_check.vvp
```

Simulation command for the VGM snippet:

```sh
iverilog -g2012 -Wall -DSIMULATION -DTEST_FIXED_VGM_SNIPPET \
  -s tb_md_sound_fixed_region_test \
  -o /tmp/tb_md_sound_fixed_region_vgm_snippet_check.vvp \
  tb/tb_md_sound_fixed_region_test.sv \
  rtl/vgm_region_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v
vvp /tmp/tb_md_sound_fixed_region_vgm_snippet_check.vvp
```

Observed VGM snippet smoke result:

```text
FIXED_REGION_TEST_START samples=5000 region_mode=1
FIXED_REGION_TEST_DONE wav_written_samples=5000 audio_sample_valid_edges=5000 pc=90 last_cmd=61 busy=1 done=0
```

The snippet now contains one-second FM and PSG waits, so a 5000-sample smoke
test is expected to finish while the player is still inside the first `0x61`
wait. `wav_written_samples == audio_sample_valid_edges` is the pass condition
for this short simulation check.

For a hardware `.rbf`, `mister_vgm_md_top` still uses the default mode unless a
compile-time macro overrides it. To build the snippet without changing
`emu.sv`, `mister_vgm_md_top.sv`, or `md_sound_module.sv`, set the Verilog macro
`FIXED_REGION_MODE=1` in the Quartus build. For example, add this temporarily to
the project assignments:

```tcl
set_global_assignment -name VERILOG_MACRO "FIXED_REGION_MODE=1"
```

Remove that assignment, or set it back to `0`, to return to the proven
BRINGUP_TONE region.

## 2026-06-05: VGM Snippet Hardware Retry With Known Init

The first `REGION_MODE=1` VGM snippet was tested on real MiSTer hardware.

Observed result:

- White debug screen appeared.
- MiSTer menu return still worked.
- Audio was silent.

The previous `REGION_MODE=0` BRINGUP_TONE build produced audible FM and PSG and
then silenced correctly, so the MiSTer shell, `AUDIO_L/R`, and md sound path are
still considered good. The likely issue is that the first snippet behaved too
much like a mid-stream fragment: it depended on chip state that does not exist
when the fixed ROM starts from reset.

To remove that dependency, `REGION_MODE=1` now reuses the exact known-good YM
initialization/timbre/frequency/pan/key-on command sequence from the hardware
passing BRINGUP_TONE region. After that it runs:

```text
known-good YM init/timbre/frequency/pan/key-on
61 44 AC   wait 44100 samples, about 1 second
FM key-off / DAC zero / DAC off
short settle wait
explicit PSG ch0 tone setup and volume unmute
61 44 AC   wait 44100 samples, about 1 second
FM key-off / DAC zero / DAC off / PSG mute
short settle wait
66 end
```

This version is still selected with:

```tcl
set_global_assignment -name VERILOG_MACRO "FIXED_REGION_MODE=1"
```

Files intentionally unchanged for this retry:

- `rtl/emu.sv`
- `rtl/mister_vgm_md_top.sv`
- `rtl/md_sound_module.sv`
- JT12/JT89 files
- `AUDIO_L/R >>> 2` scaling

## 2026-06-05: VGM Snippet Still Silent, Audio Path Reconfirmed

The `FIXED_REGION_MODE=1` VGM snippet build was tested on real MiSTer hardware
again.

Observed result:

- White debug screen appeared.
- MiSTer menu return still worked.
- Audio was still silent.

The `FIXED_REGION_MODE=1` assignment was then removed/commented out, returning
the hardware build to the default BRINGUP_TONE region.

Observed result:

- White debug screen appeared.
- MiSTer menu return still worked.
- FM and PSG bring-up tones were audible.
- The final silence sequence stopped the sound.

Conclusion:

- The MiSTer shell is good.
- `AUDIO_L/R` is good.
- `md_sound_module`, JT12, and JT89 are good.
- The proven BRINGUP_TONE command path is good.
- The remaining issue is specific to VGM_SNIPPET selection/content.

Two corrective actions are now in place:

1. `REGION_MODE=1` reuses the known-good BRINGUP_TONE YM init/timbre/frequency/
   pan/key-on sequence at the start, then holds FM for about one second.
2. `md_sound_fixed_region_test` now also defaults its `REGION_MODE` parameter to
   `FIXED_REGION_MODE`, so a Quartus macro assignment can propagate through:

```systemverilog
module md_sound_fixed_region_test #(
    parameter int REGION_MODE = `FIXED_REGION_MODE
) (
```

This matters because `mister_vgm_md_top` instantiates `md_sound_fixed_region_test`
without an explicit parameter override. If the wrapper default stayed fixed at
`0`, then the macro could fail to select the snippet at the actual hardware top
path even though `vgm_region_player` itself supported the macro.

The intended hardware snippet build selection remains:

```tcl
set_global_assignment -name VERILOG_MACRO "FIXED_REGION_MODE=1"
```

## 2026-06-05: VGM Snippet First Hardware Sound

After fixing the region-mode propagation and reusing the known-good YM
initialization sequence, `FIXED_REGION_MODE=1` was tested again on real MiSTer
hardware.

Observed result:

- White debug screen appeared.
- MiSTer menu return worked.
- The real audio output produced a clear FM tone.

This confirms that the VGM_SNIPPET path can produce hardware audio too. The
issue was not the MiSTer shell or `AUDIO_L/R`; the snippet needed a known-good
startup sequence and reliable region-mode selection.

The snippet has now been changed from a single sustained tone to a short,
listenably distinct sequence:

```text
known-good YM init/timbre/frequency/pan/key-on
FM note 1   wait 22050 samples, about 0.5 seconds
FM note 2   write A4/A0 frequency, wait 22050 samples
FM note 3   write A4/A0 frequency, wait 22050 samples
FM key-off / DAC zero / DAC off
short settle wait
PSG ch0 tone setup and volume unmute
PSG tone    wait 22050 samples
FM key-off / DAC zero / DAC off / PSG mute
short settle wait
66 end
```

Only `REGION_MODE=1` was changed for this step. The proven BRINGUP_TONE region,
`emu.sv`, `mister_vgm_md_top.sv`, `md_sound_module.sv`, JT12/JT89, and
`AUDIO_L/R >>> 2` scaling remain unchanged.

## 2026-06-05: VGM Snippet PSG Three-Tone Isolation

The `REGION_MODE=1` VGM_SNIPPET build was tested on real MiSTer hardware after
the first-audio fix.

Observed result:

- White debug screen appeared.
- MiSTer menu return worked.
- The real audio output produced a sound described as `ぷーー〜〜`.
- The sound grew in volume and ended.

This confirms that the `REGION_MODE=1` selection and the real MiSTer audio path
are working, but the previous FM-focused snippet did not sound like the expected
FM three-note plus PSG sequence. For the next isolation step, `REGION_MODE=1`
has been changed to a PSG-focused three-tone test:

```text
YM key-off / DAC zero / DAC off
PSG all channels mute
short settle wait
PSG ch0 tone period 0x100, volume unmute, wait 22050 samples
PSG ch0 mute, short wait
PSG ch0 tone period 0x080, volume unmute, wait 22050 samples
PSG ch0 mute, short wait
PSG ch0 tone period 0x040, volume unmute, wait 22050 samples
PSG all channels mute
YM key-off / DAC zero / DAC off
short settle wait
66 end
```

The purpose is to make command progression and VGM wait handling audible with
three clearly different PSG pitches before returning to more complex FM/VGM
snippets. BRINGUP_TONE remains unchanged.

Follow-up hardware observation:

- `FIXED_REGION_MODE=1` was present in the `.qsf`.
- The source on the Windows build side also contained the PSG ch0 note entries.
- The real hardware still sounded like a rising `ぷーー〜〜` rather than three
  separated PSG tones.

For the next isolation build, the PSG tone period bytes were kept explicit as
individual VGM `0x50` PSG writes, and the inter-note mute gaps were lengthened:

```text
period 0x100:
  50 80
  50 10
  50 90
  wait 22050
  50 9F
  wait 8820

period 0x080:
  50 80
  50 08
  50 90
  wait 22050
  50 9F
  wait 8820

period 0x040:
  50 80
  50 04
  50 90
  wait 22050
```

The important point is that VGM command `0x50` sends exactly one byte to
SN76489/JT89. The 10-bit PSG tone period is therefore split across a latch byte
and a following data byte; it is not stored as a raw multi-byte integer in the
VGM command stream.

Changing the debug screen from white to cyan for `REGION_MODE=1` requires a
small `emu.sv` video-color change. That was intentionally not done in this step
because the requested constraint also said to leave `emu.sv` unchanged.

## 2026-06-05: Cyan Screen Check for FIXED_REGION_MODE=1

The PSG three-tone snippet still did not sound like three separated notes on
real MiSTer hardware. The audible result was closer to a sustained rising
`ぶーーー〜〜` sound, so the next question is whether the Quartus build is truly
using the `FIXED_REGION_MODE=1` region.

For this hardware build check, the debug color path in `emu.sv` was minimally
changed:

- If `FIXED_REGION_MODE` is undefined or `0`, `audio_seen_latched` remains white.
- If `FIXED_REGION_MODE=1`, `audio_seen_latched` becomes cyan.

This is only a visual build-selection check. `AUDIO_L/R`, the `>>> 2` output
scaling, `mister_vgm_md_top`, `md_sound_module`, JT12/JT89, and
`vgm_region_player` were not changed for this step.

Expected interpretation on real hardware:

- Cyan screen after audio starts: the `FIXED_REGION_MODE=1` build reached
  `emu.sv`, so the VGM_SNIPPET build selection is active.
- White screen after audio starts: the build is still using the default region,
  or the Quartus macro/source synchronization needs to be checked.

## 2026-06-05: Source-Forced Snippet and Cyan Check

The first cyan-check RBF still showed a white screen and the audible result did
not change. The Mac-side source had already been pushed up to commit
`8fbcfde` (`Show cyan for fixed VGM snippet mode`), so the likely suspects are:

- the Quartus `VERILOG_MACRO` assignment is not being applied as expected, or
- the Windows/Quartus build is using an older source directory or an older RBF.

For the next isolation build, the QSF macro dependency was intentionally removed
from the hardware-identification path:

- `emu.sv` now shows cyan after `audio_seen_latched` unconditionally.
- `vgm_region_player.sv` now defaults `REGION_MODE` to `1` in source.
- `md_sound_fixed_region_test` also defaults `REGION_MODE` to `1` in source.

The BRINGUP_TONE ROM is still present and can be selected explicitly by setting
the parameter to `0`, but the normal no-override hardware path should now use
VGM_SNIPPET without relying on `FIXED_REGION_MODE`.

Expected interpretation on real hardware:

- Cyan screen: the new `emu.sv` source is in the RBF.
- Cyan plus PSG snippet behavior: the new `vgm_region_player.sv` source is also
  in the RBF.
- White screen: Quartus or MiSTer is still using an old source/RBF path.

## 2026-06-05: Add Known-Good FM Before PSG Snippet

The source-forced build reached real MiSTer hardware: the debug screen became
cyan, proving that the latest `emu.sv` and the `REGION_MODE=1` path were present
in the RBF. However, the PSG-focused snippet still did not produce the expected
three-tone sound. The only audible result was a short `ブッ` at core reset.

For the next isolation build, only the `REGION_MODE=1` VGM_SNIPPET ROM was
changed. The snippet now starts with the known-good FM/YM sequence that already
played successfully on hardware:

```text
known-good YM init/timbre/frequency/pan/key-on
FM tone wait 44100 samples, about 1 second
FM key-off
DAC zero / DAC off
wait 8820 samples, about 0.2 seconds
PSG ch0 three-tone test
final silence sequence
66 end
```

This separates the next hardware result into two questions:

- If the first FM tone is audible, JT12/FM writes still work in the forced
  snippet path.
- If FM is audible but the PSG section is still silent, the remaining issue is
  specific to the PSG command sequence, PSG write timing, or mixer path during
  this snippet.

The cyan debug screen and source-forced `REGION_MODE=1` default remain in place
for this check. `emu.sv`, `AUDIO_L/R`, output `>>> 2` scaling,
`mister_vgm_md_top`, `md_sound_module`, JT12, and JT89 were not changed.

## 2026-06-05: Forced VGM Snippet Hardware Confirmation

The source-forced VGM_SNIPPET build was tested again on real MiSTer hardware.

Observed result:

- The screen became cyan.
- This confirms that the forced `REGION_MODE=1` / VGM_SNIPPET build was present
  in the RBF.
- The first FM lead-in tone was audible as a clear `ぴー` sound.
- MiSTer menu return still worked.

Conclusion:

- The Windows/Quartus/RBF path is now confirmed to include the latest source.
- The forced VGM_SNIPPET path is active on hardware.
- JT12/FM writes still work in the forced snippet path.
- The remaining bring-up focus is now the PSG section after the FM lead-in.

## 2026-06-06: Auto-Start Delay After Core Load

The forced VGM_SNIPPET hardware build was confirmed further:

- The screen became cyan.
- The FM lead-in tone was audible.
- The sound stopped at the end.
- MiSTer menu return worked.

However, the sound did not start immediately after loading the core. It started
only after issuing a MiSTer core reset. This points to the fixed-region
auto-start pulse being too early during initial core load, before the PLL,
audio path, JT12/JT89, or reset synchronizers are fully settled.

`mister_vgm_md_top.sv` now delays the one-shot start pulse after reset release:

```systemverilog
parameter logic [31:0] START_DELAY_CYCLES = 32'd25_000_000
```

At a 50 MHz `clk_sys`, the default delay is about 0.5 seconds. The testbench
overrides this to a smaller value so simulation remains fast:

```systemverilog
.START_DELAY_CYCLES(32'd1024)
```

Only the auto-start timing was changed. `emu.sv` debug latches/colors,
`AUDIO_L/R`, output `>>> 2` scaling, `md_sound_module`, JT12/JT89, and
`vgm_region_player` were not changed for this step.

## 2026-06-06: Internal Power-On Reset Sequencer

`START_DELAY_CYCLES=25_000_000` alone did not fix the real-hardware symptom:
after loading the core, the fixed snippet still stayed silent until a MiSTer
core reset was issued. Since the same design plays after manual core reset, the
audio path and player path are still considered good. The likely issue is that
the first auto-start sequence after FPGA configuration begins before all local
reset/startup state is in a known condition.

`rtl/mister_vgm_md_top.sv` now has a separate internal power-on reset sequencer:

```systemverilog
parameter logic [31:0] POWER_ON_RESET_CYCLES = 32'd25_000_000;
parameter logic [31:0] START_DELAY_CYCLES    = 32'd25_000_000;
```

The internal reset is asserted while either condition is true:

```text
external reset_n is low / synchronizer reset is active
OR
internal power-on reset counter is still active
```

After the internal reset period completes, the existing start-delay counter
runs. Only after that does `mister_vgm_md_top` emit the one-clock `start_pulse`
to `md_sound_fixed_region_test`. A later MiSTer core reset drives the same
sequence again, so manual reset and core-load startup now use the same path.

Additional debug outputs were added from `mister_vgm_md_top` to `emu.sv`:

```text
startup_reset_active  internal power-on reset is being held
startup_waiting       reset is released and the start-delay counter is running
startup_done          start pulse has already been issued
```

The hardware debug colors now distinguish the startup phases:

```text
yellow   internal power-on reset active
magenta  waiting before start pulse
cyan     audio_sample_valid has been observed
blue     player_done latched
red      player_busy
green    idle/running baseline
```

`audio_seen_latched` and `done_latched` are cleared during the internal
power-on reset window, so the color state should not contain stale startup
information.

Simulation keeps the real hardware defaults out of the slow path by overriding
the counters in `tb/tb_mister_vgm_md_top.sv`:

```systemverilog
.POWER_ON_RESET_CYCLES(32'd2048),
.START_DELAY_CYCLES(32'd1024)
```

The top-level smoke test completed with the delayed startup sequence:

```text
MISTER_VGM_MD_TOP_TEST_DONE
wav_written_samples=5000
audio_sample_valid_edges=5000
startup_reset=0
startup_waiting=0
startup_done=1
```

`AUDIO_L/R`, output `>>> 2` scaling, `md_sound_module`, JT12/JT89, and
`vgm_region_player` were not changed for this step.

## 2026-06-06: Cold-Load Startup Registers Made Edge-Independent

The internal power-on reset from the previous step was visible on real hardware
when the MiSTer core reset button was pressed: the screen briefly became
yellow, then the fixed snippet played. However, a cold core load / cold boot
still did not start audio. This means the reset path after a manual reset is
good, but the configuration-time startup state may not have been entering the
same known sequence.

`rtl/mister_vgm_md_top.sv` was adjusted so the startup sequence no longer
depends on seeing a `reset_n` rising edge. The startup-related registers now
have explicit synthesizable initial values:

```systemverilog
reset_sync          = 3'b111
por_counter         = 32'd0
por_done            = 1'b0
start_delay_counter = 32'd0
start_sent          = 1'b0
start_pulse         = 1'b0
```

With these values, even if `reset_n` is already high immediately after FPGA
configuration, the module starts in this state:

```text
POR not done
start not sent
internal reset asserted
```

The sequence is now:

```text
configuration/cold load initial state
  -> POR counter runs
  -> por_done becomes 1
  -> START_DELAY counter runs
  -> one-clock start_pulse
  -> start_sent remains 1
```

If external `reset_n` is driven low later, the same registers are returned to
the initial startup state, so a MiSTer core reset and a cold load should follow
the same playback path.

`tb/tb_mister_vgm_md_top.sv` was changed to keep `reset_n` high from time zero
instead of creating an initial reset pulse. This simulates the important
failure case: startup must work from register initial values, not only after a
reset release edge.

The cold-start-style TB completed:

```text
MISTER_VGM_MD_TOP_TEST_START cold_start_reset_n_initial_high=1
MISTER_VGM_MD_TOP_TEST_DONE
wav_written_samples=5000
audio_sample_valid_edges=5000
startup_reset=0
startup_waiting=0
startup_done=1
```

`emu.sv`, `AUDIO_L/R`, output `>>> 2` scaling, `md_sound_module`, JT12/JT89,
and `vgm_region_player` were not changed for this step.

## 2026-06-06: Hold VGM Top Reset Until PLL Locked

The cold-load test on real MiSTer hardware still did not start audio, while a
manual MiSTer core reset did. During manual reset the screen briefly became
yellow, proving that the `mister_vgm_md_top` startup reset sequence runs when a
valid reset is delivered to it. The next suspicion is that, during cold core
load, relying only on internal initial values is not enough and the sound top
needs a reset explicitly tied to the MiSTer/PLL startup state.

`rtl/emu.sv` already had the InputTest-derived PLL `locked` signal:

```systemverilog
wire pll_locked;
```

The raw core reset condition remains:

```systemverilog
RESET | status[0] | !pll_locked
```

For the VGM sound top, a dedicated reset stretcher was added. It keeps
`mister_vgm_md_top.reset_n` low while any reset request is active:

```text
MiSTer RESET
OR OSD/status reset, status[0]
OR PLL not locked
```

After those reset requests are released, it keeps reset asserted for an
additional 24-bit counter window before allowing `mister_vgm_md_top` to run.
At a 50 MHz clock this is about 0.33 seconds. After that, the existing internal
`POWER_ON_RESET_CYCLES` and `START_DELAY_CYCLES` sequence inside
`mister_vgm_md_top` still runs normally.

The intended startup order is now:

```text
PLL not locked
  -> vgm_reset_n held low
PLL locked
  -> emu-side reset stretcher holds vgm_reset_n low a little longer
vgm_reset_n released
  -> mister_vgm_md_top internal POR
  -> mister_vgm_md_top start delay
  -> one-clock start pulse
  -> audio_sample_valid observed
```

Debug colors are unchanged:

```text
yellow   mister_vgm_md_top startup reset active
magenta  start delay waiting
cyan     audio_sample_valid observed
```

`AUDIO_L/R`, output `>>> 2` scaling, `md_sound_module`, JT12/JT89, and
`vgm_region_player` were not changed. The `tb_mister_vgm_md_top` smoke test
still completed with 5000 audio sample edges after this change.
