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

## 2026-06-06: Cold Boot / Core Load Audio Startup Confirmed

The PLL-locked reset stretcher change was tested on real MiSTer hardware.

Observed result:

- Audio now starts after cold boot / core load, without requiring a manual core
  reset.
- MiSTer menu return still works.
- The screen becomes cyan after `audio_seen_latched`, confirming
  `audio_sample_valid` was observed.
- Pressing core reset briefly shows yellow, confirming the startup reset phase
  is still visible and reruns on reset.

Conclusion:

- The previous failure was consistent with `mister_vgm_md_top` not receiving a
  reliable reset during cold core load.
- Holding `mister_vgm_md_top.reset_n` low until PLL lock, then extending reset
  with the emu-side reset stretcher, fixes cold-load startup.
- The existing internal POR/start-delay sequence inside `mister_vgm_md_top`
  remains useful after the emu-side reset is released.

No RTL changes were made for this log entry.

## 2026-06-06: Cold Boot / Core Load Startup Reconfirmed

The same real-hardware result was reconfirmed after the PLL-locked reset stretcher fix:

- Audio starts after cold boot / core load.
- MiSTer menu return works.
- The screen becomes cyan after audio_seen_latched.
- Pressing reset briefly shows yellow.

This confirms that using pll_locked plus MiSTer reset/status reset as the VGM top reset condition solved the automatic playback failure after core load.

No RTL changes were made for this confirmation entry.

## 2026-06-06: VGM Snippet PSG Three-Note Test

After cold boot / core load startup was confirmed, `REGION_MODE=1` was kept as
the active hardware snippet path and the snippet content was adjusted for the
next audible check. The proven BRINGUP_TONE ROM was not changed.

Current VGM_SNIPPET shape:

```text
known-good FM lead-in, about 1 second
FM key-off / DAC off
PSG ch0 note 1, about 0.4 seconds
mute gap, about 0.2 seconds
PSG ch0 note 2, about 0.4 seconds
mute gap, about 0.2 seconds
PSG ch0 note 3, about 0.4 seconds
final silence sequence
66 end
```

The PSG notes now send SN76489 tone periods as explicit byte sequences: latch
low nibble, high bits, then volume. This avoids the earlier ambiguity where a
10-bit PSG period could be mistaken for a single VGM `0x50` payload byte.

`REGION_MODE=1` remains source-forced, and the cyan `audio_seen_latched` display
path remains in place. `emu.sv`, `mister_vgm_md_top`, `md_sound_module`,
JT12/JT89, and `AUDIO_L/R` scaling were not changed for this step.

## 2026-06-06: VGM Snippet FM + PSG Three-Note Hardware Pass

The updated `REGION_MODE=1` VGM_SNIPPET was tested on real MiSTer hardware.

Observed result:

- The screen became cyan, confirming `audio_seen_latched`.
- Audio started immediately after cold boot / core load.
- The known-good FM lead-in was audible.
- The PSG three-note section was audible and distinguishable, like `ぴー・ポー・ぷー`.
- The final silence sequence stopped the sound.
- MiSTer menu return still worked.

Conclusion:

- The forced `REGION_MODE=1` snippet path is active on hardware.
- The cold-load reset/start sequence is working.
- YM/JT12 output works in the snippet path.
- PSG/JT89 output works in the snippet path.
- The fixed ROM can now play a short mixed FM + PSG phrase, not just a single
  bring-up tone.

No RTL changes were made for this log entry.

## 2026-06-06: Startup Audio Gate and Snippet Silence Init

Real-hardware testing showed that the VGM_SNIPPET path can play FM and PSG, but
cold boot / reset behavior is still not fully stable: sometimes the initial
sound is quiet, uneven, or appears to grow in volume. This is treated as an
initialization/reset settling issue, not as an output volume problem. The
external AUDIO `>>> 2` scaling was intentionally left unchanged.

Changes for this isolation step:

- Added an `audio_gate_open` startup signal in `mister_vgm_md_top`.
- Kept external audio muted until after startup reset, start-delay, and a small
  number of `audio_sample_valid` edges have occurred.
- Opened the audio gate before issuing the one-shot fixed-region `start_pulse`.
- Gated `AUDIO_L/R` to zero in `emu.sv` while `audio_gate_open` is low.
- Left `md_sound_module`, JT12, JT89, and the `>>> 2` audio scaling unchanged.
- Added a VGM_SNIPPET-only silence initialization prefix before the audible
  phrase:

```text
52 28 00      YM key off
52 2A 00      DAC data zero
52 2B 00      DAC off
50 9F         PSG ch0 mute
50 BF         PSG ch1 mute
50 DF         PSG ch2 mute
50 FF         PSG noise mute
61 44 AC      wait 44100 samples
```

Debug color intent for this step:

```text
yellow   startup reset / init reset
magenta  muted init wait / start wait
cyan     audio_sample_valid has been seen before gate opens
white    audio gate open after init wait
```

The goal is to ensure that no unstable cold-boot audio reaches MiSTer output and
that the fixed snippet starts only after the sound path has had time to settle.


## 2026-06-06: Audio Warmup Before Snippet Start

Real-hardware testing improved after the startup audio gate, but cold boot still
cut the first note sometimes. Core reset playback was cleaner, which suggests
that HDMI/audio output may still be settling when the snippet begins after a
cold load. This is still treated as a startup sequencing issue, not a volume
scaling issue. The existing AUDIO `>>> 2` scaling remains unchanged.

`mister_vgm_md_top` now waits for an additional audio-sample warmup period
before starting the fixed snippet:

```systemverilog
parameter logic [15:0] AUDIO_WARMUP_SAMPLES = 16'd22050
```

At 44.1 kHz this is about 0.5 seconds. During this warmup, `md_sound_module` is
running and `audio_sample_valid` is being counted, but `emu.sv` keeps
`AUDIO_L/R` at zero because `audio_gate_open` remains low. After warmup
completes, the gate opens, a short gate-to-start delay runs, and then the
one-shot snippet `start_pulse` is emitted.

The intended sequence is now:

```text
yellow   startup reset / init reset
magenta  reset released, start/audio warmup waiting
cyan     audio_sample_valid has been seen while output is still muted
white    audio gate open / warmup complete
start    fixed snippet begins after the gate-to-start delay
```

Color priority in `emu.sv` is reset > gate open > sample seen > waiting.
`md_sound_module`, JT12, JT89, `vgm_region_player`, and the AUDIO `>>> 2`
scaling were not changed for this step.


## 2026-06-06: Fixed ROM Region Mode 2, Real-VGM-Derived YM Snippet

The hardware bring-up tone and the VGM_SNIPPET smoke test are now confirmed, so
the next fixed-ROM step is a short snippet derived from an actual VGM command
stream instead of a purely hand-authored tone.

New fixed region mode:

```text
REGION_MODE = 0   BRINGUP_TONE, proven FM -> PSG -> silence hardware tone
REGION_MODE = 1   VGM_SNIPPET smoke test, proven FM lead-in + PSG 3-note test
REGION_MODE = 2   VGM_REAL_SNIPPET, short real-VGM-derived YM snippet
```

`REGION_MODE=2` is derived from:

```text
/Users/daizo/Downloads/fm_only_test.vgm
first active YM2612 KeyOn pc = 0x0000044B
KeyOn command = 52 28 F0
```

The fixed ROM does not include PCM/DAC stream commands. It distills the latest
YM2612 channel-1 register values seen before that first active KeyOn, keeps
them as VGM-style `0x52 reg data` opcodes, then holds the resulting tone for
about 5000 audio samples. The region ends with the same explicit silence style
used by the bring-up tests:

```text
52 28 00      YM key off
52 2A 00      DAC data zero
52 2B 00      DAC off
50 9F         PSG ch0 mute
50 BF         PSG ch1 mute
50 DF         PSG ch2 mute
50 FF         PSG noise mute
61 00 04      wait 1024 samples
66            end
```

For hardware identification, `FIXED_REGION_MODE=2` changes the gate-open debug
screen to purple. Existing mode 0 and mode 1 behavior remains available.

Simulation commands:

```sh
iverilog -g2012 -Wall -DSIMULATION -s tb_md_sound_fixed_region_test \
  -o /tmp/tb_md_sound_fixed_region_mode0.vvp \
  tb/tb_md_sound_fixed_region_test.sv \
  rtl/vgm_region_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v

iverilog -g2012 -Wall -DSIMULATION -DTEST_FIXED_VGM_SNIPPET \
  -s tb_md_sound_fixed_region_test \
  -o /tmp/tb_md_sound_fixed_region_mode1.vvp \
  tb/tb_md_sound_fixed_region_test.sv \
  rtl/vgm_region_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v

iverilog -g2012 -Wall -DSIMULATION -DTEST_FIXED_VGM_REAL_SNIPPET \
  -s tb_md_sound_fixed_region_test \
  -o /tmp/tb_md_sound_fixed_region_mode2.vvp \
  tb/tb_md_sound_fixed_region_test.sv \
  rtl/vgm_region_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v

vvp /tmp/tb_md_sound_fixed_region_mode0.vvp
vvp /tmp/tb_md_sound_fixed_region_mode1.vvp
vvp /tmp/tb_md_sound_fixed_region_mode2.vvp
```

Observed fixed-region smoke results:

```text
REGION_MODE=0:
wav_written_samples=5000
audio_sample_valid_edges=5000
pc=90
last_cmd=61

REGION_MODE=1:
wav_written_samples=5000
audio_sample_valid_edges=5000
pc=20
last_cmd=61

REGION_MODE=2:
wav_written_samples=5000
audio_sample_valid_edges=5000
pc=131
last_cmd=61
fixed_region_mode2_dump min_l=-922 max_l=1027 min_r=-922 max_r=1027 nonzero=3868 samples=5000
```

Top-level smoke command for the new mode:

```sh
iverilog -g2012 -Wall -DSIMULATION -DFIXED_REGION_MODE=2 \
  -s tb_mister_vgm_md_top \
  -o /tmp/tb_mister_vgm_md_top_mode2.vvp \
  tb/tb_mister_vgm_md_top.sv \
  rtl/mister_vgm_md_top.sv \
  rtl/vgm_region_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v

vvp /tmp/tb_mister_vgm_md_top_mode2.vvp
```

Observed top-level result:

```text
MISTER_VGM_MD_TOP_TEST_DONE
wav_written_samples=5000
audio_sample_valid_edges=5000
pc=131
last_cmd=61
startup_reset=0
startup_waiting=0
startup_done=1
audio_gate_open=1
mister_top_mode2_dump min_l=-922 max_l=1050 min_r=-922 max_r=1050 nonzero=3725 samples=5000
```

To build this mode for MiSTer hardware, use the normal project flow with:

```tcl
set_global_assignment -name VERILOG_MACRO "FIXED_REGION_MODE=2"
```

The existing 50K regression path and the previous fixed regions are not changed
by this mode addition.


## 2026-06-06: Source-Default Force For Region Mode 2 Hardware Test

On inspection, `VGM_MD_MiSTer.qsf` did not contain a `FIXED_REGION_MODE`
`VERILOG_MACRO` assignment. That means earlier hardware region selection was
very likely coming from source defaults, not from the Quartus project file.

For the next real-hardware check, the project intentionally avoids depending on
QSF macro propagation. A small shared header now owns the temporary source-side
default:

```systemverilog
// rtl/fixed_region_mode.vh
`ifndef FIXED_REGION_MODE
`define FIXED_REGION_MODE 2
`endif
```

Both `rtl/vgm_region_player.sv` and `rtl/emu.sv` include this header, so the ROM
selection and the debug color selection use the same value. With no QSF macro:

```text
REGION_MODE=2 is selected by default
gate-open debug color is purple
```

`VGM_MD_MiSTer.qsf` was not changed for this step. AUDIO `>>> 2`,
`md_sound_module`, JT12, and JT89 were not changed.

Verification:

```sh
iverilog -g2012 -Wall -DSIMULATION -s tb_md_sound_fixed_region_test \
  -o /tmp/tb_md_sound_fixed_region_default.vvp \
  tb/tb_md_sound_fixed_region_test.sv \
  rtl/vgm_region_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v

vvp /tmp/tb_md_sound_fixed_region_default.vvp
```

Observed result without any `TEST_FIXED_*` override:

```text
FIXED_REGION_TEST_START samples=5000 region_mode=2
FIXED_REGION_TEST_DONE wav_written_samples=5000 audio_sample_valid_edges=5000 pc=131 last_cmd=61 busy=1 done=0
```

To explicitly re-run the older bring-up region in simulation, use:

```sh
iverilog -g2012 -Wall -DSIMULATION -DTEST_FIXED_BRINGUP_TONE \
  -s tb_md_sound_fixed_region_test \
  -o /tmp/tb_md_sound_fixed_region_mode0_explicit.vvp \
  tb/tb_md_sound_fixed_region_test.sv \
  rtl/vgm_region_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v
```


## 2026-06-06: Region Mode 2 Hardware Sound Needs 50k Simulation Check

Real MiSTer hardware confirmed that source-default `REGION_MODE=2` is active:

```text
screen: purple
menu return: OK
audio: short "ププププ" style sound that appears to speed up
```

This proves the mode 2 ROM is selected on hardware, but it does not yet prove
that the real-VGM-derived snippet is musically held in the intended way. The
next check is to dump a longer simulation WAV for mode 2 and compare it against
the hardware sound.

New TB mode:

```text
define: TEST_FIXED_VGM_REAL_SNIPPET_50K
REGION_MODE: 2
samples: 50000
txt output: /tmp/md_sound_fixed_vgm_real_snippet_50k.txt
```

Build and run:

```sh
iverilog -g2012 -Wall -DSIMULATION -DTEST_FIXED_VGM_REAL_SNIPPET_50K \
  -s tb_md_sound_fixed_region_test \
  -o /tmp/tb_md_sound_fixed_vgm_real_snippet_50k.vvp \
  tb/tb_md_sound_fixed_region_test.sv \
  rtl/vgm_region_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v

vvp /tmp/tb_md_sound_fixed_vgm_real_snippet_50k.vvp
```

WAV conversion:

```sh
python3 tools/audio_txt_to_wav/audio_txt_to_wav.py \
  /tmp/md_sound_fixed_vgm_real_snippet_50k.txt \
  /tmp/md_sound_fixed_vgm_real_snippet_50k_gain1.wav \
  --gain 1

python3 tools/audio_txt_to_wav/audio_txt_to_wav.py \
  /tmp/md_sound_fixed_vgm_real_snippet_50k.txt \
  /tmp/md_sound_fixed_vgm_real_snippet_50k_gain4.wav \
  --gain 4
```

Interpretation:

```text
If the simulation WAV also sounds like short "ププププ":
  The mode 2 snippet itself is too short or lacks enough original VGM context.

If the simulation WAV holds a normal sustained/musical tone:
  Suspect the hardware wait/audio timing path or startup timing around mode 2.
```

Possible next edit, only after listening to the 50k WAV:

```text
Add an explicit long hold after the mode 2 KeyOn:
  61 44 AC   wait 44100 samples, about 1 second

or replace the current 5000-sample hold:
  61 88 13   wait 5000 samples

with:
  61 44 AC   wait 44100 samples
```

For this step, the snippet body, JT12/JT89, `md_sound_module`, the existing 50K
regression, mode 0, mode 1, and AUDIO `>>> 2` were not changed.


## 2026-06-06: Region Mode 2 Context Slice Rebuild

The first 50k mode 2 simulation WAV was also heard as a short "ぶおん" style
sound. Because the MiSTer hardware result and the simulation result matched in
that direction, the problem was classified as a mode 2 fixed-ROM snippet issue,
not a MiSTer audio output issue.

Conclusion:

```text
mode 2 sim WAV also short/noisy:
  real hardware path is probably not the primary problem

likely cause:
  the VGM cut was too close to the first active KeyOn and lacked enough
  preceding YM initialization/timbre/frequency context
```

The mode 2 ROM was rebuilt from a wider `fm_only_test.vgm` context slice:

```text
source VGM: /Users/daizo/Downloads/fm_only_test.vgm
slice start pc: 0x000003E2
first active KeyOn pc: 0x0000044B
slice end pc: 0x00000D51
copied active wait: 44368 samples, about 1 second
generated include: rtl/vgm_real_snippet_mode2_case.vh
ROM byte count including silence prefix/suffix: 2477
```

The fixed player change was kept local to the region ROM path:

```text
REGION_MODE=2 now uses vgm_real_context_rom_byte()
the old compact mode 2 function remains in the source but is no longer selected
internal ROM pc was widened to 12 bits
external pc_debug remains 10 bits
0x4F Game Gear stereo commands are skipped by the fixed player
```

Unchanged:

```text
emu.sv
AUDIO_L/R and >>> 2 scaling
mister_vgm_md_top
md_sound_module
JT12/JT89 sources
REGION_MODE=0 bring-up tone
REGION_MODE=1 smoke snippet
```

50k simulation check:

```sh
iverilog -g2012 -Wall -DSIMULATION -DTEST_FIXED_VGM_REAL_SNIPPET_50K \
  -s tb_md_sound_fixed_region_test \
  -o /tmp/tb_md_sound_fixed_vgm_real_snippet_50k.vvp \
  tb/tb_md_sound_fixed_region_test.sv \
  rtl/vgm_region_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v

vvp /tmp/tb_md_sound_fixed_vgm_real_snippet_50k.vvp
```

Observed simulation summary:

```text
FIXED_REGION_TEST_START samples=50000 region_mode=2
FIXED_REGION_TEST_DONE wav_written_samples=50000 audio_sample_valid_edges=50000 pc=428 last_cmd=66 busy=0 done=0
```

WAV outputs:

```text
/tmp/md_sound_fixed_vgm_real_snippet_50k_gain1.wav
/tmp/md_sound_fixed_vgm_real_snippet_50k_gain2.wav
/Users/daizo/Downloads/md_sound_fixed_vgm_real_snippet_50k_gain1.wav
/Users/daizo/Downloads/md_sound_fixed_vgm_real_snippet_50k_gain2.wav
```

Statistics:

```text
gain1:
  frames=50000
  min=-4377
  max=3216
  nonzero=97652
  rms=926.36
  clip_count=0

gain2:
  frames=50000
  min=-8754
  max=6432
  nonzero=97652
  rms=1852.73
  clip_count=0
```

The regenerated mode 2 WAV is now long enough to judge whether the fixed ROM is
musically usable before taking the same mode 2 build back to MiSTer hardware.


## 2026-06-06: Region Mode 2 Hardware Pass and Silence Strengthening

`REGION_MODE=2 / VGM_REAL_SNIPPET` was tested on real MiSTer hardware.

Observed result:

```text
screen: purple
MiSTer menu return: OK
audio: real-VGM-derived FM tone, heard as "ブォーーーーン"
problem: the tone did not stop at the end
```

This confirmed that the wider real-VGM-derived mode 2 ROM is active on
hardware and that the YM/JT12/audio path works for the snippet. The remaining
problem was classified as insufficient final silence, not as a playback path
failure.

Reasoning:

```text
The previous mode 2 suffix only wrote:
  52 28 00

But the real VGM slice can key on channels other than ch1. The tail of the
slice also contains YM key-on values such as 52 28 F2/F5/F6, so a ch1-only
key-off is not enough.
```

The `REGION_MODE=2` suffix was strengthened:

```text
YM2612 key-off for all 6 channels:
  52 28 00
  52 28 01
  52 28 02
  52 28 04
  52 28 05
  52 28 06

DAC zero/off:
  52 2A 00
  52 2B 00

PSG mute all:
  50 9F
  50 BF
  50 DF
  50 FF

final wait:
  61 44 AC   wait 44100 samples, about 1 second

end:
  66
```

This change was made only in the mode 2 fixed ROM include:

```text
rtl/vgm_real_snippet_mode2_case.vh
```

Unchanged:

```text
emu.sv
AUDIO_L/R and >>> 2 scaling
mister_vgm_md_top
md_sound_module
JT12/JT89 sources
REGION_MODE=0 bring-up tone
REGION_MODE=1 smoke snippet
```

The alternative safety gate, forcing `AUDIO_L/R=0` after
`player_done_latched`, was considered but not added in this step. The first
fix is to make the VGM command stream itself end cleanly, so the same command
path remains valid for both simulation and hardware.

Build sanity check:

```sh
iverilog -g2012 -Wall -DSIMULATION -DTEST_FIXED_VGM_REAL_SNIPPET_50K \
  -s tb_md_sound_fixed_region_test \
  -o /tmp/tb_md_sound_fixed_vgm_real_snippet_50k.vvp \
  tb/tb_md_sound_fixed_region_test.sv \
  rtl/vgm_region_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v
```

Result:

```text
build passed
warnings are the existing JT12/timescale/unique-case warnings
```


## 2026-06-06: Region Mode 2 Hardware Pass After Strong Silence

The strengthened `REGION_MODE=2 / VGM_REAL_SNIPPET` build was tested again on
real MiSTer hardware.

Observed result:

```text
screen: purple
MiSTer menu return: OK
audio:
  real-VGM-derived FM tone played as an engine-like "ぶおおおおおおん"
  then decayed/stopped as "おん、おん、おん"
  finally reached silence
```

Conclusion:

```text
REGION_MODE=2 is active on hardware
the real-VGM-derived FM snippet reaches JT12 and AUDIO_L/R
the strengthened final silence sequence works
```

The successful stop is attributed to the strengthened suffix:

```text
YM2612 all-channel key-off
DAC data zero
DAC off
PSG mute all
final wait before 0x66 end
```

No RTL was changed for this note. This records the hardware pass result only.


## 2026-06-09: Mode 5 Audio Path Hardware Status

Current best audio configuration:

```text
FIXED_REGION_MODE=5
MD_JT12_CEN_NTSC_TEST=1
MD_JT12_LADDER_EFFECT_TEST=1
MD_AUDIO_PRE_GENMIX_FM_LPF_TEST=1
```

Confirmed on real MiSTer hardware:

```text
OSD-loaded VGM playback works.
fm_only_test.vgm plays full length and loops at the correct ~150s timing.
Menu return remains OK.
single_fm_sustain.vgm is clean.
```

Major audio fixes confirmed:

```text
MD_JT12_CEN_NTSC_TEST + MD_JT12_LADDER_EFFECT_TEST:
  fixed the major snare / hi-hat / FM harshness.

MD_AUDIO_PRE_GENMIX_FM_LPF_TEST:
  fixed the patch104 / CH1 / OP1 feedback noise.
  patch104 diagnostic VGMs now sound much closer to foobar/VGMRips.
```

Patch104 investigation summary:

```text
CH1 patch104 analysis showed the issue was strongly tied to OP1/operator
interaction and feedback-heavy FM patch behavior.

The simple DC-block / difference high-pass test did not fix the issue and made
noise worse.

The successful fix was the Genesis_MiSTer-style pre-genmix FM LPF:

  JT12 raw FM
    -> fm_adjust
    -> genesis_fm_lpf
    -> jt12_genmix
    -> final genesis_lpf / audio output
```

Volume / loudness investigation:

```text
Force tone at sys_top/audio_out input is very loud.
Therefore HDMI / analog audio_out path is healthy.

Current FM-only playback remains quieter than Genesis_MiSTer.
On-screen peak and average absolute-value meters were added.

Genmix-output gain A/B was tested:
  2x: meters moved upward slightly
  4x: meters moved upward more
  6x: current safer candidate for further listening
  8x: meters moved upward significantly, but rail/clip red appeared

8x still did not fully match Genesis_MiSTer perceived volume, and it already
reached rail/clip peaks. Increasing this same stage further is unsafe.
```

Conclusion for volume:

```text
Do not pursue more gain changes for now.

The remaining FM-only perceived loudness mismatch may be RMS / average level /
dynamics related, not simply peak level.

This should be deferred and re-evaluated after PCM/DAC support is implemented,
because final Mega Drive balance needs FM + PSG + DAC together.
```

Next major task:

```text
Implement PCM/DAC support:
  0x67 data block storage
  0xE0 PCM seek
  0x80-0x8F DAC stream to YM2612 DAC register 0x2A

After PCM/DAC works:
  re-evaluate FM / PSG / DAC balance
  re-evaluate final perceived volume against Genesis_MiSTer
```

No RTL was changed for this note. This records the latest hardware result and
the next direction only.


## 2026-06-09: Mode 5 Loudness / Peak-vs-Average Diagnostic

Current working audio baseline remains:

```text
FIXED_REGION_MODE=5
MD_JT12_CEN_NTSC_TEST=1
MD_JT12_LADDER_EFFECT_TEST=1
MD_AUDIO_PRE_GENMIX_FM_LPF_TEST=1
```

Hardware observation with genmix-output gain A/B:

```text
2x after jt12_genmix / jt12_fm_uprate:
  meters moved upward slightly
  perceived volume increased slightly
  still much quieter than Genesis_MiSTer

4x after jt12_genmix / jt12_fm_uprate:
  meters moved upward more
  perceived volume increased
  patch104 remained clean
  no obvious rail/clip red indication

8x after jt12_genmix / jt12_fm_uprate:
  meters moved upward significantly
  perceived volume increased
  output still quieter than Genesis_MiSTer
  rail/clip red appeared at the right edge
  patch104 quality appeared preserved, but 8x is too aggressive as a pure peak gain
```

Conclusion:

```text
Genmix-output gain is on the real audio path and affects the measured signal.
However, 8x already reaches signed 16-bit rail/clip peaks while perceived
loudness remains below Genesis_MiSTer.

The remaining perceived loudness mismatch is therefore probably not just a peak
amplitude problem. It may be RMS / average level / dynamics related.
Further gain at the same point is unsafe because it will mainly clip peaks.
```

Diagnostics added:

```text
Peak bars:
  raw JT12 FM
  fm_adjust
  pre-genmix FM LPF
  jt12_genmix output
  md_sound_module final
  emu output
  sys_top/audio_out input

Average absolute-value bars:
  md_sound_module final, 4096 audio-sample window
  emu output, 4096 audio-sample window
  sys_top/audio_out input, 65536 clk_audio window
```

Current next A/B candidate:

```text
MD_AUDIO_GENMIX_OUTPUT_GAIN_6X_TEST
```

This is inserted at the same point as 2x/4x/8x:

```text
jt12_genmix / jt12_fm_uprate output
  -> signed saturating gain
  -> final genesis_lpf
  -> md_sound_module audio_l/r
```

Priority order is:

```text
8x > 6x > 4x > 2x > normal
```

For the next hardware build, QSF is set to the safer 6x candidate by defining
2x, 4x, and 6x, while leaving 8x disabled. 6x should be checked against:

```text
fm_only_test.vgm
ch1_main_patch.vgm
ch1_main_patch_fb7.vgm
ch1_main_patch_op1_plus_op4.vgm
```

Pass conditions:

```text
volume closer to Genesis_MiSTer than 4x
no rail/clip red indicators, or substantially less than 8x
patch104 remains clean
menu return remains OK
average bars help judge whether RMS/average level is still low
```


## 2026-06-08: JT12 Mode/Config Comparison A/B

Hardware observation before this step:

```text
current best config:
  FIXED_REGION_MODE=5
  MD_JT12_CEN_NTSC_TEST=1
  MD_JT12_LADDER_EFFECT_TEST=1

patch104 diagnostics:
  foobar/VGMRips plays ch1_main_patch.vgm, fb7, and op1+op4 cleanly
  MiSTer/JT12 current best makes the same files noisy
  disabling ladder reduces noise slightly, but does not make it clean
```

Conclusion going into this step:

```text
remaining issue is likely JT12 feedback/operator behavior or YM2612/YM3438
mode/config difference, especially around op1 feedback in patch104
```

Local JT12 wrapper inspection:

```text
rtl/genesis_audio/jt12/jt12.v:
  wrapper comment says it defaults to YM2612 mode
  exposed runtime config pins:
    en_hifi_pcm
    ladder
  no explicit ym2612/ym3438 mode input was found

rtl/genesis_audio/jt12/jt12_top.v:
  default parameters:
    use_lfo=1
    use_ssg=0
    num_ch=6
    use_pcm=1
    use_adpcm=0
    JT49_DIV=2
    mask_div=1
  no exposed feedback compatibility option was found
  en_hifi_pcm only affects YM2612 DAC/PCM interpolation path

rtl/genesis_audio/jt12/jt12_acc.v:
  ladder input adds the ladder-effect term
  comments distinguish YM2612 limiter behavior and YM3438 behavior, but this
  local wrapper exposes only ladder/en_hifi_pcm as runtime chip-character knobs
```

Genesis_MiSTer comparison:

```text
Genesis_MiSTer CONF_STR exposes:
  FM Chip,YM2612,YM3438
  HiFi PCM,No,Yes

Genesis_MiSTer top wiring:
  EN_HIFI_PCM(status[23])
  LADDER(~status[11])
  LPF_MODE(status[15:14])

Genesis_MiSTer files.qip includes:
  rtl/jt12/jt12.qip
```

Reference sources:

```text
https://github.com/MiSTer-devel/Genesis_MiSTer
https://github.com/MiSTer-devel/Genesis_MiSTer/blob/master/Genesis.sv
https://github.com/MiSTer-devel/Genesis_MiSTer/blob/master/files.qip
```

RTL diagnostic macros added:

```text
MD_JT12_FORCE_YM2612_TEST
  Forces local JT12 ladder config high.
  Intended as explicit YM2612-style label for hardware A/B.

MD_JT12_FORCE_YM3438_TEST
  Forces local JT12 ladder config low.
  Intended as explicit YM3438-style label for hardware A/B.

MD_JT12_FORCE_LADDER_ON_TEST
  Forces ladder high, overriding the named mode macros.

MD_JT12_FORCE_LADDER_OFF_TEST
  Forces ladder low, overriding the named mode macros.

MD_JT12_HIFI_PCM_TEST
  Drives en_hifi_pcm high.
  Expected to have no effect on fm_only_test/ch1 patch diagnostics because
  those files do not use YM DAC/PCM, but it is useful for matching the
  Genesis_MiSTer exposed option.
```

Macro priority:

```text
MD_JT12_FORCE_LADDER_OFF_TEST
MD_JT12_FORCE_LADDER_ON_TEST
MD_JT12_FORCE_YM3438_TEST
MD_JT12_FORCE_YM2612_TEST
MD_JT12_LADDER_EFFECT_TEST
default low
```

No loader, VGM timing, mode5 player, PCM/DAC parsing, or final mixer behavior
was changed in this step. No JT12 feedback compatibility macro was added because
the currently imported JT12 wrapper does not expose such a setting; feedback
level A/B remains best tested with the generated patch104 `fb0`..`fb7` VGM
diagnostics.

Suggested hardware A/B matrix:

```text
baseline current best:
  FIXED_REGION_MODE=5
  MD_JT12_CEN_NTSC_TEST=1
  MD_JT12_LADDER_EFFECT_TEST=1

explicit YM2612-style:
  FIXED_REGION_MODE=5
  MD_JT12_CEN_NTSC_TEST=1
  MD_JT12_FORCE_YM2612_TEST=1

explicit YM3438-style:
  FIXED_REGION_MODE=5
  MD_JT12_CEN_NTSC_TEST=1
  MD_JT12_FORCE_YM3438_TEST=1

ladder polarity sanity:
  FIXED_REGION_MODE=5
  MD_JT12_CEN_NTSC_TEST=1
  MD_JT12_FORCE_LADDER_ON_TEST=1

  FIXED_REGION_MODE=5
  MD_JT12_CEN_NTSC_TEST=1
  MD_JT12_FORCE_LADDER_OFF_TEST=1

HiFi PCM sanity:
  FIXED_REGION_MODE=5
  MD_JT12_CEN_NTSC_TEST=1
  MD_JT12_LADDER_EFFECT_TEST=1
  MD_JT12_HIFI_PCM_TEST=1
```

For each build, test `ch1_main_patch.vgm`, `ch1_main_patch_fb7.vgm`,
`ch1_main_patch_op1_plus_op4.vgm`, and `fm_only_test.vgm`. Watch the top 12-line
marker to confirm the expected macro is active before judging audio.


## 2026-06-08: FM DC-Block / High-Pass Diagnostic A/B

External review hypothesis:

```text
The remaining patch104 noise may be caused by missing DC blocking or
high-pass filtering after the JT12 FM output, especially for strong feedback
sounds such as OP1 feedback / FB7.
```

Current evidence:

```text
foobar/VGMRips:
  patch104 diagnostics are clean synth lead / clean rotating tone

MiSTer/JT12 current best:
  ch1_main_patch.vgm, fb7, and op1+op4 remain noisy
  ladder off reduces noise slightly but does not make the tone clean

Previously unlikely causes:
  final output attenuation / clipping
  LPF setting alone
  fm_adjust gain alone
  YM write timing
  CEN jitter alone
  LFO/PMS/AMS
  channel 3 special mode
  VGM loader/player/timing
```

Added macro:

```text
MD_AUDIO_FM_DC_BLOCK_TEST
```

Implementation:

```text
location:
  after JT12 snd_left/snd_right, including ladder effect
  before fm_adjust and jt12_genmix

first diagnostic equation:
  y[n] = (x[n] - x[n-1]) >>> 1

sample point:
  previous x is updated only on jt12_sample

reason:
  this is a deliberately simple DC-block / high-pass A/B. It may make the FM
  sound thinner or overemphasize transients; it is not intended as final audio
  tuning.
```

Current best QSF should remain:

```text
FIXED_REGION_MODE=5
MD_JT12_CEN_NTSC_TEST=1
MD_JT12_LADDER_EFFECT_TEST=1
```

For this A/B, add:

```text
MD_AUDIO_FM_DC_BLOCK_TEST=1
```

Expected marker:

```text
top 12 lines: yellow/green stripe
```

Hardware test files:

```text
ch1_main_patch.vgm
ch1_main_patch_fb7.vgm
ch1_main_patch_op1_plus_op4.vgm
fm_only_test.vgm
```

Interpretation:

```text
If noise / biting feedback becomes clean or greatly reduced:
  missing FM DC blocking / post-filtering is likely a major cause
  next try a proper one-pole DC blocker:
    y[n] = x[n] - x[n-1] + R*y[n-1]
    R near 0.995, or a power-of-two approximation

If the sound becomes thinner but noise remains:
  simple difference is too crude; test the one-pole version before returning
  to JT12 internals

If unchanged:
  return focus to JT12 feedback/model differences
```

No VGM loader, VGM timing, mode5 player, PCM/DAC handling, or JT12 write logic
was changed in this step.


## 2026-06-08: FM DC-Block Result and Direct Genesis_MiSTer JT12 Compare

Hardware result:

```text
MD_AUDIO_FM_DC_BLOCK_TEST:
  expected yellow/green marker appeared
  simple difference high-pass did not improve patch104/op1+op4 noise
  volume was lower
  noise increased
```

Conclusion:

```text
the simple y[n] = x[n] - x[n-1] high-pass/DC-block diagnostic is not the fix
do not add more broad filters for now
return QSF to current best config
```

Current best QSF restored:

```text
FIXED_REGION_MODE=5
MD_JT12_CEN_NTSC_TEST=1
MD_JT12_LADDER_EFFECT_TEST=1
```

The `MD_AUDIO_FM_DC_BLOCK_TEST` RTL macro remains available as a diagnostic, but
it is no longer enabled in `VGM_MD_MiSTer.qsf`.

Direct Genesis_MiSTer source comparison:

```text
Genesis_MiSTer source checked:
  https://github.com/MiSTer-devel/Genesis_MiSTer

fetched for comparison:
  files.qip
  rtl/jt12/jt12.qip
  rtl/jt12/*.v
  rtl/jt12/mixer/*.v
  Genesis.sv
  rtl/system.sv
```

JT12 file-set comparison:

```text
Genesis_MiSTer uses:
  rtl/jt12/jt12.qip

The local project uses the same JT12 Verilog file set under:
  rtl/genesis_audio/jt12
```

Important source equality result:

```text
jt12_op.v:
  identical to Genesis_MiSTer master

This is the file containing the operator feedback path:
  fb_II input
  pm_preshift_II <= xs + ys
  fb level shift table for fb=0..7
  phasemod_VIII 6-stage YM2612 delay

Therefore the current patch104 feedback noise is probably not caused by a local
edit to the core feedback operator implementation.
```

JT12 files that were byte-identical to Genesis_MiSTer master:

```text
jt12_top.v
jt12_op.v
jt12_mod.v
jt12_pg*.v
jt12_pm.v
jt12_lfo.v
jt12_logsin.v
jt12_div.v
jt12_csr.v
jt12_dout.v
jt12_rst.v
jt12_timers.v
jt12_sumch.v
most EG files
adpcm/jt10_adpcm_div.v
mixer/jt12_decim.v
```

JT12 files with local differences:

```text
jt12.v:
  local wrapper ties some otherwise unused ADPCM/IO/debug inputs to constants

jt12_acc.v:
  local version adds reset initialization for pcm_sum, rl_latch, rl_old,
  left, and right
  ladder equation itself matches Genesis_MiSTer:
    ladder high enables the ladder-effect term
    ladder low disables it

jt12_kon.v / jt12_mmr.v / jt12_reg.v:
  local differences are VERBOSE_TB_LOG debug instrumentation

jt12_single_acc.v:
  local differences initialize regs

jt12_pcm_interpol.v:
  local difference is declaration ordering / newline style

mixer/jt12_genmix.v / jt12_fm_uprate.v / jt12_comb.v / jt12_interpol.v:
  local differences are debug instrumentation and wrap counters
```

No Genesis_MiSTer special handling for feedback-heavy patches was found in
`system.sv`. Its FM path is:

```text
jt12
  -> fm_adjust = FM * 22.25
  -> optional genesis_fm_lpf when LPF_MODE == 2'b01
  -> jt12_genmix
  -> genesis_lpf
  -> DAC_LDATA / DAC_RDATA
```

Important integration difference still remaining:

```text
Genesis_MiSTer has a dedicated FM-only LPF before genmix:
  genesis_fm_lpf fm_lpf_l/r

It is selected only when:
  LPF_MODE == 2'b01

The current VGM-only project has been testing the final genesis_lpf path, but
does not currently insert Genesis_MiSTer's pre-genmix genesis_fm_lpf in the
normal FM path.
```

This is not the same as the failed simple DC-block test. `genesis_fm_lpf` is the
known Genesis_MiSTer FM post-processing stage for Model 2 mode, placed after
`fm_adjust` and before `jt12_genmix`.

Current interpretation:

```text
less likely now:
  local jt12_op feedback implementation drift
  local ladder equation drift
  missing simple DC blocking

still plausible:
  Genesis_MiSTer FM-only LPF integration difference
  JT12 drive/reset/init differences outside the byte-identical op core
  remaining clocking/sample-enable differences from running JT12 from 20 MHz
```

Verification after restoring QSF:

```text
tb_mister_vgm_md_top compile:
  FIXED_REGION_MODE=5
  MD_JT12_CEN_NTSC_TEST=1
  MD_JT12_LADDER_EFFECT_TEST=1
  result: PASS

tb_mister_vgm_md_top vvp:
  result: PASS
  audio_sample_valid_edges=5000
```


## 2026-06-08: Pre-Genmix Genesis FM LPF A/B

Current concrete difference after direct Genesis_MiSTer JT12 comparison:

```text
jt12_op.v feedback/operator core:
  matches Genesis_MiSTer master byte-for-byte

jt12_acc.v ladder expression:
  matches Genesis_MiSTer

simple FM DC-block/high-pass:
  did not improve patch104/op1+op4 noise

Genesis_MiSTer system.sv still has one relevant FM post-processing stage that
the VGM-only project did not have in the normal path:
  genesis_fm_lpf after fm_adjust and before jt12_genmix
```

Added macro:

```text
MD_AUDIO_PRE_GENMIX_FM_LPF_TEST
```

Implementation:

```text
default path:
  JT12 raw FM
    -> fm_adjust
    -> jt12_genmix

with MD_AUDIO_PRE_GENMIX_FM_LPF_TEST:
  JT12 raw FM
    -> fm_adjust
    -> genesis_fm_lpf
    -> jt12_genmix
```

The `genesis_fm_lpf` implementation is reused from the local
`rtl/genesis_audio/filters/genesis_lpf.v`, which matches the Genesis_MiSTer FM
post-filter module already imported into this project.

Current best QSF remains:

```text
FIXED_REGION_MODE=5
MD_JT12_CEN_NTSC_TEST=1
MD_JT12_LADDER_EFFECT_TEST=1
```

For this A/B, add:

```text
MD_AUDIO_PRE_GENMIX_FM_LPF_TEST=1
```

Expected marker:

```text
top 12 lines: purple/green stripe
```

Hardware test files:

```text
ch1_main_patch.vgm
ch1_main_patch_fb7.vgm
ch1_main_patch_op1_plus_op4.vgm
fm_only_test.vgm
```

Interpretation:

```text
If patch104 becomes closer to the foobar/VGMRips clean synth lead:
  the missing pre-genmix FM LPF was likely a major difference

If unchanged:
  continue comparing Genesis_MiSTer post-FM audio path and JT12 wrapper/clock
  integration details
```

No VGM loader, VGM timing, mode5 player, PCM/DAC handling, JT12 write logic, or
final output path was changed in this step.


## 2026-06-08: Pre-Genmix FM LPF Hardware Pass

`REGION_MODE=5 / OSD-loaded VGM` playback is working on real MiSTer hardware.
The remaining major audio issue was the patch104 / CH1 main melody / OP1
feedback noise.

Working QSF configuration:

```tcl
set_global_assignment -name VERILOG_MACRO "MISTER_FB=1"
set_global_assignment -name VERILOG_MACRO "FIXED_REGION_MODE=5"
set_global_assignment -name VERILOG_MACRO "MD_JT12_CEN_NTSC_TEST=1"
set_global_assignment -name VERILOG_MACRO "MD_JT12_LADDER_EFFECT_TEST=1"
set_global_assignment -name VERILOG_MACRO "MD_AUDIO_PRE_GENMIX_FM_LPF_TEST=1"
```

Confirmed hardware result:

```text
OSD Load VGM: works
fm_only_test.vgm: loads and plays full length
loop length: matches foobar/VGMRips, about 150 seconds
MiSTer menu return: OK
single_fm_sustain.vgm: clean

patch104 / CH1 main melody issue:
  isolated to the CH1 main patch / OP1 feedback-heavy material

without pre-genmix FM LPF:
  ch1_main_patch.vgm noisy
  ch1_main_patch_fb7.vgm noisy
  ch1_main_patch_op1_plus_op4.vgm noisy

with MD_AUDIO_PRE_GENMIX_FM_LPF_TEST=1:
  noise disappears
  patch becomes clean
  result is much closer to foobar/VGMRips
```

Important investigation history:

```text
fm_only_test.vgm is effectively FM-only:
  DAC data writes 0x2A: 0
  DAC enable 0x2B: one write, value 0x00
  PSG writes: 24
  YM port0 writes: 50488
  YM port1 writes: 3500
  unsupported commands: 0
```

The issue was not caused by:

```text
VGM loader
VGM wait timing
loop handling
PCM/DAC
PSG
final sys_top/audio_out clipping
simple output attenuation
post-output LPF alone
fm_adjust 22.25x gain alone
YM write spacing / handshake
LFO / PMS / AMS
CH3 special mode
simple DC-block / difference high-pass
```

JT12 source comparison result:

```text
jt12_op.v:
  matches Genesis_MiSTer master byte-for-byte

jt12_acc.v:
  ladder expression is effectively the same as Genesis_MiSTer
  local difference is reset initialization

Conclusion:
  noise was not due to a locally broken JT12 feedback/operator implementation
```

Key finding:

```text
Genesis_MiSTer has a pre-genmix genesis_fm_lpf between fm_adjust and
jt12_genmix. The self-made audio path was missing this stage.
```

Working path:

```text
JT12 raw FM
  -> fm_adjust
  -> genesis_fm_lpf
  -> jt12_genmix
  -> genesis_lpf / final audio path
```

Conclusion:

```text
The patch104 / OP1 feedback / FB7 noise was caused by missing
Genesis_MiSTer-style pre-genmix FM LPF in the self-made audio path.

JT12 itself was not locally broken.
```

Current best hardware audio configuration for Mega Drive / Genesis-style
YM2612 audio:

```text
1. NTSC Mega Drive style JT12 CEN
   MD_JT12_CEN_NTSC_TEST=1

2. YM2612 / ladder-style behavior
   MD_JT12_LADDER_EFFECT_TEST=1

3. Genesis_MiSTer-style pre-genmix FM LPF
   MD_AUDIO_PRE_GENMIX_FM_LPF_TEST=1
```

Next suggested cleanup:

```text
Promote the three successful test macros into named normal Mega Drive audio
configuration options.

Keep debug/test macros available, but avoid leaving the QSF in an experimental
state.

Potential renames:
  MD_JT12_CEN_NTSC_TEST
    -> normal MD FM CEN mode

  MD_JT12_LADDER_EFFECT_TEST
    -> normal YM2612 ladder mode

  MD_AUDIO_PRE_GENMIX_FM_LPF_TEST
    -> normal Genesis FM LPF path

Preserve the known-good mode3 and mode5 paths.
Do not change PCM/DAC yet.
```


## 2026-06-08: Post-FM-LPF Gain Staging Check

Hardware result after enabling the current best audio configuration:

```text
FIXED_REGION_MODE=5
MD_JT12_CEN_NTSC_TEST=1
MD_JT12_LADDER_EFFECT_TEST=1
MD_AUDIO_PRE_GENMIX_FM_LPF_TEST=1

patch104 noise: fixed
overall sound: much cleaner
remaining issue: output volume seems significantly lower than foobar/VGMRips
and normal MiSTer cores
```

QSF macro check:

```text
no leftover attenuation / mute / raw debug macros were found:
  MD_AUDIO_RAW_JT12_FM_TEST
  MD_AUDIO_SYSOUT_ATTENUATE_6DB
  MD_AUDIO_SYSOUT_ATTENUATE_24DB
  MD_AUDIO_FINAL_ATTENUATE_6DB
  MD_AUDIO_FM_ADJUST_BYPASS_TEST
  MD_AUDIO_FM_FORCE_MUTE_TEST
  MD_AUDIO_FM_DC_BLOCK_TEST
  MD_AUDIO_PREMIX_ATTENUATE_FM_6DB

active audio-related QSF macros:
  MD_JT12_CEN_NTSC_TEST=1
  MD_JT12_LADDER_EFFECT_TEST=1
  MD_AUDIO_PRE_GENMIX_FM_LPF_TEST=1
```

Current gain/scaling path:

```text
md_sound_module:
  fm_left/right:
    signed 16-bit from JT12 snd_left/snd_right

  fm_adjust_l/r:
    signed 16-bit result
    expression matches Genesis_MiSTer:
      (FM << 4) + (FM << 2) + (FM << 1) + (FM >>> 2)
    effective gain: 22.25x before 16-bit truncation/saturation A/B options

  genesis_fm_lpf output:
    signed 16-bit
    now inserted before jt12_genmix when MD_AUDIO_PRE_GENMIX_FM_LPF_TEST=1

  jt12_genmix input:
    fm_left/right signed 16-bit
    psg_snd signed 11-bit

  jt12_fm_uprate internal mix:
    local diagnostic version widens FM+PSG sum to 17-bit for wrap counting,
    then stores mixed as signed 16-bit, matching the original 16-bit output
    width behavior

  jt12_genmix output:
    signed 16-bit pre_lpf_l/r

  genesis_lpf final output:
    signed 16-bit lpf_audio_l/r

  md_sound_module audio_l/r:
    signed 16-bit
```

Top-level output scaling:

```text
emu.sv:
  md_audio_l/r from md_sound_module are shifted before AUDIO_L/R:
    default MD_AUDIO_OUTPUT_SHIFT = 2
    MD_AUDIO_FINAL_ATTENUATE_6DB would make it 3, but that macro is not active

  AUDIO_L/R:
    signed 16-bit after audio_gate_open

sys_top/audio_out:
  no sysout attenuation macro is active
  audio_out_core_l/r = audio_l/r
```

Genesis_MiSTer comparison:

```text
Genesis_MiSTer system.sv:
  JT12 raw FM
    -> fm_adjust
    -> optional genesis_fm_lpf when LPF_MODE == 2'b01
    -> jt12_genmix
    -> genesis_lpf
    -> DAC_LDATA / DAC_RDATA

No explicit gain compensation after genesis_fm_lpf was found in Genesis_MiSTer.
```

Interpretation:

```text
genesis_fm_lpf can reduce perceived level because it is a real FM-only
low-pass stage before genmix.

This project also has an existing emu-level safety shift:
  md_audio_l/r >>> 2

That shift predates the pre-genmix FM LPF and remains a likely contributor to
lower-than-core volume, but it was not changed in this step.
```

Added A/B macro:

```text
MD_AUDIO_POST_FM_LPF_GAIN_TEST
```

Implementation:

```text
Only affects the pre-genmix FM LPF path:

  JT12 raw FM
    -> fm_adjust
    -> genesis_fm_lpf
    -> signed saturating x2 gain
    -> jt12_genmix

If MD_AUDIO_PRE_GENMIX_FM_LPF_TEST is not active, this macro has no audible
effect on the FM path.
```

Saturation behavior:

```text
wide calculation:
  signed 17-bit = signed 16-bit LPF output <<< 1

clamp:
  >  32767 ->  32767
  < -32768 -> -32768
```

Expected marker:

```text
top 12 lines: white/purple stripe
```

Hardware A/B suggestion:

```text
baseline:
  FIXED_REGION_MODE=5
  MD_JT12_CEN_NTSC_TEST=1
  MD_JT12_LADDER_EFFECT_TEST=1
  MD_AUDIO_PRE_GENMIX_FM_LPF_TEST=1

gain A/B:
  add MD_AUDIO_POST_FM_LPF_GAIN_TEST=1

Listen for:
  overall level increase
  whether patch104 remains clean
  whether fm_only_test.vgm clips or becomes harsh again
```

Do not change VGM timing, loader, PCM/DAC, CEN, ladder, mode5 player, or JT12
write logic for this gain A/B.


## 2026-06-08: Final Output Shift A/B

Hardware result:

```text
MD_AUDIO_POST_FM_LPF_GAIN_TEST:
  x2 saturating gain after genesis_fm_lpf did not noticeably increase overall
  volume

Conclusion:
  the main low-volume issue is probably not solved at the FM pre-genmix stage
```

Current remaining gain suspect:

```text
emu.sv:
  md_audio_l/r >>> MD_AUDIO_OUTPUT_SHIFT

default:
  MD_AUDIO_OUTPUT_SHIFT = 2

This divides final core audio by 4 before sys_top/audio_out. The observed volume
is roughly 1/4 of Genesis_MiSTer, which matches this scaling.
```

QSF restored to current best FM path:

```text
FIXED_REGION_MODE=5
MD_JT12_CEN_NTSC_TEST=1
MD_JT12_LADDER_EFFECT_TEST=1
MD_AUDIO_PRE_GENMIX_FM_LPF_TEST=1
```

The failed `MD_AUDIO_POST_FM_LPF_GAIN_TEST` A/B is no longer part of the current
best QSF.

Added final output shift A/B macros:

```text
MD_AUDIO_OUTPUT_SHIFT_1_TEST
  sets MD_AUDIO_OUTPUT_SHIFT = 1
  final output scale changes from /4 to /2
  marker: cyan/white top stripe

MD_AUDIO_OUTPUT_SHIFT_0_TEST
  sets MD_AUDIO_OUTPUT_SHIFT = 0
  final output scale changes from /4 to unity
  marker: red/green top stripe
```

Priority:

```text
MD_AUDIO_OUTPUT_SHIFT_0_TEST
MD_AUDIO_OUTPUT_SHIFT_1_TEST
MD_AUDIO_FINAL_ATTENUATE_6DB
default shift 2
```

Existing rail/clip counters remain available:

```text
md_audio_l_rail_count
md_audio_r_rail_count
fm_adjust_clip_count_l
fm_adjust_clip_count_r
genmix_wrap_count_l
genmix_wrap_count_r
```

Hardware test order:

```text
1. Test SHIFT=1 first:
   add MD_AUDIO_OUTPUT_SHIFT_1_TEST=1

2. If still quiet and no clipping/harshness:
   remove SHIFT=1
   add MD_AUDIO_OUTPUT_SHIFT_0_TEST=1

3. Compare volume to Genesis_MiSTer Super Hang-On on the same TV.

4. Confirm:
   patch104 noise remains fixed
   fm_only_test.vgm remains clean
   no clipping or harshness returns
   MiSTer menu return remains OK
```

Do not change VGM timing, loader, mode5 player, PCM/DAC, JT12 CEN, ladder, or
pre-genmix FM LPF for this A/B.


## 2026-06-08: sys_top/audio_out Gain A/B

Hardware result:

```text
MD_AUDIO_OUTPUT_SHIFT_1_TEST:
  cyan/white top stripe visible
  sound quality remains good
  overall HDMI volume does not noticeably change
```

Conclusion:

```text
emu.sv MD_AUDIO_OUTPUT_SHIFT does not appear to be the effective final gain
control for the audible HDMI path.

Previous sys_top/audio_out-side tests did affect HDMI:
  MD_AUDIO_FORCE_MUTE_TEST muted HDMI completely
  MD_AUDIO_SYSOUT_ATTENUATE_24DB made HDMI much quieter

Therefore the next gain A/B should be applied at the sys_top/audio_out input
side, at the same point where force-mute and sysout attenuation worked.
```

Current best QSF remains:

```text
FIXED_REGION_MODE=5
MD_JT12_CEN_NTSC_TEST=1
MD_JT12_LADDER_EFFECT_TEST=1
MD_AUDIO_PRE_GENMIX_FM_LPF_TEST=1
```

The `MD_AUDIO_OUTPUT_SHIFT_1_TEST` macro was removed from QSF after this
hardware result.

Added sys_top/audio_out-side gain A/B macros:

```text
MD_AUDIO_SYSOUT_GAIN_2X_SAT_TEST
  applies signed saturating x2 gain to audio_out core_l/core_r inputs
  marker: green/white top stripe

MD_AUDIO_SYSOUT_GAIN_4X_SAT_TEST
  applies signed saturating x4 gain to audio_out core_l/core_r inputs
  marker: orange/blue top stripe
```

Implementation point:

```text
sys/sys_top.v:
  audio_l/r
    -> optional MD_AUDIO_FORCE_MUTE_TEST
    -> optional MD_AUDIO_SYSOUT_ATTENUATE_24DB / 6DB
    -> optional MD_AUDIO_SYSOUT_GAIN_4X_SAT_TEST
    -> optional MD_AUDIO_SYSOUT_GAIN_2X_SAT_TEST
    -> audio_out.core_l/core_r

ALSA audio_out inputs use the same gain/mute/attenuation selection when ALSA
is enabled.
```

Saturation behavior:

```text
wide signed calculation:
  x2: sign-extended 18-bit sample <<< 1
  x4: sign-extended 18-bit sample <<< 2

clamp:
  >  32767 ->  32767
  < -32768 -> -32768

No wrapping gain is used.
```

Priority:

```text
MD_AUDIO_FORCE_MUTE_TEST
MD_AUDIO_SYSOUT_ATTENUATE_24DB
MD_AUDIO_SYSOUT_ATTENUATE_6DB
MD_AUDIO_SYSOUT_GAIN_4X_SAT_TEST
MD_AUDIO_SYSOUT_GAIN_2X_SAT_TEST
default passthrough
```

Hardware test order:

```text
1. Test 2x first:
   add MD_AUDIO_SYSOUT_GAIN_2X_SAT_TEST=1

2. If still too quiet and patch104 remains clean:
   remove 2x
   add MD_AUDIO_SYSOUT_GAIN_4X_SAT_TEST=1

3. Compare volume to Genesis_MiSTer Super Hang-On on the same TV.

4. Confirm:
   ch1_main_patch.vgm remains clean
   fm_only_test.vgm remains clean
   snare / hi-hat harshness does not return
   no obvious clipping or pumping appears
   MiSTer menu return remains OK
```

Do not change VGM timing, loader, mode5 player, PCM/DAC, JT12 CEN, ladder,
pre-genmix FM LPF, fm_adjust, or jt12_genmix for this A/B.


## 2026-06-08: Raw JT12 FM Still Distorted, JT12 Clock/CEN A/B Added

Hardware A/B result:

```text
build macro:
  MD_AUDIO_RAW_JT12_FM_TEST

screen:
  blue/white top stripe visible

audio:
  much quieter, as expected because fm_adjust/genmix/PSG/LPF are bypassed
  snare distortion / harsh character remains essentially unchanged
```

Conclusion:

```text
distortion is already present in raw JT12 FM output
not caused by fm_adjust
not caused by jt12_genmix
not caused by PSG mixing
not caused by genesis_lpf
not caused by final sys_top/audio_out scaling
```

JT12 integration inspection:

```text
actual clk_sys:
  rtl/pll/pll_0002.v outputs 20.000000 MHz

current md_sound_module default FM enable:
  fm_clken = clk / 7
  at 20 MHz this is about 2.857 MHz

Genesis_MiSTer-style assumption in md_sound_module comments:
  master clock about 53.693 MHz
  FM_CLKEN about MCLK / 7 = about 7.670 MHz

jt12 wrapper:
  rst must be held for at least 6 clk&cen cycles
  current reset stretcher holds jt12_reset for 8 fm_clken pulses

jt12_top:
  exposes signed 16-bit fm_snd_left/right
  jt12.v wrapper currently leaves separated fm_snd_left/right unconnected
  snd_left/right are connected to md_sound_module fm_left/right
  with use_ssg=0, snd_left/right are assigned directly from fm_snd_left/right

mode/config:
  jt12.v default parameters select YM2612-style use_pcm=1, use_ssg=0
  en_hifi_pcm is tied low
  ladder was tied low before this A/B step
```

Important note:

```text
The project now has correct VGM wait timing at CLK_SYS_HZ=20 MHz, but that does
not automatically make JT12's FM core clocking equivalent to the Mega Drive
integration. The VGM sequencer timing and the YM core execution clock are now
separate suspects.
```

Added hardware A/B macros:

```text
MD_JT12_CEN_NTSC_TEST
  Uses a fractional accumulator to approximate 53.693175 MHz / 7 from the
  current 20 MHz clk_sys.
  Target enable rate: about 7.670454 MHz.
  Current accumulator increment: 6434443 / 2^24 per 20 MHz clock.
  Marker: green/white top stripe.

MD_JT12_CEN_EVERY_CLK_TEST
  Drives jt12 cen every clk_sys cycle as an extreme clocking A/B.
  Marker: red/white top stripe.

MD_AUDIO_RAW_JT12_SAMPLE_LATCH_TEST
  Routes raw JT12 FM output, but updates the routed sample only on jt12_sample.
  This checks whether raw fm_left/right should be consumed only on JT12's own
  sample pulse.
  Marker: blue/yellow top stripe.

MD_JT12_LADDER_EFFECT_TEST
  Drives jt12 ladder input high for YM2612 ladder-effect A/B.
  Marker: magenta/cyan top stripe.
```

Current QSF test build selection:

```text
FIXED_REGION_MODE=5
MD_AUDIO_RAW_JT12_FM_TEST=1
MD_JT12_CEN_NTSC_TEST=1
```

Expected hardware marker for the current build:

```text
green/white top stripe
```

Exact MiSTer hardware test steps:

```text
1. Build the current QSF.
2. Confirm the top stripe is green/white.
3. Open OSD and Load VGM.
4. Load fm_only_test.vgm.
5. Confirm mode5 still starts and loops.
6. Compare against the previous raw JT12 FM build:
   - pitch / tempo of FM tone material
   - snare distortion
   - hi-hat harshness
   - overall character
7. Menu return must remain OK.
```

Interpretation:

```text
If MD_JT12_CEN_NTSC_TEST changes pitch/timbre or improves the harsh snare,
focus next on making the JT12/FM clock-enable relationship match the known-good
Genesis integration without disturbing VGM wait timing.

If it does not change the harsh character, test MD_AUDIO_RAW_JT12_SAMPLE_LATCH_TEST
next to see whether output consumption needs to be synchronized to jt12_sample.

If both are unchanged, test MD_JT12_LADDER_EFFECT_TEST only as a mode/character
comparison; it is not expected to fix harshness if the current low-ladder path
is already the cleaner YM3438-like path.
```


## 2026-06-08: Mode 5 Hardware Pass and JT12 CEN/Ladder Improvement

Real-hardware status for `REGION_MODE=5 / OSD-loaded VGM` is now a pass for the
non-PCM loaded-VGM playback path.

Confirmed on MiSTer hardware:

```text
OSD Load VGM: works
216 KB fm_only_test.vgm: loads successfully
64 KiB boundary: crossed successfully
full-length playback: works
loop duration: matches foobar2000, about 150 seconds
MiSTer menu return: OK

VGM timing: working
loop behavior: working
loader: working
256 KiB loaded RAM path: working
```

Important fixes and corrected interpretations:

```text
1. The earlier 7-8 second restart was caused by the top-level watchdog timeout,
   not by VGM wait speed.

2. The later 150s -> 90s speed issue was caused by a CLK_SYS_HZ mismatch:
     actual PLL clk_sys: 20 MHz
     old CLK_SYS_HZ:     12.5 MHz
     fixed CLK_SYS_HZ:   20 MHz

   Changing CLK_SYS_HZ to 20 MHz fixed the dedicated VGM wait timing on real
   hardware.
```

Audio distortion investigation summary:

```text
The snare distortion / harsh hi-hat issue was not caused by:

  final sys_top/audio_out clipping
  LPF setting alone
  fm_adjust 22.25x gain alone
  PSG
  YM DAC / PCM
  YM write spacing / handshake
  VGM loader
  mode 5 player
```

Mac-side analysis of `fm_only_test.vgm`:

```text
dac_2a writes:        0
dac_2b writes:        1, value 0x00
PSG writes:           24
YM port0 writes:      50488
YM port1 writes:      3500
unsupported commands: 0
```

Conclusion from the file analysis:

```text
fm_only_test.vgm is effectively FM-only
the observed distortion is not a DAC/PCM playback issue
PSG contribution is negligible for this test material
```

Hardware A/B conclusions:

```text
FM force mute:
  fm_only_test.vgm becomes silent
  confirms the real FM contribution path

Raw JT12 FM output:
  much quieter because fm_adjust/genmix/PSG/LPF are bypassed
  same snare/hi-hat harshness remains
  points upstream to JT12 drive conditions rather than downstream mix

YM write slow test:
  marker appears
  snare/hi-hat character unchanged
  write spacing / handshake is unlikely to be the primary cause
```

Decisive hardware improvement:

```text
MD_JT12_CEN_NTSC_TEST=1
MD_JT12_LADDER_EFFECT_TEST=1

Result:
  drums sound much better
  most instruments sound much better
  previous snare / hi-hat problem is mostly resolved
```

Current best hardware test configuration:

```text
FIXED_REGION_MODE=5
MD_JT12_CEN_NTSC_TEST=1
MD_JT12_LADDER_EFFECT_TEST=1
```

Current remaining issue:

```text
one or more tones still seem to have unwanted vibrato / pitch wobble
drums and most other parts sound good
```

Likely next suspects:

```text
fractional JT12 CEN jitter from deriving the Mega Drive-ish FM enable from
  the current 20 MHz clk_sys

JT12 output sample latch timing

YM2612 / YM3438 mode details

remaining Genesis_MiSTer integration differences
```

Next investigation direction:

```text
Keep the working mode 5 loader/player/timing path unchanged.
Do not tune final mix yet.
Do not implement PCM yet.

Focus next on making JT12's clock-enable and mode wiring closer to the known
Genesis_MiSTer integration, and specifically test whether a less jittery JT12
CEN source or sample-latched output reduces the remaining pitch wobble.
```

No RTL was changed for this note. This records the hardware pass and audio
investigation result only.


## 2026-06-08: JT12 Fractional CEN Jitter Investigation

Current hardware result:

```text
FIXED_REGION_MODE=5
MD_JT12_CEN_NTSC_TEST=1
MD_JT12_LADDER_EFFECT_TEST=1

drums: good
most instruments: good
tempo / loop length: correct

remaining issue:
  one or more sustained tones seem to have unwanted vibrato / pitch wobble
  drums and bass do not obviously wobble
```

Hypothesis:

```text
The fractional JT12 CEN generated from the current 20 MHz clk_sys has the
correct average rate, but its per-enable spacing alternates between uneven
2-clk and 3-clk intervals. This enable jitter may be audible on sustained FM
tones even when drums and bass sound acceptable.
```

Current fractional CEN parameters:

```text
clk_sys:
  20,000,000 Hz

target Mega Drive-ish JT12 CEN:
  53.693175 MHz / 7 = about 7.670454 MHz

accumulator width:
  24 bits

increment:
  6,434,443

denominator:
  2^24 = 16,777,216

average CEN rate:
  20,000,000 * 6,434,443 / 16,777,216
  = 7,670,453.786849976 Hz

average interval:
  20,000,000 / 7,670,453.786849976
  = 2.607407665 clk_sys cycles
```

Observed interval pattern from the accumulator:

```text
first CEN pulse positions in clk_sys cycles:
  3, 6, 8, 11, 14, 16, 19, 21, 24, 27,
  29, 32, 34, 37, 40, 42, 45, 47, 50, 53,
  ...

intervals:
  3, 2, 3, 3, 2, 3, 2, 3, 3, 2,
  3, 2, 3, 3, 2, 3, 2, 3, 3, 2,
  ...

min interval:
  2 clk_sys cycles

max interval:
  3 clk_sys cycles

short-window distribution example:
  2-clk intervals: 29
  3-clk intervals: 46
```

Periodicity:

```text
gcd(6,434,443, 16,777,216) = 1

full accumulator state period:
  16,777,216 clk_sys cycles
  about 0.838861 seconds at 20 MHz

pulses per full pattern:
  6,434,443

This is not a small repeating divider pattern. It is a long Bresenham-style
fractional pattern with only 2-clk and 3-clk intervals.
```

JT12 cadence expectation:

```text
JT12 accepts a clk plus cen. The local jt12_top/jt12_div code is written around
a regular chip clock/enable relationship. It can function with a cen, but a
high-jitter fractional cen is not equivalent to running the core from a true
uniform Mega Drive master clock or from a clean divided enable.
```

Comparison with Genesis_MiSTer:

```text
Genesis_MiSTer uses a PLL-derived Genesis system clock path and passes MCLK into
the system module. The FM chip option also drives the LADDER input from the OSD
FM Chip selection.

Relevant observed wiring from Genesis_MiSTer Genesis.sv:
  system system (
    .MCLK(clk_sys),
    ...
    .LADDER(~status[11]),
    .LPF_MODE(status[15:14]),
    ...
  )

This differs from the current VGM-only project, where clk_sys is the MiSTer
shell's 20 MHz PLL output and MD_JT12_CEN_NTSC_TEST synthesizes a Mega
Drive-ish JT12 enable by fractional accumulation.
```

Engineering interpretation:

```text
For a permanent fix, a separate PLL clock or a higher clk_sys would likely be
better than generating a 7.67 MHz enable from only 20 MHz.

Examples:
  a true Genesis-like master clock lets the JT12 enable be a uniform /7 style
  relationship.

  a much higher clk_sys reduces the absolute time size of fractional jitter.

  a diagnostic uniform divider from 20 MHz removes jitter, but necessarily
  changes the FM chip rate and therefore pitch.
```

Added hardware A/B macros:

```text
MD_AUDIO_NORMAL_SAMPLE_LATCH_TEST
  Applies sample-latch behavior on the normal audio path, after genmix/LPF.
  This is separate from MD_AUDIO_RAW_JT12_SAMPLE_LATCH_TEST, which only affects
  the raw JT12 debug output path.
  Marker: blue/green top stripe.

MD_JT12_CEN_UNIFORM_10MHZ_TEST
  Generates a uniform CEN every 2 clk_sys cycles.
  Rate: 10 MHz.
  Pitch is expected to be too high compared with the target 7.67 MHz.
  Purpose: see whether removing CEN jitter changes the sustained-tone wobble.
  Marker: yellow/blue top stripe.

MD_JT12_CEN_UNIFORM_6P67MHZ_TEST
  Generates a uniform CEN every 3 clk_sys cycles.
  Rate: about 6.666667 MHz.
  Pitch is expected to be too low compared with the target 7.67 MHz.
  Purpose: see whether removing CEN jitter changes the sustained-tone wobble.
  Marker: amber/green top stripe.
```

Added CEN interval debug:

```text
jt12_cen_interval_1_count
jt12_cen_interval_2_count
jt12_cen_interval_3_count
jt12_cen_interval_4_count
jt12_cen_interval_ge5_count
jt12_cen_interval_min
jt12_cen_interval_max
jt12_cen_interval_last
```

The interval counters are exposed through `md_sound_module`,
`mister_vgm_md_top`, and `emu.sv` unused-input retention so they can be probed
in hardware if needed.

Current QSF baseline after this step:

```text
FIXED_REGION_MODE=5
MD_JT12_CEN_NTSC_TEST=1
MD_JT12_LADDER_EFFECT_TEST=1
```

Suggested hardware A/B sequence:

```text
Baseline:
  FIXED_REGION_MODE=5
  MD_JT12_CEN_NTSC_TEST=1
  MD_JT12_LADDER_EFFECT_TEST=1

A/B 1, normal-path sample latch:
  add MD_AUDIO_NORMAL_SAMPLE_LATCH_TEST=1
  keep MD_JT12_CEN_NTSC_TEST=1
  keep MD_JT12_LADDER_EFFECT_TEST=1
  listen for sustained-tone wobble change

A/B 2, uniform 10 MHz CEN:
  replace MD_JT12_CEN_NTSC_TEST with MD_JT12_CEN_UNIFORM_10MHZ_TEST=1
  keep MD_JT12_LADDER_EFFECT_TEST=1
  expect pitch to be high
  listen only for wobble character change

A/B 3, uniform 6.67 MHz CEN:
  replace MD_JT12_CEN_NTSC_TEST with MD_JT12_CEN_UNIFORM_6P67MHZ_TEST=1
  keep MD_JT12_LADDER_EFFECT_TEST=1
  expect pitch to be low
  listen only for wobble character change
```

Do not use the uniform-divider tests as final sound tuning. They are only to
separate "wrong average FM clock" from "fractional CEN jitter".

Compile checks:

```text
tb_mister_vgm_md_top compile with:
  MD_JT12_CEN_NTSC_TEST=1
  MD_JT12_LADDER_EFFECT_TEST=1

result:
  passed

tb_mister_vgm_md_top compile with:
  MD_AUDIO_NORMAL_SAMPLE_LATCH_TEST=1
  MD_JT12_CEN_UNIFORM_10MHZ_TEST=1

result:
  passed

tb_md_sound_module compile with:
  MD_JT12_CEN_NTSC_TEST=1
  MD_JT12_LADDER_EFFECT_TEST=1

result:
  passed

warnings:
  existing jt12_comb mem[-1] warnings
  existing Icarus unique-case ignored warnings
```

No VGM timing, loader, PCM, or final mix behavior was changed in this step.


## 2026-06-08: Uniform CEN A/B and YM LFO/CH3 Register Analysis

Hardware result:

```text
MD_JT12_CEN_UNIFORM_10MHZ_TEST:
  pitch changes as expected
  sustained-note buzzing / "re-re-re" artifact remains

Conclusion:
  fractional CEN jitter is probably not the main cause
```

Current best hardware configuration remains:

```text
FIXED_REGION_MODE=5
MD_JT12_CEN_NTSC_TEST=1
MD_JT12_LADDER_EFFECT_TEST=1
```

Remaining issue:

```text
sustained FM notes should sound continuous
some sustained notes sound finely chopped / buzzing / vibrato-like
pitch is mostly correct
drums and short attacks sound mostly OK
overall FM is improved but still somewhat noisy/rough
```

`fm_only_test.vgm` register analysis:

```text
file: out/fm_only_test.vgm
file size: 0x3601e bytes, 221214 decimal
data_start: 0x40
first 0x66 end command: pc=0x35f39
wait total before end: 6608179 samples
duration: 149.845 seconds
unsupported commands: none
```

YM LFO register `0x22`:

```text
port 0 reg 0x22 writes: 1
  pc=0x52 data=0x00

port 1 reg 0x22 writes: 0

Interpretation:
  VGM explicitly disables YM LFO at startup
  the sustained-tone artifact is not explained by intentional global YM LFO
```

PMS/AMS/pan registers `0xB4-0xB6`:

```text
reg 0xB4 total writes: 19
  all values: 0xC0

reg 0xB5 total writes: 18
  all values: 0xC0

reg 0xB6 total writes: 274
  values: 0xC0 for 273 writes, 0x00 for 1 write

decoded 0xC0:
  pan: left+right
  AMS: 0
  PMS: 0

nonzero AMS/PMS writes across 0xB4-0xB6:
  0

Interpretation:
  the file is not intentionally using PMS/AMS vibrato/tremolo
```

Timer / mode register `0x27`:

```text
reg 0x24 timer A high: 0 writes
reg 0x25 timer A low:  0 writes
reg 0x26 timer B:      0 writes
reg 0x27 mode/timer:   1 write
  pc=0x55 data=0x40
```

Interpretation:

```text
timer values are not programmed
CSM/timer playback is not the apparent source
0x27=0x40 enables the channel 3 special-frequency mode bit path
```

Channel 3 special-frequency registers:

```text
0xA8 writes: 1887
0xA9 writes: 1887
0xAA writes: 1887
0xAC writes: 1887
0xAD writes: 1887
0xAE writes: 1887
```

Interpretation:

```text
channel 3 special mode is heavily used
the affected sustained-tone artifact is more plausibly related to channel 3
special-frequency behavior, operator frequency update timing, or JT12 handling
of that mode than to LFO/PMS/AMS
```

JT12 mode/config comparison:

```text
current VGM project:
  jt12 default parameters select YM2612-style use_pcm=1, use_ssg=0
  en_hifi_pcm is tied low
  ladder is controlled by MD_JT12_LADDER_EFFECT_TEST
  LPF defaults to bypass unless an LPF A/B macro is enabled
  no compile-time NOLFO macro is used

Genesis_MiSTer:
  system receives MCLK(clk_sys)
  FM Chip OSD option drives LADDER(~status[11])
  LPF_MODE is also driven from OSD status
  Genesis_MiSTer exposes YM2612/YM3438-style FM chip choice
```

Added incorrect diagnostic macros:

```text
MD_YM_FORCE_LFO_OFF_TEST
  forces accepted YM write port0/reg0x22 data to 0x00
  marker: black/yellow top stripe
  expected effect for fm_only_test.vgm: probably no change, because the file
  already writes 0x22=0x00

MD_YM_MASK_PMS_AMS_TEST
  masks data for regs 0xB4-0xB6 to keep only pan bits: data & 0xC0
  marker: cyan/yellow top stripe
  expected effect for fm_only_test.vgm: probably no change, because AMS/PMS
  are already zero

MD_YM_CH3_NORMAL_TEST
  masks port0/reg0x27 with data & 0x3F, clearing the upper mode bits
  marker: red/blue top stripe
  this is intentionally incorrect for files using channel 3 special mode
  purpose: test whether the buzzing/chopped sustained tones are tied to
  channel 3 special-frequency handling
```

Suggested hardware A/B sequence:

```text
Baseline:
  FIXED_REGION_MODE=5
  MD_JT12_CEN_NTSC_TEST=1
  MD_JT12_LADDER_EFFECT_TEST=1

A/B 1:
  add MD_YM_FORCE_LFO_OFF_TEST=1
  expected: little/no change

A/B 2:
  add MD_YM_MASK_PMS_AMS_TEST=1
  expected: little/no change

A/B 3:
  add MD_YM_CH3_NORMAL_TEST=1
  expected: pitch/timbre may become wrong
  listen specifically for whether the chopped/buzzing sustained artifact
  disappears or changes character
```

Compile check:

```text
tb_mister_vgm_md_top compile with:
  MD_JT12_CEN_NTSC_TEST=1
  MD_JT12_LADDER_EFFECT_TEST=1
  MD_YM_FORCE_LFO_OFF_TEST=1
  MD_YM_MASK_PMS_AMS_TEST=1
  MD_YM_CH3_NORMAL_TEST=1

result:
  passed

warnings:
  existing jt12_comb mem[-1] warnings
  existing Icarus unique-case ignored warnings
```

No loader, VGM wait timing, mode 5 player, PCM/DAC, final mixer, or fm_adjust
behavior was changed in this step.


## 2026-06-08: CH3 Normal A/B No Change and Single-Tone Diagnostic VGM

Hardware result:

```text
MD_YM_CH3_NORMAL_TEST=1:
  expected blue/red stripe appears
  sustained-note buzzing / noisy character is unchanged
```

Conclusion:

```text
The remaining sustained-note buzzing is unlikely to be caused by:

  LFO / PMS / AMS
  channel 3 special mode
  fractional CEN jitter alone
  output sample latch timing
  fm_adjust
  LPF
  sys_top/audio_out clipping
  YM write spacing
```

Current best known hardware configuration remains:

```text
FIXED_REGION_MODE=5
MD_JT12_CEN_NTSC_TEST=1
MD_JT12_LADDER_EFFECT_TEST=1
```

QSF has been returned to that best-known baseline. The diagnostic
`MD_YM_CH3_NORMAL_TEST` macro is not enabled in the current QSF.

Direct JT12 / Genesis_MiSTer comparison:

```text
This project:
  clk_sys is 20 MHz from rtl/pll/pll_0002.v
  MD_JT12_CEN_NTSC_TEST creates an approximate 7.670454 MHz JT12 cen
  jt12.v default parameters are used:
    use_lfo = 1
    use_ssg = 0
    num_ch  = 6
    use_pcm = 1
  en_hifi_pcm is tied low
  ladder is high when MD_JT12_LADDER_EFFECT_TEST=1
  jt12.snd_left/right are used
  with use_ssg=0, jt12_top assigns snd_left/right directly from fm_snd_left/right
  external PSG is mixed later through jt12_genmix
  genesis_lpf is present but currently bypassed unless an LPF A/B macro is used

Genesis_MiSTer:
  system receives MCLK(clk_sys)
  FM chip OSD option is "YM2612,YM3438"
  LADDER is wired as ~status[11]
  EN_HIFI_PCM is wired from status[23]
  LPF_MODE is wired from status[15:14]
  AUDIO_L/R are driven from system DAC_LDATA/DAC_RDATA
```

Interpretation:

```text
The biggest remaining integration differences are no longer the final mixer or
VGM player. They are more likely:

  exact clock tree / MCLK relationship
  JT12 wrapper version or surrounding system integration
  hifi PCM / ladder / LPF option defaults
  any Genesis_MiSTer-specific FM post-processing before DAC_LDATA/DAC_RDATA
```

Simple diagnostic VGM prepared:

```text
file:
  out/single_fm_sustain.vgm

size:
  203 bytes

header:
  uncompressed VGM
  version 1.50
  data_start 0x40
  YM2612 clock 7,670,454 Hz
  total samples 485100, about 11 seconds

content:
  one sustained FM tone on YM channel 1
  LFO disabled
  normal channel mode
  DAC disabled
  no PMS/AMS
  no channel 3 special mode
  no PSG
  no PCM/DAC stream
  no data blocks

tone duration:
  10 seconds sustained
  1 second key-off/silence
```

`vgm_inspector` summary:

```text
YM2612 port0 writes: 38
YM2612 port1 writes: 0
SN76489 writes: 0
WAIT commands: 8
WAIT total samples: 485100
Data blocks: 0
PCM seeks: 0
YM2612 DAC stream commands: 0
Unsupported commands: none
END reached: yes

reg 0x22 LFO writes: 1
reg 0x28 KeyOn writes: 3
reg 0x30-0x9E operator parameter writes: 28
reg 0xB4-0xB6 pan/AMS/FMS writes: 1
```

Manual register sanity check:

```text
reg 0x22:
  0x00

reg 0x27:
  0x00

reg 0xB4-0xB6:
  only 0xB4=0xC0
  AMS=0
  PMS=0

channel 3 special registers:
  no 0xA8/0xA9/0xAA/0xAC/0xAD/0xAE writes
```

Hardware test purpose:

```text
If out/single_fm_sustain.vgm buzzes or sounds chopped:
  the artifact is likely intrinsic to the current JT12 drive/config/integration
  rather than fm_only_test.vgm's complex patches.

If out/single_fm_sustain.vgm sounds clean:
  the artifact is likely triggered by fm_only_test.vgm's patch data, dense
  frequency updates, or some more specific YM register interaction.
```

No loader, VGM wait timing, mode 5 player, PCM/DAC, final mixer, or fm_adjust
behavior was changed in this step.


## 2026-06-08: Mode 5 Per-File Sound-Core Reset

Hardware observation:

```text
Current best configuration:
  FIXED_REGION_MODE=5
  MD_JT12_CEN_NTSC_TEST=1
  MD_JT12_LADDER_EFFECT_TEST=1

out/single_fm_sustain.vgm by itself:
  simple sustained FM tone sounds clean

fm_only_test.vgm loaded/played first, then out/single_fm_sustain.vgm loaded:
  sustain test appears to inherit/drag previous fm_only sound/timbre/state
```

Conclusion:

```text
Mode 5 playback was not fully resetting the sound chip state between OSD-loaded
VGM files. The next file could start while JT12/YM2612 and PSG state from the
previous file was still present.
```

Implementation change:

```text
REGION_MODE=0..4:
  unchanged

REGION_MODE=5:
  loader still captures OSD/HPS bytes into the same 256 KiB BRAM path
  vgm_loaded_player command parsing is unchanged
  VGM wait timing is unchanged
  CEN_NTSC and ladder test behavior is unchanged

new load sequence:
  load_done_pulse
    -> hold md_sound_module in reset for MODE5_SOUND_RESET_CYCLES
    -> keep vgm_loaded_player reset during that sound reset
    -> issue one gated mode5 player start pulse

load/error behavior:
  while a new file is downloading, mode5 player and sound core are reset
  if load_error or overflow_error is latched, mode5 sound core remains reset/silent
```

Rationale:

```text
md_sound_module reset clears the local YM command adapter state and drives the
existing JT12 reset stretcher. JT89 is also reset through the same module reset.
This should clear stale YM register/key-on/DAC/LFO/timer/channel-mode state and
PSG latch/volume state before the newly loaded file starts.
```

New debug/status:

```text
mode5_sound_reset_active:
  high during the post-load sound reset window

mode5_player_start_pulse_debug:
  one-cycle pulse when mode5 starts the loaded player after reset

emu.sv debug color:
  yellow during mode5 post-load sound reset
  white on the mode5 gated player-start pulse
```

Test added:

```text
tb/tb_mode5_sound_reset_sequence.sv

test behavior:
  load a minimal VGM through the mode5 ioctl path
  confirm mode5_sound_reset_active asserts
  confirm player start is not issued while sound reset is active
  confirm a gated player start pulse is issued after reset
  repeat the load a second time to cover per-file reinitialization
```

Simulation result:

```text
PASS tb_mode5_sound_reset_sequence
```

Hardware test steps:

```text
Build with:
  FIXED_REGION_MODE=5
  MD_JT12_CEN_NTSC_TEST=1
  MD_JT12_LADDER_EFFECT_TEST=1

1. Boot the RBF on MiSTer.
2. OSD Load VGM: out/single_fm_sustain.vgm.
3. Confirm the simple sustained FM tone is clean by itself.
4. OSD Load VGM: fm_only_test.vgm.
5. Let it play long enough to establish the previous FM timbre/state.
6. OSD Load VGM: out/single_fm_sustain.vgm again.
7. Expected: the sustain tone starts from a freshly reset sound core and no
   longer drags the previous fm_only_test.vgm timbre/state.
8. Confirm OSD menu return remains OK.
```


## 2026-06-08: FM Channel Solo Diagnostic Macros

Clarification after the per-file reset work:

```text
The per-file sound reset issue is real when loading multiple VGMs in one core
session, but it likely does not explain the current fm_only_test.vgm buzzing.

single_fm_sustain.vgm:
  clean from a fresh core load

fm_only_test.vgm:
  still has buzzing/noisy sustained tones from a fresh core load
```

Next diagnostic target:

```text
Isolate which YM2612/JT12 FM channel or patch in fm_only_test.vgm produces the
buzzing, or determine whether the roughness is present across all FM output.
```

Added compile-time macros:

```text
MD_AUDIO_FM_CH1_ONLY_TEST
MD_AUDIO_FM_CH2_ONLY_TEST
MD_AUDIO_FM_CH3_ONLY_TEST
MD_AUDIO_FM_CH4_ONLY_TEST
MD_AUDIO_FM_CH5_ONLY_TEST
MD_AUDIO_FM_CH6_ONLY_TEST
```

Implementation note:

```text
JT12's current wrapper exposes combined stereo FM output, not separate per-
channel PCM. The diagnostic therefore filters YM2612 register 0x28 KeyOn
writes in md_sound_module:

  selected channel:
    KeyOn writes pass unchanged

  non-selected channels:
    operator key-on bits are cleared, preserving the channel number

All other YM register writes still pass through. This keeps VGM timing, loader,
mode5 reset/init, PCM/DAC handling, JT12 CEN, ladder, fm_adjust, genmix, LPF,
and final mixer behavior unchanged.
```

YM2612 KeyOn channel mapping used by the macros:

```text
CH1 -> keyon channel value 0
CH2 -> keyon channel value 1
CH3 -> keyon channel value 2
CH4 -> keyon channel value 4
CH5 -> keyon channel value 5
CH6 -> keyon channel value 6
```

Hardware build guidance:

```text
Keep current best config:
  FIXED_REGION_MODE=5
  MD_JT12_CEN_NTSC_TEST=1
  MD_JT12_LADDER_EFFECT_TEST=1

Add exactly one channel solo macro per A/B build, for example:
  MD_AUDIO_FM_CH1_ONLY_TEST=1
```

Debug marker colors in the top 12 lines:

```text
CH1 solo: red
CH2 solo: green
CH3 solo: blue
CH4 solo: yellow
CH5 solo: magenta
CH6 solo: cyan
```

Suggested hardware pass:

```text
1. Build six RBFs, each with one MD_AUDIO_FM_CHn_ONLY_TEST macro.
2. Fresh-load the core for each RBF.
3. OSD Load VGM: fm_only_test.vgm.
4. Note which solo channels contain the sustained buzzing/noisy tone.
5. Compare against the all-channel current-best build.

Interpretation:
  one channel only:
    suspect that channel's patch/register stream in fm_only_test.vgm

  several channels:
    suspect a shared JT12 behavior triggered by this file's more complex FM use

  no solo channel buzzes, but all-channel does:
    suspect interaction between simultaneous FM channels or accumulated output
```

Compile checks:

```text
tb_mister_vgm_md_top compile with MD_AUDIO_FM_CH1_ONLY_TEST: PASS
tb_mister_vgm_md_top compile with MD_AUDIO_FM_CH2_ONLY_TEST: PASS
tb_mister_vgm_md_top compile with MD_AUDIO_FM_CH3_ONLY_TEST: PASS
tb_mister_vgm_md_top compile with MD_AUDIO_FM_CH4_ONLY_TEST: PASS
tb_mister_vgm_md_top compile with MD_AUDIO_FM_CH5_ONLY_TEST: PASS
tb_mister_vgm_md_top compile with MD_AUDIO_FM_CH6_ONLY_TEST: PASS

emu.sv syntax/elaboration reached the existing vendor PLL model boundary:
  missing altera_pll simulation model
```


## 2026-06-08: CH1 Main Melody Patch Extraction

Hardware observation:

```text
Current best config plus MD_AUDIO_FM_CH1_ONLY_TEST=1:
  intro sounds mostly OK
  when the main melody starts, buzzing/wobble becomes clear
  artifact sounds like rotary-speaker / wave-like modulation

Interpretation:
  the issue is not global JT12 noise
  the strongest suspect is a CH1 main melody patch/operator behavior
```

Tool added:

```text
tools/ch1_patch_probe.py
```

The tool parses `out/fm_only_test.vgm`, tracks CH1 YM2612 register state by VGM
sample time, emits a CSV timeline, summarizes active CH1 key-on patch usage, and
generates minimal CH1-only sustain VGMs from selected patches.

Generated analysis outputs:

```text
out/fm_only_ch1_timeline.csv
out/fm_only_ch1_report.txt
```

CH1 activity summary:

```text
CH1 register events: 1550
CH1 active key-ons: 561
```

Most-used CH1 patches among active key-ons:

```text
patch 104:
  count: 237
  first_t: 21.442s
  first_pc: 0x09081
  likely main melody candidate

patch 125:
  count: 233
  first_t: 106.825s
  likely later/second-section melody candidate

patch 35:
  count: 67
  first_t: 0.000s
  intro/early repeated figure

patch 59:
  count: 24
  first_t: 2.658s
  early transition/fill candidate
```

CH1 patch comparison:

```text
patch 35, intro/early:
  DT/MUL: 61,31,31,61
  TL:     1E,1B,1A,1A
  RS/AR:  4F,4F,9F,1F
  AM/DR:  03,0E,01,15
  SR:     01,08,01,15
  SL/RR:  27,47,28,28
  SSG-EG: 00,00,00,00
  B0:     3C
  B4:     C0

patch 59, early transition:
  DT/MUL: 61,02,01,31
  TL:     18,7F,7F,19
  RS/AR:  11,1F,1F,15
  AM/DR:  0B,1F,1F,09
  SR:     09,00,00,07
  SL/RR:  37,0F,0F,59
  SSG-EG: 00,00,00,00
  B0:     3A
  B4:     C0

patch 104, main melody candidate:
  DT/MUL: 61,23,21,21
  TL:     16,2B,33,1A
  RS/AR:  18,5F,18,1F
  AM/DR:  00,00,00,03
  SR:     00,00,00,03
  SL/RR:  09,09,0B,1C
  SSG-EG: 00,00,00,00
  B0:     3D
  B4:     C0

patch 125, later candidate:
  DT/MUL: 01,12,02,22
  TL:     18,1B,1B,23
  RS/AR:  1C,16,1C,1D
  AM/DR:  1F,1F,1F,1F
  SR:     00,00,00,00
  SL/RR:  09,07,09,08
  SSG-EG: 00,00,00,00
  B0:     3B
  B4:     C0
```

What changes when the suspected wobble begins:

```text
The main melody candidate at 21.442s switches CH1 to patch 104:
  feedback/algorithm changes to B0=3D
  DT/MUL changes from the intro patch's 61,31,31,61 to 61,23,21,21
  TL balance changes to 16,2B,33,1A
  AR/DR/SR/RR envelope shape is much more sustained than the intro patch
  SSG-EG remains disabled on all operators
  B4 remains C0, so AMS/PMS are still 0

Therefore the audible rotary/wave-like artifact is unlikely to be caused by
YM LFO/PMS/AMS or SSG-EG in this file. The next suspects are operator
interaction, feedback, detune/multiply, or an algorithm-specific JT12 behavior.
```

Generated minimal patch VGMs:

```text
out/ch1_main_patch.vgm
  patch 104, one sustained CH1 note

out/ch1_main_patch_fb0.vgm
  patch 104 with feedback forced to 0

out/ch1_main_patch_detune0.vgm
  patch 104 with detune bits forced to 0

out/ch1_main_patch_no_ssgeg.vgm
  patch 104 with SSG-EG forced to 0

out/ch1_main_patch_alg0.vgm
  patch 104 with algorithm forced to 0

out/ch1_main_patch_op1_only.vgm
out/ch1_main_patch_op2_only.vgm
out/ch1_main_patch_op3_only.vgm
out/ch1_main_patch_op4_only.vgm
  patch 104 with only one selected operator keyed on

Additional high-use patch candidates:
  out/ch1_main_patch_patch104.vgm
  out/ch1_main_patch_patch125.vgm
  out/ch1_main_patch_patch35.vgm
  out/ch1_main_patch_patch59.vgm
```

Generated VGM properties:

```text
uncompressed VGM
YM2612 clock: 7,670,454 Hz
LFO register 0x22: 00
channel mode register 0x27: 00
DAC enable 0x2B: 00
PSG writes: none
PCM/data blocks: none
PMS/AMS: B4=C0, so AMS=0 and PMS=0
duration: about 9 seconds
```

Suggested hardware test order:

```text
1. Fresh-load current best RBF.
2. OSD Load VGM: out/ch1_main_patch.vgm.
3. If wobble reproduces, test:
     out/ch1_main_patch_fb0.vgm
     out/ch1_main_patch_detune0.vgm
     out/ch1_main_patch_alg0.vgm
     out/ch1_main_patch_op1_only.vgm .. op4_only
4. If patch104 does not reproduce, test:
     out/ch1_main_patch_patch125.vgm
     out/ch1_main_patch_patch35.vgm
     out/ch1_main_patch_patch59.vgm
```

No VGM loader, timing, CEN, ladder, PCM, reset/init, or final mixer RTL was
changed in this step.


## 2026-06-08: Patch104 Operator Combination A/B VGMs

Hardware result for patch104 operator-only VGMs:

```text
out/ch1_main_patch_op1_only.vgm:
  silent

out/ch1_main_patch_op2_only.vgm:
  faint noise, no rotary/wobble

out/ch1_main_patch_op3_only.vgm:
  simple sustained tone with slight noise, no rotary/wobble

out/ch1_main_patch_op4_only.vgm:
  cleanest / most natural
  sustained "poooo" tone
  slight slow movement

out/ch1_main_patch.vgm, full patch104:
  buzzing / rotary / distortion present

out/ch1_main_patch_fb0.vgm:
  harsh feedback-like buzz is reduced
  rotary movement remains

out/ch1_main_patch_alg0.vgm:
  clean
```

Interpretation:

```text
The artifact is likely not produced by one operator alone. It appears when the
operators interact under patch104's algorithm 5, with feedback contributing the
harsh buzz component.
```

Additional generated operator-combination diagnostics:

```text
out/ch1_main_patch_op3_plus_op4.vgm
  KeyOn data: C0

out/ch1_main_patch_op2_plus_op4.vgm
  KeyOn data: A0

out/ch1_main_patch_op1_plus_op4.vgm
  KeyOn data: 90

out/ch1_main_patch_op2_plus_op3_plus_op4.vgm
  KeyOn data: E0

out/ch1_main_patch_op1_plus_op2_plus_op3_plus_op4_fb0.vgm
  KeyOn data: F0
  B0: 05, algorithm 5 with feedback 0
```

Additional generated feedback-step diagnostics:

```text
out/ch1_main_patch_fb1.vgm
  B0: 0D, algorithm 5 with feedback 1

out/ch1_main_patch_fb2.vgm
  B0: 15, algorithm 5 with feedback 2

out/ch1_main_patch_fb3.vgm
  B0: 1D, algorithm 5 with feedback 3

out/ch1_main_patch_fb4.vgm
  B0: 25, algorithm 5 with feedback 4

out/ch1_main_patch_fb5.vgm
  B0: 2D, algorithm 5 with feedback 5

out/ch1_main_patch_fb6.vgm
  B0: 35, algorithm 5 with feedback 6

out/ch1_main_patch_fb7.vgm
  B0: 3D, original patch104 algorithm/feedback
```

Suggested hardware test order:

```text
Operator interaction pass:
  1. out/ch1_main_patch_op4_only.vgm
  2. out/ch1_main_patch_op3_plus_op4.vgm
  3. out/ch1_main_patch_op2_plus_op4.vgm
  4. out/ch1_main_patch_op1_plus_op4.vgm
  5. out/ch1_main_patch_op2_plus_op3_plus_op4.vgm
  6. out/ch1_main_patch.vgm

Feedback threshold pass:
  1. out/ch1_main_patch_fb0.vgm
  2. out/ch1_main_patch_fb1.vgm
  3. out/ch1_main_patch_fb2.vgm
  4. out/ch1_main_patch_fb3.vgm
  5. out/ch1_main_patch_fb4.vgm
  6. out/ch1_main_patch_fb5.vgm
  7. out/ch1_main_patch_fb6.vgm
  8. out/ch1_main_patch_fb7.vgm
```

No RTL was changed for this step. Only diagnostic VGM generation was extended.


## 2026-06-07: Common Audio Output Gain A/B Test

Hardware A/B observation:

```text
REGION_MODE=3 fixed-ROM playback: correct speed
REGION_MODE=5 OSD-loaded VGM playback: correct speed

common audio issue in both paths:
  snare sounds distorted/clipped
  hi-hat sounds harsh/bright
  channels seem present
  timing is correct
```

Because both fixed-ROM and OSD-loaded playback show the same issue, the first
suspect is the shared audio output/mixing path rather than the mode 5 loader,
BRAM reader, VGM parser, or command timing.

Current common audio path:

```text
VGM command player
  -> md_sound_module
  -> JT12 FM core
  -> JT89 PSG core
  -> fm_adjust_l/r and psg_adjust
  -> jt12_genmix
  -> genesis_lpf with lpf_mode=2'b11
  -> mister_vgm_md_top.audio_l/r
  -> emu.sv final AUDIO_L/R scaling and gate
```

Width inspection:

```text
JT12 FM output:
  fm_left/fm_right are signed 16-bit from jt12.snd_left/snd_right

FM pre-genmix adjustment in md_sound_module:
  fm_adjust_l/r are declared signed 16-bit
  expression is approximately fm * 22.25
  because the destination is 16-bit, large values can wrap/truncate here

JT89 PSG output:
  jt89.sound is signed 11-bit
  internal jt89_mixer sums four signed 9-bit channels into signed 11-bit

PSG pre-genmix adjustment:
  psg_adjust is signed 11-bit
  psg_mixer_snd remains signed 11-bit

jt12_genmix input/output:
  fm_left/fm_right input: signed 16-bit
  psg_snd input: signed 11-bit
  psg is interpolated to signed 12-bit inside genmix
  jt12_fm_uprate mixed register is 16-bit
  final snd_left/snd_right are signed 16-bit

genesis_lpf:
  instantiated on both channels
  lpf_mode is currently 2'b11
  2'b11 bypasses the filter, so no low-pass filtering is active

emu.sv final output:
  default AUDIO_L/R uses md_audio_l/r >>> 2 while audio_gate_open is high
```

Potential clipping/wrap points:

```text
1. fm_adjust_l/r:
   signed 16-bit destination after a large gain expression

2. jt12_fm_uprate.mixed:
   16-bit register receiving FM + shifted PSG

3. jt12 interpolation/decimation chain:
   outputs are signed 16-bit

4. final emu.sv AUDIO_L/R:
   normally reduced by >>> 2, so final MiSTer output is less likely to clip
   unless the signal has already wrapped/clipped upstream
```

Quick hardware A/B attenuation test added:

```text
default build:
  MD_AUDIO_OUTPUT_SHIFT = 2
  AUDIO_L/R = md_audio_l/r >>> 2

test build with -DMD_AUDIO_FINAL_ATTENUATE_6DB:
  MD_AUDIO_OUTPUT_SHIFT = 3
  AUDIO_L/R = md_audio_l/r >>> 3
  this is an additional -6 dB at the final output only
```

This does not change VGM timing, REGION_MODE playback logic, YM registers, VGM
command handling, PCM support, loader capacity, or loop behavior.

Debug added for SignalTap:

```text
md_audio_l_at_rail
md_audio_r_at_rail
md_audio_l_rail_count
md_audio_r_rail_count
```

These counters only see the 16-bit `md_audio_l/r` values entering the final
`emu.sv` output scaler. They can show whether the shared module output is
reaching signed 16-bit rails before the final shift. They cannot prove earlier
internal wrap in `fm_adjust_l/r` or `jt12_fm_uprate.mixed`.

Hardware test plan:

```text
1. Build the normal RBF and confirm the known snare/hi-hat issue.
2. Build a second RBF with MD_AUDIO_FINAL_ATTENUATE_6DB defined.
3. Test the same REGION_MODE=3 fixed-ROM phrase.
4. Test the same REGION_MODE=5 OSD-loaded fm_only_test.vgm.
5. If snare distortion improves significantly, the issue is likely gain/clipping
   at or after the shared 16-bit output.
6. If harshness remains with only lower level, inspect upstream mixer/filter
   configuration next, especially active LPF mode and FM/PSG gain staging.
```

Simulation compile checks:

```text
default tb_mister_vgm_md_top compile: passed
MD_AUDIO_FINAL_ATTENUATE_6DB tb_mister_vgm_md_top compile: passed
warnings: existing JT12/timescale/unique-case style warnings
```


## 2026-06-07: Mode 5 Wait Clock Matched to 20 MHz clk_sys

Hardware observation after disabling the mode 5 playback watchdog:

```text
fm_only_test.vgm now plays through the full chorus/full song structure
and loops on real MiSTer hardware.

foobar2000 loop length: about 2:30, roughly 150 seconds
MiSTer mode 5 loop length: about 1:30, roughly 90 seconds
ratio: 150 / 90 = about 1.666x fast
```

This strongly pointed at a clock-parameter mismatch in the dedicated
`vgm_wait_tick` generator, not a file-size, BRAM address, loop offset, or
command-PC problem.

Confirmed clock path:

```text
sys/sys_top.v:
  HPS_BUS carries clk_sys into emu

rtl/emu.sv:
  pll pll (
    .refclk(CLK_50M),
    .outclk_0(clk_sys)
  )

rtl/pll/pll_0002.v:
  output_clock_frequency0("20.000000 MHz")

rtl/mister_vgm_md_top.sv before this change:
  CLK_SYS_HZ = 12_500_000
```

Because the hardware `clk_sys` is 20 MHz, using `CLK_SYS_HZ=12.5 MHz` makes the
phase accumulator emit too many 44.1 kHz wait ticks per real second:

```text
20.0 / 12.5 = 1.6x
observed: about 1.67x fast
```

Change made:

```text
rtl/mister_vgm_md_top.sv:
  CLK_SYS_HZ default changed from 12_500_000 to 20_000_000

comment added:
  active PLL output feeding emu.clk_sys is 20 MHz
```

This affects the shared dedicated `vgm_wait_tick` generator used by both the
fixed-region path and mode 5. That is intentional: the previous value did not
match the actual hardware clock. `REGION_MODE=0..4` command streams and player
logic were not changed, but their wait timing now uses the hardware-correct
20 MHz clock assumption.

No sound tuning, PCM support, loader capacity change, SDRAM work, or loop-offset
logic change was made in this step.

Test added:

```text
tb/tb_mister_vgm_wait_tick.sv

scaled check:
  CLK_SYS_HZ = 20_000
  VGM_WAIT_HZ = 44
  count vgm_wait_tick pulses for one configured clock-second

expected:
  exactly 44 ticks
```

Simulation result:

```text
PASS tb_mister_vgm_wait_tick clk_hz=20000 wait_hz=44 ticks=44
```

Next hardware test:

```text
1. Build FIXED_REGION_MODE=5 with the updated CLK_SYS_HZ default.
2. Load fm_only_test.vgm through OSD.
3. Measure the loop length again.
4. Expected result: close to foobar2000's about 150 second loop length.
5. Confirm menu return remains OK.
6. Do not tune sound quality from this test.
7. Do not implement PCM unless unsupported_opcode / unsupported_pc proves that
   PCM/DAC commands are the next blocker for a specific file.
```


## 2026-06-07: Mode 5 20 MHz Wait Timing Hardware Pass

`FIXED_REGION_MODE=5` was tested again on real MiSTer hardware after changing
`mister_vgm_md_top.CLK_SYS_HZ` from `12_500_000` to `20_000_000`.

Observed result:

```text
foobar2000 loop length: about 150 seconds
MiSTer mode 5 loop length: about 150 seconds
OSD Load VGM: works
216 KB non-PCM fm_only_test.vgm: loads and plays
64 KiB boundary: crossed successfully
watchdog early restart: fixed
VGM wait timing: correct on real hardware
MiSTer menu return: OK
```

Conclusion:

```text
mode 5 loaded-BRAM playback path is working for the 216 KB non-PCM VGM
the 256 KiB loader is valid on hardware
the 64 KiB address boundary is not the playback-limit problem
the previous 7-8 second restart was the mode 5 watchdog timeout
the previous 150s -> 90s fast playback was the 12.5 MHz vs 20 MHz clock mismatch
```

The confirmed real-hardware path is now:

```text
hps_io ioctl
  -> vgm_file_loader
  -> vgm_loaded_player
  -> md_sound_module
  -> JT12 / JT89
  -> MiSTer AUDIO_L/R
```

No RTL was changed for this note. This records the hardware pass result only.


## 2026-06-07: Mode 5 Early Restart Timing Investigation

Hardware observation:

```text
fm_only_test.vgm:
  Mac-side parser first 0x66: pc=0x35f39
  expected time to first 0x66: about 149.8 seconds
  foobar2000 playback: full song

MiSTer mode 5:
  apparent loop/restart: about 7-8 seconds

cross64_probe.vgm:
  confirmed playback past 64 KiB works
```

Initial suspicion was that mode 5 VGM waits were running roughly 20x too fast.
The code inspection showed a different likely cause.

Wait timing inspection:

```text
vgm_loaded_player:
  wait_remaining decrements only on vgm_wait_tick rising edge
  it does not decrement on every clk_sys
  it does not use audio_sample_valid

mister_vgm_md_top mode 5:
  vgm_loaded_player.vgm_wait_tick is connected to the same dedicated
  vgm_wait_tick generator used by the fixed-region path

vgm_region_player / REGION_MODE=4:
  also decrements waits only on vgm_wait_tick rising edge
```

The more likely early-restart source was the top-level player watchdog:

```text
PLAYER_DONE_TIMEOUT_TICKS = 264600
264600 / 44100 Hz = 6.0 seconds
```

In `STARTUP_PLAYING`, the wrapper reset/retried the player if `player_done`
did not happen before this timeout. That was useful for short fixed-ROM bring-up
regions, but wrong for externally loaded mode 5 VGM files that may run for
minutes. A 6-second watchdog plus startup/warmup latency matches the observed
7-8 second apparent restart much better than a BRAM address or VGM `0x66`
problem.

Change made:

```text
REGION_MODE=0..4:
  keep the existing PLAYER_DONE_TIMEOUT_TICKS watchdog behavior

REGION_MODE=5:
  disable the player_done timeout while playing
  keep start-accept timeout and explicit reset behavior unchanged
```

Additional mode 5 debug:

```text
wait_ticks_consumed_debug:
  32-bit counter in vgm_loaded_player
  increments only when a VGM wait command consumes a vgm_wait_tick
  exported through mister_vgm_md_top and emu for SignalTap/debug
```

Test added:

```text
loaded VGM body:
  60 x 0x62 wait commands
  then 0x66 end

expected:
  60 * 735 = 44100 wait ticks consumed before end
  wait counter does not advance from clk_sys-only cycles
  done is not reached before 44100 consumed wait ticks
```

Important note:

```text
mode 5 was already using the dedicated vgm_wait_tick, not audio_sample_valid.
The user-visible early restart was most likely the mode 5 watchdog timeout.
```

Next hardware test:

```text
1. Build FIXED_REGION_MODE=5.
2. Load fm_only_test.vgm through OSD.
3. Confirm playback does not restart around 7-8 seconds.
4. Let it run well beyond 64 KiB and past the previous apparent restart point.
5. If it still restarts early, capture:
   current_pc_debug
   wait_ticks_consumed_debug
   end_command_seen
   loop_taken_debug
   player_error_code
   unsupported_opcode
   unsupported_pc
6. Do not tune sound quality and do not implement PCM from this result alone.
```


## 2026-06-07: Mode 5 256 KiB Loader Playback and Loop Debug

Real-hardware status before this RTL/debug step:

```text
FIXED_REGION_MODE=5: hardware pass
OSD Load VGM: works
216 KB fm_only_test.vgm: loads and plays from external loaded BRAM
mode 5 256 KiB loader: confirmed on hardware
menu return: OK
```

The 216 KB `fm_only_test.vgm` plays, but was observed to repeat at the same
point as the earlier trimmed 64 KiB test. A PCM-included VGM loads but goes
red/silent. Sound quality and PCM/DAC accuracy are still intentionally out of
scope.

The current supported path remains:

```text
hps_io ioctl
  -> vgm_file_loader
  -> vgm_loaded_player
  -> md_sound_module
  -> JT12 / JT89
  -> MiSTer AUDIO_L/R
```

Before this step, `vgm_loaded_player` handled command `0x66` by entering
`done/ST_DONE`. The startup/replay wrapper could then restart the player from
the parsed VGM data start. The VGM header loop offset at `0x1C` was not read,
so file-authored loop points were ignored.

This step adds hardware-visible mode 5 player debug and basic VGM loop offset
support:

```text
player_error_code: exported through mister_vgm_md_top / emu
unsupported_opcode: exported
unsupported_pc: exported
current_pc_debug: exported full mode5 BRAM-width PC
end_command_seen: latched when command 0x66 is decoded
restarted_from_data_start: latched when playback starts from parsed data_start
loop_pc_debug: exported parsed loop target
loop_valid_debug: exported parsed loop target validity
loop_taken_debug: latched when 0x66 jumps to loop_pc
```

Loop handling now reads the VGM loop offset at header bytes `0x1C..0x1F`:

```text
if loop_offset != 0:
  loop_pc = 0x1C + loop_offset
  loop_valid = loop_pc < file_size and fits loaded RAM address width

on 0x66:
  if loop_valid:
    jump to loop_pc
  else:
    keep the previous done/ST_DONE behavior
```

The non-loop case therefore stays compatible with the previous mode 5 behavior.
`0x67` data block skip, the 256 KiB loader sizing, and `REGION_MODE=0..4` were
not changed. `0xE0`, `0x80..0x8F` DAC stream commands, VGZ, SDRAM, and sound
accuracy tuning were not implemented in this step.

Expected hardware debug interpretation:

```text
red/silent:
  vgm_load_error, vgm_load_overflow, or vgm_player_error
  check player_error_code / unsupported_opcode / unsupported_pc in SignalTap

blue/teal playback:
  mode 5 header valid and player busy

0x66 loop diagnosis:
  end_command_seen=1 and loop_taken_debug=0 means 0x66 ended the stream
  end_command_seen=1 and loop_taken_debug=1 means 0x66 used the VGM loop point
  restarted_from_data_start=1 means playback began from the parsed data_start
```

Exact MiSTer hardware test steps for the next pass:

```text
1. Build an .rbf with FIXED_REGION_MODE=5.
2. Copy the .rbf to the MiSTer test location.
3. Boot/load the core and confirm the video state reaches the mode 5 idle/load screen.
4. Open the OSD and use Load VGM.
5. Load the 216 KB fm_only_test.vgm.
6. Confirm it loads without red/overflow and enters blue/teal playback.
7. Listen for playback and watch whether the previous repeat point changes.
8. Return to the MiSTer menu and confirm menu return remains OK.
9. Load the PCM-included VGM that previously went red/silent.
10. If it still goes red/silent, capture:
    player_error_code
    unsupported_opcode
    unsupported_pc
    current_pc_debug
    end_command_seen
    loop_valid_debug
    loop_taken_debug
11. Do not tune sound quality from this result; use it only to identify the
    next unsupported VGM command or loop behavior.
```

Simulation checks run after this change:

```text
tb_vgm_file_loader: PASS
tb_vgm_loaded_player: PASS
  includes no playback before load_done
  includes VGM data_start parsing
  includes 0x67 data block skip
  includes unsupported opcode debug
  includes no-loop 0x66 done/ST_DONE behavior
  includes valid-loop 0x66 jump-to-loop behavior

tb_mister_vgm_md_top, FIXED_REGION_MODE=5: compile PASS
tb_mister_vgm_md_top, default mode 3: compile PASS
tb_mister_vgm_md_top, default mode 3 5k smoke run: PASS
```

Quartus was not available in the local shell used for this note:

```text
command -v quartus_sh: not found
```


## 2026-06-06: Fixed ROM Milestone and VGM Load Plan

The fixed-ROM bring-up path has reached the intended hardware milestone.

Confirmed on MiSTer hardware:

```text
REGION_MODE=0: hand-written FM/PSG bring-up tone
REGION_MODE=1: smoke-test snippet
REGION_MODE=2: short real-VGM-derived FM snippet
REGION_MODE=3: longer real-VGM-derived YM/PSG phrase
REGION_MODE=4: timing calibration

video shell: stable
MiSTer menu return: OK
audio output: OK
JT12/YM2612 writes: OK
JT89/SN76489 writes: OK
VGM wait tick: corrected for the current 12.5 MHz clk_sys assumption
start/retry/replay: OK for bring-up
silence/end: OK with all-channel key-off, DAC off, PSG mute
```

`REGION_MODE=3 / VGM_REAL_PHRASE` is the current best fixed-ROM proof:

```text
screen: orange while playing
done/replay indication: green observed
audio: real-VGM-derived Super Hang-On-like phrase
repeat: hardware replay confirmed
menu return: OK
```

Keep `REGION_MODE=0..4` as permanent bring-up and regression modes. They are
small, deterministic, and useful when the future file-loading path fails.

Next phase goal:

```text
move from fixed ROM command arrays
to loading an uncompressed .vgm file from MiSTer/HPS
then parse/play it through the same md_sound_module input interface
```

Out of scope for the first loader:

```text
VGZ decompression
XGM
full DAC Stream Control 0x90-0x95
compressed data blocks
multi-bank PCM
playlist/browser UI
full loop polish
audio filter/level matching
```

Initial supported target:

```text
uncompressed .vgm only
Mega Drive / Genesis style command subset
YM2612 writes: 0x52 / 0x53
SN76489 writes: 0x50
waits: 0x61 / 0x62 / 0x63 / 0x70-0x7F
end: 0x66
skip or minimally hold: 0x4F, 0x67, 0xE0, 0x80-0x8F for later DAC phase
```

Current MiSTer shell already exposes the relevant `hps_io` download signals:

```text
ioctl_download
ioctl_wr
ioctl_addr[26:0]
ioctl_dout[7:0]
ioctl_index[15:0]
```

These are currently unused by the sound path. The loader phase should connect
them to a new VGM receive buffer.

Suggested architecture:

```text
MiSTer OSD / HPS file download
  -> hps_io ioctl_download/ioctl_wr/ioctl_addr/ioctl_dout
  -> vgm_file_loader
  -> VGM byte memory
  -> vgm_file_player
  -> existing md_sound_module command inputs
  -> JT12 / JT89
  -> MiSTer AUDIO_L/R
```

New RTL blocks to add later:

```text
rtl/vgm_file_loader.sv
  receives bytes from ioctl_wr
  writes them to BRAM or SDRAM
  tracks file_size
  exposes load_done / load_busy / load_error

rtl/vgm_file_player.sv
  reads bytes from VGM memory
  parses the VGM header
  computes command_start
  executes the same command subset as vgm_region_player
  drives ym_cmd_valid / psg_cmd_valid into md_sound_module

rtl/vgm_memory_bram.sv or SDRAM adapter
  first implementation can be BRAM for small test VGMs
  later implementation can use SDRAM for full songs
```

BRAM-first option:

```text
pros:
  simplest to simulate
  easiest first hardware pass
  deterministic timing
  no SDRAM arbitration yet

cons:
  limited file size
  not enough for many full VGM files
```

Recommended first BRAM size:

```text
64 KiB or 128 KiB if the Quartus fit allows it
enough for short uncompressed VGM tests
not intended for full library support
```

SDRAM option for later:

```text
pros:
  enough space for full uncompressed VGM files
  closer to final architecture

cons:
  requires MiSTer memory-controller integration
  needs arbitration between loader writes and player reads
  harder to debug than BRAM
```

VGM header handling for the first player:

```text
check magic "Vgm "
read version
read EOF offset for sanity
read SN76489 clock
read YM2612 clock
read total samples
read loop offset / loop samples, but loop can be ignored first
read data offset

if version >= 1.50 and data_offset != 0:
  command_start = 0x34 + data_offset
else:
  command_start = 0x40
```

Playback state machine sketch:

```text
IDLE
  wait for load_done and play_start

READ_HEADER
  validate magic and compute command_start

FETCH_CMD
  read one byte at pc

DECODE
  0x52: read reg/data, send YM port0 write
  0x53: read reg/data, send YM port1 write
  0x50: read data, send PSG write
  0x61: read 16-bit wait count
  0x62: wait 735
  0x63: wait 882
  0x70-0x7F: wait 1..16
  0x66: stop or wait-for-replay

WAIT_READY
  wait for ym_cmd_ready / psg_cmd_ready

WAIT_SAMPLES
  count vgm_wait_tick, not audio_sample_valid

DONE
  hold stopped or replay depending on bring-up mode
```

Important design rule:

```text
VGM timing must remain based on the dedicated 44100 Hz vgm_wait_tick.
Do not return to audio_sample_valid as the VGM wait source.
```

Reuse from fixed-ROM path:

```text
md_sound_module command interface
JT12/JT89 write timing and ready handling
vgm_wait_tick generator in mister_vgm_md_top
debug colors / menu-safe InputTest shell
REGION_MODE fixed ROMs as fallback tests
```

Milestone plan:

```text
Phase A: Loader-only smoke
  hps_io downloads a small .vgm into BRAM
  show load_done/load_error with debug colors
  no playback yet

Phase B: Header parser
  read magic/version/data_offset from BRAM
  expose command_start/debug values
  reject non-VGM/VGZ

Phase C: YM-only file playback
  support 0x52/0x53/waits/0x66
  use a small FM-only VGM first
  compare against fixed REGION_MODE=3 behavior

Phase D: PSG support
  add 0x50 and 0x4F skip/handling
  confirm YM+PSG file playback

Phase E: Minimal DAC stream support
  add 0x67 type 0x00 data block
  add 0xE0 seek
  add 0x80-0x8F generated YM 0x2A writes
  reuse the simulator-proven minimal PCM approach

Phase F: Loop/end behavior
  implement optional loop offset
  define stop, replay, and silence behavior

Phase G: SDRAM/full-size path
  move from BRAM to SDRAM once the parser/player works
```

Bring-up UI/debug suggestion:

```text
fixed ROM modes remain selected by source default or build define
file-loader mode gets a new debug color
loader states:
  waiting for file
  downloading
  load done
  header OK
  playing
  done
  error
```

Do not remove the fixed ROM path when adding the loader. It is the known-good
hardware reference for video, reset, timing, JT12/JT89 writes, and AUDIO output.


## 2026-06-07: Phase A VGM File Loader Smoke RTL

The first uncompressed VGM loading step has been added without replacing the
known-good fixed-ROM playback path.

Added:

```text
rtl/vgm_file_loader.sv
tb/tb_vgm_file_loader.sv
```

`vgm_file_loader` receives the existing MiSTer `hps_io` download bus:

```text
ioctl_download
ioctl_wr
ioctl_addr[26:0]
ioctl_dout[7:0]
ioctl_index[15:0]
```

For this first smoke step it stored bytes into a small BRAM-backed buffer:

```text
ADDR_WIDTH = 16
capacity   = 64 KiB
```

This was the initial Phase A size. A later compatibility step raises the
active `REGION_MODE=5` capacity to 256 KiB.

It exposes only loader status and debug values for now:

```text
load_busy
load_done
load_error
overflow_error
file_size
magic_debug
```

No VGM header parser or file playback is connected yet. The active audio path
still uses:

```text
REGION_MODE=3 fixed ROM
  -> vgm_region_player
  -> md_sound_module
  -> JT12 / JT89
  -> AUDIO_L/R
```

`rtl/emu.sv` now adds an OSD file entry:

```text
F,VGM,Load VGM;
```

and instantiates `vgm_file_loader` beside the existing fixed-region sound path.
The loader accepts any download index for the initial smoke test, so the first
hardware check should focus on whether selecting a `.vgm` from the OSD changes
the loader debug color.

Debug colors added above the normal fixed-ROM color priority:

```text
blue: file download active
cyan: file download completed into BRAM
red : file load error or initial 64 KiB overflow
```

`files.qip` now includes:

```text
set_global_assignment -name SYSTEMVERILOG_FILE rtl/vgm_file_loader.sv
```

Loader unit test:

```sh
iverilog -g2012 -Wall -s tb_vgm_file_loader \
  -o /tmp/tb_vgm_file_loader.vvp \
  tb/tb_vgm_file_loader.sv \
  rtl/vgm_file_loader.sv

vvp /tmp/tb_vgm_file_loader.vvp
```

Observed result:

```text
PASS tb_vgm_file_loader
```

Existing fixed-ROM top-path build still passes:

```sh
iverilog -g2012 -Wall -DTEST_MISTER_TOP_MODE3_5K \
  -s tb_mister_vgm_md_top \
  -o /tmp/tb_mister_vgm_md_top_mode3_top_path_5k.vvp \
  tb/tb_mister_vgm_md_top.sv \
  rtl/mister_vgm_md_top.sv \
  rtl/vgm_region_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v
```

Warnings are the existing JT12/timescale/unique-case warnings.

Attempted `emu.sv` elaboration with `iverilog` stops because `build_id.v` is a
Quartus/generated include and is not present in the repository checkout. This
is not a loader-specific failure.

Next hardware check:

```text
1. Build the MiSTer core.
2. Confirm fixed REGION_MODE=3 playback still works.
3. Open OSD and load a small uncompressed .vgm.
4. Expect blue while downloading.
5. Expect cyan after load_done, or red if the file exceeds the active BRAM
   capacity.
```

If Phase A passes on hardware, the next RTL step is Phase B: read bytes back
from the BRAM buffer and validate the VGM header magic/version/data offset.


## 2026-06-07: REGION_MODE=5 Loaded-BRAM VGM Playback

OSD file index behavior was inspected in `sys/hps_io.sv`.

Relevant implementation:

```text
FIO_FILE_INDEX writes io_din[15:0] directly to ioctl_index
FIO_FILE_TX starts/ends ioctl_download
FIO_FILE_TX_DAT emits ioctl_wr/ioctl_addr/ioctl_dout while downloading
```

So the safe hardware contract is to make the CONF_STR index explicit and match
the loader to it:

```text
rtl/emu.sv:
  F1,VGM,Load VGM;

rtl/mister_vgm_md_top.sv / vgm_file_loader:
  VGM_LOAD_FILE_INDEX = 1
  ACCEPT_ANY_INDEX = 0
```

This replaces the previous Phase A permissive loader mode. A download with any
other `ioctl_index` is ignored.

Added:

```text
rtl/vgm_loaded_player.sv
tb/tb_vgm_loaded_player.sv
```

`REGION_MODE=5` now selects the first loaded-BRAM playback path:

```text
hps_io ioctl_* download
  -> vgm_file_loader, BRAM
  -> vgm_loaded_player
  -> md_sound_module
  -> JT12 / JT89
  -> AUDIO_L/R
```

`REGION_MODE=0..4` remain fixed-ROM modes and are not rewritten. In
`mister_vgm_md_top`, mode 5 is selected with a generate branch; all other modes
still instantiate `md_sound_fixed_region_test`.

Mode 5 behavior:

```text
no valid load_done:
  no YM/PSG commands are generated
  audio path remains silent

load_error or overflow_error:
  no YM/PSG commands are generated
  debug error color is shown

load_done_pulse with valid file:
  dynamic player validates the VGM header
  data_start is computed
  playback starts from loaded BRAM
```

Minimal supported VGM header parsing:

```text
magic bytes 0x00..0x03 must be "Vgm "
data offset is read little-endian from 0x34..0x37
if data offset == 0:
  data_start = 0x40
else:
  data_start = 0x34 + data_offset
```

Minimal supported command subset:

```text
0x52 rr dd   YM2612 port 0 write
0x53 rr dd   YM2612 port 1 write
0x50 dd      SN76489 write
0x4F dd      Game Gear stereo write, skipped
0x61 ll hh   wait n VGM samples
0x62         wait 735 samples
0x63         wait 882 samples
0x70-0x7F    short wait 1..16 samples
0x66         end
```

Unsupported commands currently stop with `player_error`. This first mode 5
path does not support VGZ/gzip, compressed VGM data blocks, DAC stream control,
or SDRAM streaming.

Debug color additions:

```text
file download busy: blue
file loaded: cyan
mode 5 header-valid playback: teal/blue
load error / overflow / player error: red
```

Tests run:

```sh
iverilog -g2012 -Wall -s tb_vgm_file_loader \
  -o /tmp/tb_vgm_file_loader.vvp \
  tb/tb_vgm_file_loader.sv \
  rtl/vgm_file_loader.sv

vvp /tmp/tb_vgm_file_loader.vvp
```

Result:

```text
PASS tb_vgm_file_loader
```

Coverage:

```text
index mismatch ignored
index 1 accepted
load_done_pulse generated
bytes readable after load
overflow detected
```

```sh
iverilog -g2012 -Wall -s tb_vgm_loaded_player \
  -o /tmp/tb_vgm_loaded_player.vvp \
  tb/tb_vgm_loaded_player.sv \
  rtl/vgm_loaded_player.sv

vvp /tmp/tb_vgm_loaded_player.vvp
```

Result:

```text
PASS tb_vgm_loaded_player
```

Coverage:

```text
no playback before load_done
data offset 0 selects data_start 0x40
nonzero data offset selects data_start 0x34 + offset
load_error prevents playback
overflow_error prevents playback
```

Existing mode 3 top-path simulation:

```sh
iverilog -g2012 -Wall -DSIMULATION -DTEST_MISTER_TOP_MODE3_5K \
  -s tb_mister_vgm_md_top \
  -o /tmp/tb_mister_vgm_md_top_mode3_top_path_5k.vvp \
  tb/tb_mister_vgm_md_top.sv \
  rtl/mister_vgm_md_top.sv \
  rtl/vgm_region_player.sv \
  rtl/vgm_file_loader.sv \
  rtl/vgm_loaded_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v

vvp /tmp/tb_mister_vgm_md_top_mode3_top_path_5k.vvp
```

Result:

```text
MISTER_VGM_MD_TOP_TEST_DONE
wav_written_samples=5000
audio_sample_valid_edges=5000
startup_done=1
audio_gate_open=1
```

Mode 5 generate-path compile:

```sh
iverilog -g2012 -Wall -DSIMULATION -DFIXED_REGION_MODE=5 \
  -DTEST_MISTER_TOP_MODE3_5K \
  -s tb_mister_vgm_md_top \
  -o /tmp/tb_mister_vgm_md_top_mode5_compile.vvp \
  tb/tb_mister_vgm_md_top.sv \
  rtl/mister_vgm_md_top.sv \
  rtl/vgm_region_player.sv \
  rtl/vgm_file_loader.sv \
  rtl/vgm_loaded_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v
```

Result:

```text
build passed
warnings: existing JT12/timescale/unique-case style warnings
```

Quartus was not run in this environment because `quartus_sh` was not available
on PATH.

Exact MiSTer hardware steps for mode 5:

```text
1. Keep rtl/fixed_region_mode.vh default at 3 for reference builds unless
   intentionally testing loaded playback.

2. For the mode 5 hardware build, set:
     `define FIXED_REGION_MODE 5
   or add the equivalent Quartus VERILOG_MACRO for FIXED_REGION_MODE=5.

3. Build the core and copy the RBF to MiSTer.

4. Boot the core.
   Expected before loading a file:
     no VGM playback from mode 5
     no YM/PSG commands from loaded player
     menu return still works

5. Open OSD and choose:
     Load VGM

6. Select a small uncompressed .vgm that fits in the active BRAM capacity.
   The file should use only the currently supported command subset.

7. Expected colors:
     blue while downloading
     cyan after load_done
     teal/blue while header-valid playback is busy
     red on load overflow, bad header, unsupported command, or other player error

8. Expected audio:
     the loaded .vgm starts automatically after load_done
     waits use the existing 44.1 kHz vgm_wait_tick
     no audio should play for no file, bad header, overflow, or unsupported command

9. Rebuild or reset back to FIXED_REGION_MODE=3 to compare against the known-good
   fixed-ROM reference path.
```


## 2026-06-07: REGION_MODE=5 Hardware Pass

`FIXED_REGION_MODE=5` was tested on real MiSTer hardware.

Observed result:

```text
MiSTer menu return: OK
OSD Load VGM: works
large source VGM: fm_only_test.vgm, about 216 KiB
large-file result: overflow detected, red debug color, silent as expected
trimmed source VGM: fm_only_test_64k.vgm, under 64 KiB
trimmed-file result: loaded successfully
debug playback state: blue/debug playback state observed
audio: external loaded VGM plays and repeats
```

This confirms that the first real-hardware OSD-loaded uncompressed VGM playback
path is alive:

```text
hps_io ioctl
  -> vgm_file_loader
  -> vgm_loaded_player
  -> md_sound_module
  -> JT12 / JT89
  -> MiSTer AUDIO_L/R
```

Important conclusions:

```text
F1,VGM,Load VGM; reaches the loader path correctly
ioctl file download reaches BRAM-backed vgm_file_loader
64 KiB overflow handling works on hardware
overflow/error path stays silent and shows red
trimmed under-64 KiB uncompressed VGM can be loaded from OSD
loaded-BRAM playback can drive the existing YM/PSG sound path
the existing menu-safe MiSTer shell remains OK
```

This is the first confirmed hardware pass where the command bytes did not come
from fixed FPGA ROM. The known-good fixed `REGION_MODE=3` path should remain as
the reference comparison path while the loaded-player support grows.

No RTL was changed for this note. This records the hardware pass result only.


## 2026-06-07: REGION_MODE=5 256 KiB BRAM and 0x67 Skip

After the first `FIXED_REGION_MODE=5` hardware pass, the loaded-player
compatibility path was extended without changing the known-good fixed-ROM
paths.

Unchanged:

```text
REGION_MODE=0..4
REGION_MODE=3 fixed-ROM reference path
JT12/JT89 command adapters
sound accuracy / tuning
VGZ support
SDRAM support
DAC stream support
```

Capacity change:

```text
old loaded VGM BRAM:
  ADDR_WIDTH = 16
  capacity   = 64 KiB

new loaded VGM BRAM:
  ADDR_WIDTH = 18
  capacity   = 256 KiB
```

The wider address is carried through:

```text
vgm_file_loader rd_addr/write address range
vgm_loaded_player rd_addr / pc / data_start_debug
mister_vgm_md_top VGM_LOAD_ADDR_WIDTH default
emu.sv loader debug wires
file_size width
overflow detection
```

New command compatibility:

```text
0x67 0x66 tt ss ss ss ss
```

`vgm_loaded_player` now recognizes VGM data blocks and skips them:

```text
read marker 0x66
read block type tt
read 32-bit little-endian block size
advance pc by 7 + size bytes
continue with the next VGM command
```

The data bytes are not decoded or played yet. This is only a compatibility
skip so files containing VGM data blocks can continue to later YM/PSG commands.

Still not implemented:

```text
0xE0 PCM seek
0x80-0x8F DAC stream writes
0x90-0x95 DAC stream control
VGZ/gzip
SDRAM/full-file streaming
```

Error behavior:

```text
if a 0x67 block would skip beyond file_size:
  player_error is set
  playback remains silent

if an unsupported opcode is decoded:
  player_error is set
  unsupported_opcode records the opcode
  unsupported_pc records the command pc
  player_error_code records the reason
  playback remains silent
```

Current player error code meanings:

```text
0 = none
1 = bad VGM magic
2 = bad data_start
3 = pc out of loaded file range
4 = unsupported opcode
5 = loader error / overflow input
6 = malformed 0x67 data block
7 = 0x67 data block skip beyond file_size
```

Tests run:

```sh
iverilog -g2012 -Wall -s tb_vgm_file_loader \
  -o /tmp/tb_vgm_file_loader.vvp \
  tb/tb_vgm_file_loader.sv \
  rtl/vgm_file_loader.sv

vvp /tmp/tb_vgm_file_loader.vvp
```

Result:

```text
PASS tb_vgm_file_loader
```

Coverage:

```text
index mismatch ignored
index 1 accepted
normal low-address load/readback
write beyond 64 KiB but below 256 KiB accepted
overflow above 256 KiB still errors
```

```sh
iverilog -g2012 -Wall -s tb_vgm_loaded_player \
  -o /tmp/tb_vgm_loaded_player.vvp \
  tb/tb_vgm_loaded_player.sv \
  rtl/vgm_loaded_player.sv

vvp /tmp/tb_vgm_loaded_player.vvp
```

Result:

```text
PASS tb_vgm_loaded_player
```

Coverage:

```text
no playback before load_done
data_start 0x40 when header data offset is zero
data_start 0x34 + offset when header data offset is nonzero
0x67 data block skipped and later PSG command executed
0x67 data block skip beyond file_size raises player_error
unsupported opcode raises player_error
unsupported opcode and pc are recorded
load_error prevents playback
overflow_error prevents playback
```

Mode 5 generate-path compile:

```sh
iverilog -g2012 -Wall -DSIMULATION -DFIXED_REGION_MODE=5 \
  -DTEST_MISTER_TOP_MODE3_5K \
  -s tb_mister_vgm_md_top \
  -o /tmp/tb_mister_vgm_md_top_mode5_compile.vvp \
  tb/tb_mister_vgm_md_top.sv \
  rtl/mister_vgm_md_top.sv \
  rtl/vgm_region_player.sv \
  rtl/vgm_file_loader.sv \
  rtl/vgm_loaded_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v
```

Result:

```text
build passed
warnings: existing JT12/timescale/unique-case style warnings
```

Fixed-ROM reference generate-path compile:

```sh
iverilog -g2012 -Wall -DSIMULATION -DTEST_MISTER_TOP_MODE3_5K \
  -s tb_mister_vgm_md_top \
  -o /tmp/tb_mister_vgm_md_top_mode3_compile.vvp \
  tb/tb_mister_vgm_md_top.sv \
  rtl/mister_vgm_md_top.sv \
  rtl/vgm_region_player.sv \
  rtl/vgm_file_loader.sv \
  rtl/vgm_loaded_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v
```

Result:

```text
build passed
warnings: existing JT12/timescale/unique-case style warnings
```

Quartus was not run in this environment because `quartus_sh` was not available
on PATH.

Next hardware check:

```text
1. Build with FIXED_REGION_MODE=5.
2. Load a VGM larger than 64 KiB but smaller than 256 KiB.
3. Confirm it no longer overflows only because it crossed 64 KiB.
4. Load a VGM larger than 256 KiB.
5. Confirm red/error/silent still occurs.
6. Load an uncompressed VGM with a 0x67 data block before later YM/PSG writes.
7. Confirm playback continues past the data block.
8. Do not evaluate sound accuracy yet.
```


## 2026-06-06: Region Mode 3 Audio Difference Triage

`REGION_MODE=3 / VGM_REAL_PHRASE` now plays and replays on real MiSTer
hardware, but the tone is still audibly different from the source/original VGM
playback. Before changing the sound path, keep the next step focused on
comparison data.

Current mode3 fixed ROM facts:

```text
region: REGION_MODE=3 / VGM_REAL_PHRASE
generated include: rtl/vgm_real_phrase_mode3_case.vh
source VGM: /Users/daizo/Downloads/fm_only_test.vgm
source slice start: VGM pc=0x00000040
source slice end:   VGM pc=0x000014AA
copied wait total before suffix: 100220 samples
ROM byte count including strong silence suffix: 5262
suffix: all 6 YM key-off, DAC zero/off, PSG mute all, final wait, 0x66 end
```

The slice starts at the VGM command area and includes the early YM setup writes
visible at the start of the generated ROM:

```text
YM key-off for channels 0..5
LFO off
timer/control setup
DAC off
YM port0 and port1 operator/frequency/pan writes from the source VGM
wait commands copied from the source command stream
```

Top-level simulation WAV procedure for mode3:

```sh
iverilog -g2012 -Wall -DSIMULATION \
  -s tb_mister_vgm_md_top \
  -o /tmp/tb_mister_vgm_md_top_mode3_audio_check.vvp \
  tb/tb_mister_vgm_md_top.sv \
  rtl/mister_vgm_md_top.sv \
  rtl/vgm_region_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v

vvp /tmp/tb_mister_vgm_md_top_mode3_audio_check.vvp \
  > /tmp/tb_mister_vgm_md_top_mode3_audio_check.log

python3 tools/audio_txt_to_wav/audio_txt_to_wav.py \
  /tmp/mister_vgm_md_top_5k.txt \
  /tmp/mister_vgm_md_top_mode3_5k_gain1.wav \
  --gain 1

python3 tools/audio_txt_to_wav/audio_txt_to_wav.py \
  /tmp/mister_vgm_md_top_5k.txt \
  /tmp/mister_vgm_md_top_mode3_5k_gain2.wav \
  --gain 2
```

For a MiSTer hardware recording comparison, generate a simulation WAV with the
same intended sample count as the capture. The current top TB dumps 5000 samples
to:

```text
/tmp/mister_vgm_md_top_5k.txt
```

If the hardware recording is longer, temporarily adjust only
`AUDIO_DUMP_SAMPLE_COUNT` in `tb/tb_mister_vgm_md_top.sv` or add a dedicated
test define for the desired sample count, then regenerate the WAV with the same
gain used for comparison. Do not tune RTL audio based on a different duration or
gain.

Current mixer/filter/audio-output path:

```text
JT12 fm_left/fm_right
  -> fm_adjust_l/r, matching the Genesis_MiSTer-style pre-genmix gain adjustment
JT89 psg_sound
  -> psg_adjust
jt12_genmix
  -> pre_lpf_l/r
genesis_lpf
  -> audio_l/audio_r
emu.sv
  -> AUDIO_L/R = md_audio_l/r >>> 2 while audio_gate_open is high
```

Important current difference from a final Genesis/Mega Drive output model:

```text
genesis_lpf is instantiated, but lpf_mode is 2'b11, which is bypass
AUDIO_L/R are shifted right by 2 in emu.sv for safe hardware level
AUDIO_MIX is 2'b00, so stereo is not forced to mono by this core
PCM/DAC stream is not part of this mode3 fixed phrase
```

Likely causes to isolate, in order:

```text
1. Source/reference mismatch
   Compare against the same fixed slice, not a full VGM player at another song
   position.

2. Filter mismatch
   The current hardware path bypasses genesis_lpf. Original MD/MiSTer playback
   may use Model 1, Model 2, or another low-pass response.

3. Level mismatch
   emu.sv applies AUDIO >>> 2 after md_sound_module. This should not change
   pitch or register behavior, but it changes perceived loudness and may make
   envelopes feel different.

4. Command context mismatch
   The mode3 ROM includes YM setup from command_start, but it is still a fixed
   slice. If the reference playback includes earlier reset behavior, DAC/PCM, or
   a different VGM region, the tone will differ.

5. Wait/timing mismatch
   VGM waits now use a dedicated 44100 Hz tick with CLK_SYS_HZ=12_500_000.
   The mode4 calibration made the first 1-second wait roughly correct, but a
   longer capture should still be compared against simulation at the same sample
   count.

6. JT12/JT89 model difference
   If the simulation top WAV and MiSTer recording match each other but both
   differ from another emulator/player, the remaining difference may be the
   selected JT12/JT89 model/mixer/filter configuration rather than the VGM
   command stream.
```

Do not change the audio RTL yet. First collect:

```text
top-sim mode3 WAV, gain1/gain2, same sample count as hardware capture
MiSTer hardware recording from the same region and gain path
reference/original VGM playback of the same slice, if possible
```

Then compare:

```text
pitch/tempo
attack timing
envelope decay
stereo pan
high-frequency brightness, especially with LPF bypass
overall level caused by >>> 2
```


## 2026-06-06: Region Mode 3 Comparison Baseline

The comparison target is now fixed to the exact ROM used by hardware
`REGION_MODE=3`.

Baseline definition:

```text
fixed ROM file: rtl/vgm_real_phrase_mode3_case.vh
mode name: REGION_MODE=3 / VGM_REAL_PHRASE
source VGM: /Users/daizo/Downloads/fm_only_test.vgm
source slice: VGM pc=0x00000040 through 0x000014AA
copied wait total before suffix: 100220 samples
ROM byte count including strong silence suffix: 5262
```

Use this as the only reference for mode3 MiSTer comparison. Do not mix these
results with:

```text
REGION_MODE=2 / VGM_REAL_SNIPPET
older 50K fixed-region WAVs
full-VGM parser simulation WAVs
PCM/DAC-region tests
```

Top-path simulation means the signal goes through the same wrapper path used by
the MiSTer shell:

```text
tb_mister_vgm_md_top
  -> mister_vgm_md_top
  -> md_sound_fixed_region_test
  -> vgm_region_player REGION_MODE=3
  -> md_sound_module
  -> JT12 / JT89
  -> jt12_genmix
  -> genesis_lpf bypass
  -> audio_l/audio_r
```

120K top-path dump command:

```sh
iverilog -g2012 -Wall -DSIMULATION -DTEST_MISTER_TOP_MODE3_120K \
  -s tb_mister_vgm_md_top \
  -o /tmp/tb_mister_vgm_md_top_mode3_top_path_120k.vvp \
  tb/tb_mister_vgm_md_top.sv \
  rtl/mister_vgm_md_top.sv \
  rtl/vgm_region_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v

vvp /tmp/tb_mister_vgm_md_top_mode3_top_path_120k.vvp \
  > /tmp/tb_mister_vgm_md_top_mode3_top_path_120k.log
```

Short top-path debug commands:

```sh
iverilog -g2012 -Wall -DSIMULATION -DTEST_MISTER_TOP_MODE3_5K \
  -s tb_mister_vgm_md_top \
  -o /tmp/tb_mister_vgm_md_top_mode3_top_path_5k.vvp \
  tb/tb_mister_vgm_md_top.sv \
  rtl/mister_vgm_md_top.sv \
  rtl/vgm_region_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v

vvp /tmp/tb_mister_vgm_md_top_mode3_top_path_5k.vvp

iverilog -g2012 -Wall -DSIMULATION -DTEST_MISTER_TOP_MODE3_10K \
  -s tb_mister_vgm_md_top \
  -o /tmp/tb_mister_vgm_md_top_mode3_top_path_10k.vvp \
  tb/tb_mister_vgm_md_top.sv \
  rtl/mister_vgm_md_top.sv \
  rtl/vgm_region_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v

vvp /tmp/tb_mister_vgm_md_top_mode3_top_path_10k.vvp
```

The top-path TB now prints debug state before and during dumping:

```text
MISTER_VGM_MD_TOP_TEST_START
MISTER_VGM_MD_TOP_WAITING_FOR_AUDIO_EDGE
MISTER_VGM_MD_TOP_FIRST_AUDIO_EDGE
MISTER_VGM_MD_TOP_DUMP_PROGRESS
MISTER_VGM_MD_TOP_WATCHDOG_TIMEOUT
MISTER_VGM_MD_TOP_TEST_DONE
```

The debug lines include:

```text
audio_sample_valid
audio_gate_open
startup_reset / startup_waiting / startup_done
internal startup_state
player_busy / player_done
player_pc_debug / player_last_cmd_debug
start_pulse
player_reset_active
vgm_wait_tick
```

The TB also flushes the text dump after the first audio edge and periodically
after that, so a running simulation should no longer appear as a permanently
zero-line file merely because stdio buffering has not reached `$fclose`.

Expected text dump:

```text
/tmp/mister_vgm_md_top_mode3_top_path_120k.txt
```

WAV conversion:

```sh
python3 tools/audio_txt_to_wav/audio_txt_to_wav.py \
  /tmp/mister_vgm_md_top_mode3_top_path_120k.txt \
  /tmp/mister_vgm_md_top_mode3_top_path_120k_gain1.wav \
  --gain 1

python3 tools/audio_txt_to_wav/audio_txt_to_wav.py \
  /tmp/mister_vgm_md_top_mode3_top_path_120k.txt \
  /tmp/mister_vgm_md_top_mode3_top_path_120k_gain2.wav \
  --gain 2
```

These WAVs are the comparison baseline for MiSTer hardware `REGION_MODE=3`:

```text
/tmp/mister_vgm_md_top_mode3_top_path_120k_gain1.wav
/tmp/mister_vgm_md_top_mode3_top_path_120k_gain2.wav
```

Comparison rule:

```text
same fixed ROM
same top path
same sample count
same gain
same AUDIO >>> 2 hardware path noted separately
```


## 2026-06-06: Region Mode 3 Start Retry / Replay

`REGION_MODE=3 / VGM_REAL_PHRASE` was confirmed on real MiSTer hardware, but
the replay was not yet stable.

Observed result:

```text
screen: orange
MiSTer menu return: OK
audio: Super Hang-On-intro-like sound played once
tempo: improved after the 12.5 MHz wait tick correction
issue: after several core resets, playback happened only once
```

Conclusion:

```text
REGION_MODE=3 itself is active
the VGM_REAL_PHRASE ROM contents were not changed
the JT12/JT89/audio path was not changed
the remaining issue is bring-up start/reset/replay stability
```

Change made for bring-up stability:

```text
rtl/mister_vgm_md_top.sv:
  add player-local retry reset
  retry if player_busy is not seen after start
  retry if player_done is not seen within a timeout
  add REPLAY_ENABLE for automatic replay after player_done
  wait about 2 seconds before replay by default

rtl/vgm_region_player.sv:
  add player_reset to md_sound_fixed_region_test wrapper
  retry reset is applied to vgm_region_player only
  md_sound_module reset remains tied to the normal top reset

rtl/emu.sv:
  keep AUDIO_L/R scaling at >>> 2
  keep debug color output
  show reset/retry reset as yellow
  show start/replay wait as magenta
  show REGION_MODE=3 playback as orange
  show player_done latched as green
```

The sound core itself remains untouched:

```text
rtl/md_sound_module.sv unchanged
JT12/JT89 unchanged
REGION_MODE=3 ROM unchanged
AUDIO >>> 2 scaling unchanged
```


## 2026-06-06: VGM Wait Tick Clock Assumption Adjusted to 12.5 MHz

`REGION_MODE=4 / TIMING_CALIBRATION` was tested on real MiSTer hardware after
splitting VGM waits from `audio_sample_valid`.

Observed result:

```text
screen: lime, confirming REGION_MODE=4
expected: 1 second tone / 1 second silence
actual: about 4 seconds tone / about 4 seconds silence
```

This means the dedicated `vgm_wait_tick` exists and is controlling VGM wait
progression, but it is about 4x too slow. The most likely cause is that the
clock feeding `mister_vgm_md_top` in the InputTest-based shell is not 50 MHz,
but closer to 12.5 MHz.

Correction for the next hardware timing calibration:

```text
rtl/mister_vgm_md_top.sv
  CLK_SYS_HZ default:
    50_000_000 -> 12_500_000
```

The phase accumulator still targets:

```text
VGM_WAIT_HZ = 44100
```

Expected next check:

```text
REGION_MODE=4 should produce roughly:
  1 second tone
  1 second silence
  repeated
```

Build checks after the default change:

```text
tb_mister_vgm_md_top build: passed
TEST_FIXED_TIMING_CALIBRATION_100K build: passed
warnings: existing JT12/timescale/unique-case warnings
```

Unchanged:

```text
md_sound_module internals
JT12/JT89 sources
AUDIO_L/R and >>> 2 scaling
```


## 2026-06-06: Return to Region Mode 3 After Timing Calibration

`REGION_MODE=4 / TIMING_CALIBRATION` was tested again after changing
`CLK_SYS_HZ` to 12.5 MHz.

Observed result:

```text
first expected 1 second tone: roughly 1 second on hardware
later repeats: silent due to the mode 4 re-trigger sequence, not treated as a
               wait-timing blocker
```

Conclusion:

```text
12.5 MHz CLK_SYS_HZ assumption is good enough for the next VGM phrase test
VGM wait tick correction is effective
timing calibration phase is sufficient for now
```

The hardware default was switched back from mode 4 to mode 3:

```text
rtl/fixed_region_mode.vh
  FIXED_REGION_MODE = 3
```

Keep:

```text
rtl/mister_vgm_md_top.sv
  CLK_SYS_HZ = 12_500_000
  VGM_WAIT_HZ = 44_100
```

Next hardware check:

```text
REGION_MODE=3 / VGM_REAL_PHRASE
screen: orange
goal: verify that the Super Hang-On intro tempo improves with the 12.5 MHz
      wait-tick calibration
```

Build sanity check:

```text
tb_mister_vgm_md_top build: passed
warnings: existing JT12/timescale/unique-case warnings
```

Unchanged:

```text
md_sound_module internals
JT12/JT89 sources
AUDIO_L/R and >>> 2 scaling
```


## 2026-06-06: VGM Wait Tick Split from Audio Sample Valid

`REGION_MODE=4 / TIMING_CALIBRATION` was tested on real MiSTer hardware.

Observed result:

```text
expected: 1 second tone
actual: tone was clearly too long
```

This confirmed that using `audio_sample_valid` as the VGM wait progression
source is not suitable on real hardware. `audio_sample_valid` is derived from
JT12's `snd_sample`:

```text
md_sound_module:
  audio_sample_valid = audio_path_enable && jt12_sample
```

That strobe remains useful for audio/debug/dump timing, but VGM wait commands
must advance in VGM's 44100 Hz sample units.

Implementation change:

```text
vgm_region_player:
  old wait source: audio_sample_valid rising edge
  new wait source: vgm_wait_tick rising edge

md_sound_fixed_region_test:
  now passes vgm_wait_tick into vgm_region_player

mister_vgm_md_top:
  generates vgm_wait_tick with a phase accumulator
  default parameters:
    CLK_SYS_HZ  = 50000000
    VGM_WAIT_HZ = 44100
```

The phase accumulator produces an average 44100 Hz tick from the 50 MHz MiSTer
system clock. This avoids using JT12's sample strobe as the VGM tempo source.

For compatibility with earlier direct fixed-region simulation tests,
`tb_md_sound_fixed_region_test.sv` currently drives:

```text
vgm_wait_tick = audio_sample_valid
```

The real MiSTer path uses the dedicated phase-accumulator tick from
`mister_vgm_md_top`.

Mode 4 remains the hardware timing calibration region:

```text
FIXED_REGION_MODE = 4
debug color: lime
pattern: 1 second tone / 1 second silence repeated
wait command: 61 44 AC, 44100 samples
```

Build checks:

```text
TEST_FIXED_TIMING_CALIBRATION_100K build: passed
tb_mister_vgm_md_top build: passed
tb_mister_vgm_md_top run:
  wav_written_samples=5000
  audio_sample_valid_edges=5000
  startup_done=1
  audio_gate_open=1
```

Unchanged:

```text
md_sound_module internals
JT12/JT89 sources
AUDIO_L/R and >>> 2 scaling
```


## 2026-06-06: Region Mode 3 Hardware Timing Issue and Mode 4 Calibration

`REGION_MODE=3 / VGM_REAL_PHRASE` was tested again on real MiSTer hardware
after the source default was switched to mode 3.

Observed result:

```text
screen: orange, confirming REGION_MODE=3
MiSTer menu return: OK
audio: recognizable as the Super Hang-On intro
problem: tempo is slow
problem: some notes appear to be missing
reset behavior: reset repeats the same slow playback
```

This means the mode selection and VGM slice are now correct. The remaining
problem is likely timing, not the fixed ROM selection:

```text
likely suspect:
  VGM wait timing
  audio_sample_valid frequency
  real hardware sample strobe not matching the VGM 44100 Hz sample basis
```

Current wait implementation in `vgm_region_player.sv`:

```text
0x61 ll hh:
  wait_remaining = {hh,ll}

0x62:
  wait_remaining = 735

0x63:
  wait_remaining = 882

0x70-0x7F:
  wait_remaining = (cmd & 0x0F) + 1

wait progress:
  decrement wait_remaining by 1 on audio_sample_valid rising edge
```

Current sample-valid source in `md_sound_module.sv`:

```text
audio_sample_valid = audio_path_enable && jt12_sample
```

So the fixed player currently treats one `jt12_sample` pulse as one VGM sample.
If `jt12_sample` is not exactly 44100 Hz on MiSTer hardware, VGM tempo will be
wrong even though command decoding is correct.

To isolate this, `REGION_MODE=4 / TIMING_CALIBRATION` was added.

Purpose:

```text
play 1 second tone
play 1 second silence
repeat several times
use VGM wait 44100 samples:
  61 44 AC
```

Expected hardware behavior if timing is correct:

```text
tone: about 1.0 second
silence: about 1.0 second
repeat cadence: steady 1s on / 1s off
```

If the one-second sections are clearly too long, the likely fix is to decouple
VGM wait timing from `jt12_sample` and provide a true 44100 Hz wait tick. Two
possible directions:

```text
1. Generate vgm_wait_tick from the MiSTer/audio clock domain at 44100 Hz.

2. Expose a dedicated timing input to vgm_region_player and keep
   audio_sample_valid only for WAV/audio dump synchronization.
```

No sound core internals were changed for this calibration step:

```text
md_sound_module: unchanged
JT12/JT89: unchanged
AUDIO_L/R and >>> 2 scaling: unchanged
```

Hardware selection:

```text
rtl/fixed_region_mode.vh
  FIXED_REGION_MODE = 4
```

Debug color:

```text
REGION_MODE=4 gate-open color: lime
```

Simulation build check:

```sh
iverilog -g2012 -Wall -DSIMULATION -DTEST_FIXED_TIMING_CALIBRATION_100K \
  -s tb_md_sound_fixed_region_test \
  -o /tmp/tb_md_sound_fixed_timing_calibration_100k.vvp \
  tb/tb_md_sound_fixed_region_test.sv \
  rtl/vgm_region_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v
```

Result:

```text
build passed
warnings are the existing JT12/timescale/unique-case warnings
```


## 2026-06-06: Source Default Changed to Region Mode 3

The previous hardware check was expected to use `REGION_MODE=3`, but the real
MiSTer screen was still purple and the audio matched the known `REGION_MODE=2`
sound. That means the build was still selecting mode 2.

Root cause:

```text
rtl/fixed_region_mode.vh still defaulted FIXED_REGION_MODE to 2
```

For the next hardware test, the source-side default was changed:

```text
rtl/fixed_region_mode.vh
  FIXED_REGION_MODE 2 -> 3
```

Confirmed connections:

```text
emu.sv:
  FIXED_REGION_MODE == 3 selects the orange debug color

vgm_region_player.sv:
  REGION_MODE == 3 selects vgm_real_phrase_rom_byte()
```

Unchanged:

```text
AUDIO_L/R and >>> 2 scaling
md_sound_module
JT12/JT89 sources
mister_vgm_md_top
```

Build sanity check:

```sh
iverilog -g2012 -Wall -DSIMULATION \
  -s tb_md_sound_fixed_region_test \
  -o /tmp/tb_md_sound_fixed_region_default_mode3_check.vvp \
  tb/tb_md_sound_fixed_region_test.sv \
  rtl/vgm_region_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v
```

Result:

```text
build passed
warnings are the existing JT12/timescale/unique-case warnings
```


## 2026-06-06: Region Mode 3 Real-VGM Phrase Preparation

After `REGION_MODE=2 / VGM_REAL_SNIPPET` passed on MiSTer hardware, the next
step is to move from a one-shot FM sound to a short real-VGM-derived phrase.

Purpose:

```text
REGION_MODE=3 / VGM_REAL_PHRASE
  longer fixed-ROM phrase
  real VGM-derived YM2612 + PSG command stream
  no PCM/DAC stream for this first phrase pass
  target length: about 2-5 seconds
```

The first mode 3 candidate is derived from `fm_only_test.vgm`:

```text
source VGM: /Users/daizo/Downloads/fm_only_test.vgm
source command_start: 0x00000040
slice end pc: 0x000014AA
copied wait total before suffix: 100220 samples, about 2.27 seconds
body byte count: 5226
ROM byte count including strong silence suffix: 5262
generated include: rtl/vgm_real_phrase_mode3_case.vh
```

Command mix in the copied body:

```text
YM2612 port 0 writes: 1048
YM2612 port 1 writes: 306
SN76489 writes: 22
0x4F Game Gear stereo commands: 2
wait commands: 0x61 and 0x70-0x7F
PCM/DAC stream: not included
unsupported commands: none
```

Mode 3 final silence suffix:

```text
YM2612 all-channel key-off
DAC data zero
DAC off
PSG mute all
44100-sample final wait
0x66 end
```

Implementation notes:

```text
REGION_MODE=0 remains the proven bring-up tone
REGION_MODE=1 remains the smoke snippet
REGION_MODE=2 remains the proven real-VGM snippet
REGION_MODE=3 adds the longer real-VGM phrase
```

The fixed player internal ROM `pc` was widened to 13 bits so the 5262-byte
mode 3 ROM fits. The external `pc_debug` output remains 10 bits. The audio
path was not changed:

```text
AUDIO_L/R and >>> 2 scaling: unchanged
md_sound_module: unchanged
JT12/JT89: unchanged
mister_vgm_md_top: unchanged
```

For hardware identification, `FIXED_REGION_MODE=3` makes the gate-open debug
color orange. The source default was not switched to mode 3 in this step;
mode 3 is first intended for simulation WAV review.

50k simulation command:

```sh
iverilog -g2012 -Wall -DSIMULATION -DTEST_FIXED_VGM_REAL_PHRASE_50K \
  -s tb_md_sound_fixed_region_test \
  -o /tmp/tb_md_sound_fixed_vgm_real_phrase_50k.vvp \
  tb/tb_md_sound_fixed_region_test.sv \
  rtl/vgm_region_player.sv \
  rtl/md_sound_module.sv \
  rtl/genesis_audio/**/*.v

vvp /tmp/tb_md_sound_fixed_vgm_real_phrase_50k.vvp
```

Observed simulation summary:

```text
FIXED_REGION_TEST_START samples=50000 region_mode=3
FIXED_REGION_TEST_DONE wav_written_samples=50000 audio_sample_valid_edges=50000 pc=447 last_cmd=61 busy=1 done=0
```

WAV conversion:

```sh
python3 tools/audio_txt_to_wav/audio_txt_to_wav.py \
  /tmp/md_sound_fixed_vgm_real_phrase_50k.txt \
  /tmp/md_sound_fixed_vgm_real_phrase_50k_gain1.wav \
  --gain 1

python3 tools/audio_txt_to_wav/audio_txt_to_wav.py \
  /tmp/md_sound_fixed_vgm_real_phrase_50k.txt \
  /tmp/md_sound_fixed_vgm_real_phrase_50k_gain2.wav \
  --gain 2
```

WAV outputs:

```text
/tmp/md_sound_fixed_vgm_real_phrase_50k_gain1.wav
/tmp/md_sound_fixed_vgm_real_phrase_50k_gain2.wav
/Users/daizo/Downloads/md_sound_fixed_vgm_real_phrase_50k_gain1.wav
/Users/daizo/Downloads/md_sound_fixed_vgm_real_phrase_50k_gain2.wav
```

Statistics:

```text
gain1:
  frames=50000
  min=-4453
  max=3408
  nonzero=98924
  rms=939.76
  clip_count=0

gain2:
  frames=50000
  min=-8906
  max=6816
  nonzero=98924
  rms=1879.52
  clip_count=0
```

Additional compile checks:

```text
REGION_MODE=2 fixed-region TB build: passed
default fixed-region TB build: passed
warnings: existing JT12/timescale/unique-case warnings
```

Hardware pass conditions for the next step:

```text
screen color: orange when FIXED_REGION_MODE=3 is selected
MiSTer menu return: OK
audio: short real-VGM-derived YM/PSG phrase, not just a one-shot tone
end behavior: all-channel key-off / DAC off / PSG mute reaches silence
```


## 2026-06-06: Region Mode 3 Hardware Pass

`REGION_MODE=3 / VGM_REAL_PHRASE` was tested on real MiSTer hardware.

Observed result:

```text
screen: orange, confirming REGION_MODE=3
MiSTer menu return: OK
audio: real-VGM-derived phrase was recognizable as the Super Hang-On intro
```

Conclusion:

```text
REGION_MODE=3 fixed ROM is active on hardware
the real-VGM-derived YM2612/PSG command stream is valid
JT12/JT89 playback works on real MiSTer hardware
the path is no longer limited to hand-written test tones or a one-shot FM sound
```

This is the first hardware pass where a fixed-ROM real VGM-derived YM/PSG
phrase was played through:

```text
vgm_region_player
  -> md_sound_module
  -> JT12 / JT89
  -> MiSTer AUDIO_L/R
```

No RTL was changed for this note. This records the hardware pass result only.
