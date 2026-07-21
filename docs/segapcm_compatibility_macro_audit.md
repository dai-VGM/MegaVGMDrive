# SegaPCM normal-DDR compatibility macro audit

This audit describes the active `VGM_MD_MiSTer.qsf` compatibility build and
the real-payload `tb_segapcm_backend_ab` comparison.  Line numbers refer to
the workspace revision containing the compile-time build signature.

## Result

Three legacy-named macros are currently functional dependencies, not debug
visibility switches:

- `MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD` selects the corrected JT C0
  instance, synchronous RAM/CEN schedule, current writeback arbitration,
  prefetch/generation path, and the experimental YM2151+SegaPCM top mix.
- `MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST` compiles the control/source ports used by
  that C0 instance and changes CPU/ROM/audio-valid routing.
- `MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST` compiles the normal-DDR payload
  copy/read ports and the mapper/FIFO/owner/response/prefetch path.

Removing any of these three is therefore a functional RTL change.  The clean
compatibility QSF keeps them until the functionality is renamed or moved
behind a non-debug feature guard.

The following experiment-only start/timing macros are removed from the clean
QSF:

- `MEGAVGMDRIVE_SEGAPCM_SMOKE_PARSER_RUN_TEST`
- `MEGAVGMDRIVE_SEGAPCM_C0DRIVE_TICK_SLOW`
- `MEGAVGMDRIVE_START_HOLD_NO_BUSY_CLEAR`
- `MEGAVGMDRIVE_DIRECT_PLAYER_START_DEBUG`

`MEGAVGMDRIVE_SEGAPCM_USE_C0_LAB_BACKEND` remains undefined, so the top-level
generate branch elaborates `vgm_ddram_backend`, not `vgm_c0_lab_backend`.

## Functional effect by macro

| Macro | Functional effect | Classification |
|---|---|---|
| `C0_ONLY_DEBUG_BUILD` | Defines the audio-stub/JT51-lab top mode; fixes the OSD C0/JT selection; selects the corrected JT instance, C0 decode/write queue, sync RAM schedule, request mapper, FIFO/owner, per-channel prefetch/generation, and JT output as the SegaPCM source. | C0 decode, ROM request, response/prefetch, JT CEN/RAM, audio output/mixer, debug |
| `SMOKE_TEST` | Adds the loaded-source controls, changes `core_cpu_cs`, ROM source/mapping branches, `raw_audio_sample_valid`, and enables the parser-run selector when requested.  Forced-smoke logic is compiled but is inactive in ordinary JT playback. | C0/ROM routing, audio-valid, optional player start, debug |
| `SMOKE_LOADED_DDR_TEST` | Adds payload tap/read ports to player, backend, top, wrapper and JT; compiles cumulative type80 mapping, DDR request/response, FIFO/owner, gap response and prefetch plumbing.  It does not choose LAB versus DDR. | DDR response feed, sample prefetch/generation, payload copy/read, debug |
| `MIN_DEBUG_PROBE` | Removes/reduces large observation arrays and selects a smaller overlay view. | Debug visibility only |
| `SMOKE_PARSER_RUN_TEST` | Selects the smoke parser start hold and its reduced loaded-player reset instead of the ordinary play-ready/start/reset handoff. | Player start/play-ready/reset |
| `AB1_MAME_SCRATCH` | Sets `MAME_SCRATCH_CURRENT=1`; C0 offset 0 stays scratch and is not current fraction. | JT C0/current semantics |
| `AB2_MAME_NONLOOP_END` | Sets `MAME_NONLOOP_END=1`; non-loop end compares against `end`, not `end+1`. | JT end semantics |
| `C0DRIVE_TICK_SLOW` | Changes only forced-C0 smoke `SMOKE_C0_TICK_RELOAD` to 15.  It does not alter the normal fractional `segapcm_cen`. | Forced-smoke PCM tick only |
| `START_HOLD_NO_BUSY_CLEAR` | Prevents the normal start hold from clearing on `player_busy`/load-session conditions. | Player start handoff |
| `DIRECT_PLAYER_START_DEBUG` | Bypasses the normal armed/started handoff and drives the loaded-player start from file-ready hold. | Player start handoff |
| `MODE5_DEBUG_OVERLAY_ALWAYS_ON` | Forces overlay visibility. | Debug visibility only |
| `USE_C0_LAB_BACKEND` | Compile-time branch selecting `vgm_c0_lab_backend`; undefined selects `vgm_ddram_backend`. | Backend selection |

The JT reset expression itself remains `reset | mode5_sound_core_reset` in the
clean build.  `SMOKE_PARSER_RUN_TEST` used to alter `mode5_loaded_player_reset`,
not the `jtoutrun_pcm` reset port directly.

## Previous A/B TB versus pre-audit QSF

The previous common A/B compile command used:

```text
SIMULATION
MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD
MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST
MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST
MEGAVGMDRIVE_SEGAPCM_AB1_MAME_SCRATCH
MEGAVGMDRIVE_SEGAPCM_AB2_MAME_NONLOOP_END
```

The LAB pass additionally used `AB_LAB_BACKEND`; the DDR pass did not.  The TB
instantiates each backend directly, so `AB_LAB_BACKEND` is a TB selector and
is not the top-level `MEGAVGMDRIVE_SEGAPCM_USE_C0_LAB_BACKEND` macro.

| Set | Defines |
|---|---|
| Both previous A/B and pre-audit QSF | `C0_ONLY_DEBUG_BUILD`, `SMOKE_TEST`, `SMOKE_LOADED_DDR_TEST`, `AB1_MAME_SCRATCH`, `AB2_MAME_NONLOOP_END` |
| Previous A/B only | `SIMULATION`; `AB_LAB_BACKEND` in the LAB pass |
| Pre-audit QSF only | `MISTER_FB=1`, `FIXED_REGION_MODE=5`, `MODE5_VGM_BACKEND=1`, `MODE5_VGM_ADDR_WIDTH=23`, `MIN_DEBUG_PROBE`, `SMOKE_PARSER_RUN_TEST`, `C0DRIVE_TICK_SLOW`, `START_HOLD_NO_BUSY_CLEAR`, `DIRECT_PLAYER_START_DEBUG`, `MODE5_DEBUG_OVERLAY_ALWAYS_ON` |
| Disabled in the previous DDR A/B and QSF | `USE_C0_LAB_BACKEND` |

Therefore the earlier A/B comparison proved the backend boundary below the
wrapper, but did not reproduce the QSF-only player-start/tick macros.  The
clean rerun passes the complete clean QSF define list to Icarus, plus only
`SIMULATION` and the TB's `AB_LAB_BACKEND` selector where appropriate.

## Clean compatibility QSF block

Active SegaPCM-related defines are:

```text
MISTER_FB=1
FIXED_REGION_MODE=5
MODE5_VGM_BACKEND=1
MODE5_VGM_ADDR_WIDTH=23
MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD=1
MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST=1
MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST=1
MEGAVGMDRIVE_SEGAPCM_MIN_DEBUG_PROBE=1
MEGAVGMDRIVE_SEGAPCM_AB1_MAME_SCRATCH=1
MEGAVGMDRIVE_SEGAPCM_AB2_MAME_NONLOOP_END=1
MODE5_DEBUG_OVERLAY_ALWAYS_ON=1
```

The four start/tick experiment macros listed in the Result section are
commented out.  The C0 LAB backend macro is also commented out.

## Compile-time overlay signature

The last overlay row displays `BS=xxxx PF=xx D/L`.

```text
BS[15:8] = prefetch/consume contract revision
BS[7]    = START_HOLD
BS[6]    = DIRECT_START
BS[5]    = TICK_SLOW
BS[4]    = PARSER_RUN
BS[3]    = LOADED_DDR_SMOKE
BS[2]    = SMOKE
BS[1]    = C0_ONLY
BS[0]    = LAB backend
```

The clean normal-DDR QSF must display:

```text
BS=010E PF=01 D
```

Every bit is derived directly from a compile-time `ifdef`; no runtime signal
is used.

The pre-audit QSF macro set reports `BS=01FE PF=01 D`; this makes a stale RBF
immediately distinguishable from the clean `BS=010E` build.

## Clean compatibility simulation

Both A/B compiles used the complete active clean-QSF define list above.  The
only additional defines were `SIMULATION`, and `AB_LAB_BACKEND` for the LAB
pass.  `SMOKE_PARSER_RUN_TEST`, `C0DRIVE_TICK_SLOW`,
`START_HOLD_NO_BUSY_CLEAR`, and `DIRECT_PLAYER_START_DEBUG` were absent.

Splash Wave 0--2 s used 10 type80 blocks, 59,862 payload bytes and 390 C0
events.  Results:

```text
                         LAB       normal DDR
consume slots            282586    282586
PCM output events         62922     62922
interval minimum          256       256 SYS cycles
interval maximum          257       257 SYS cycles
interval average          256.000   256.000 SYS cycles
interval histogram        256:62920, 257:1 (both)
stale generation          0         0
wrong channel             0         0
wrong address             0         0
final FIFO backlog        0         0
```

Slot-normalized comparison found no difference in all 282,586 rows for:

```text
channel/current/control/delta/address/generation
response byte/valid
consume byte
multiply and per-channel contribution
accumulator before/after
JT snd_left/snd_right and JT output valid
wrapper PCM L/R
top PCM contribution L/R
```

The first four consume bytes are `7F 7F 85 85` in both builds.  Physical
response arrival is 7--14 SYS cycles later in the DDR build (7 cycles for
282,567 of 282,586 slots), but every consume cycle is identical.  The complete
62,922-row output CSVs are byte-for-byte identical.

The ordinary start path, with all four start/tick experiment macros removed,
also passes:

```text
PASS tb_mode5_ddram_header_start core=fd9a magic=206d6756
PASS tb_mode5_start_hold_fallback debug=0c30
```

An Icarus compilation-unit signature check produced:

```text
SEGAPCM_BUILD_SIGNATURE=010e PREFETCH=01 LAB=0
```

## Complete conditional-directive location catalogue

- `MEGAVGMDRIVE_SEGAPCM_C0_ONLY_DEBUG_BUILD`
  - `rtl/segapcm_sound_module.sv`: 331, 1387, 1912, 2120, 3044, 3141, 7207, 7534, 7663, 7681, 7915, 7929, 7945, 7954, 7963, 7973, 7982, 7990, 7999, 8020, 8057, 8064, 8071, 8101, 8122, 8128, 8134, 8140, 8146, 8152, 8158, 8164, 8170, 8176, 8182, 8188, 8197, 8253, 8257, 8281, 8286, 8291, 8297, 8311, 8340, 10992, 11361, 11672, 11715, 11908, 11932, 12243, 12247, 12358, 12563, 12567, 13210, 13216, 13255, 13439, 13456, 13506, 13530, 13779, 13793, 13816, 13908, 13927, 14111, 14385, 14969, 15009
  - `rtl/vgm_loaded_player.sv`: 208, 482, 3294, 3389
  - `rtl/mister_vgm_md_top.sv`: 554
  - `rtl/emu.sv`: 334, 706, 1375, 1399, 1406, 1424, 1429, 1434, 1447, 1476, 2425, 2504, 2541, 2715, 2721, 2732, 2743, 2754, 2769, 2784, 2795, 2810, 2825, 2836, 2842, 2848, 2854, 2860, 2866, 2872, 2878, 2884, 2890, 2896, 2902, 2917, 2932, 2947, 2953, 2964, 2970, 2976, 2987, 2993, 2999, 3015, 3588, 3681
  - `third_party/jtcores/cores/outrun/hdl/jtoutrun_pcm.v`: 225, 239, 432, 616, 896, 912, 977, 1004, 1103, 1183, 1211, 1221, 1230, 1270, 1313, 1374, 1533, 1719, 1916, 2064, 2073, 2084, 2094, 2159, 2186, 2201, 2227, 2245, 2257, 2270, 2517, 2528, 2609, 2631, 2686, 2746, 2828, 2983, 3017, 3098, 3112, 3121, 3128, 3137, 3155, 3169, 3178, 3185, 3197, 3218, 3232, 3241, 3248, 3258, 3266, 3279, 3290, 3301, 3312, 3320, 3383, 3402, 3542
- `MEGAVGMDRIVE_SEGAPCM_SMOKE_TEST`
  - `rtl/segapcm_sound_module.sv`: 82, 1169, 7194, 7206, 7247, 7458, 7469, 7485, 7502, 7532, 7560, 7572, 7591, 7608, 7641, 7679, 7716, 7806, 7823, 7848, 7886, 10925, 11306, 13269, 14371, 14399, 14826
  - `rtl/vgm_loaded_player.sv`: 206
  - `rtl/mister_vgm_md_top.sv`: 92, 1258, 1874, 1924, 1944, 2958, 3343, 3987
  - `rtl/emu.sv`: 339, 704, 1370, 1528, 1682, 2347, 2724, 2735, 2746, 2757, 2772, 2787, 2798, 2813, 2905, 2920, 2935, 2956, 2979, 3278, 3290, 3308, 3315, 3322, 3331, 3353
  - `third_party/jtcores/cores/outrun/hdl/jtoutrun_pcm.v`: 52, 645, 913, 947, 981, 1005, 1406, 1726, 1994, 2061, 2099, 2112, 2171, 2234, 2273, 2302, 2344, 2361, 2415, 2430, 2464, 2475, 2496, 2560, 2636, 2765, 3000, 3009, 3274, 3296, 3373, 3388, 3500
- `MEGAVGMDRIVE_SEGAPCM_SMOKE_LOADED_DDR_TEST`
  - `rtl/segapcm_sound_module.sv`: 93, 1090, 1186, 1199, 1207, 2032, 3061, 5159, 7470, 7503, 7561, 7574, 7592, 7609, 7642, 7656, 7661, 7672, 7680, 7693, 7698, 7717, 7747, 7772, 7807, 7824, 7837, 7849, 7879, 7887, 7897, 7913, 8100, 8196, 8341, 11278, 11343, 12248, 13270, 14401, 14618, 14828, 15016
  - `rtl/vgm_loaded_player.sv`: 207
  - `rtl/mister_vgm_md_top.sv`: 96, 273, 914, 1261, 3408, 3511, 3615, 3695, 3992, 4524
  - `rtl/emu.sv`: 344, 705, 870, 1371, 1618, 1686, 1855
  - `rtl/vgm_ddram_backend.sv`: 54, 154, 188, 273, 309, 325, 342, 378, 642, 656, 716, 745, 759, 824, 882, 907, 912, 921, 927, 933, 938, 977, 1041, 1084, 1114, 1134, 1155
  - `third_party/jtcores/cores/outrun/hdl/jtoutrun_pcm.v`: 54, 650, 722, 867, 874, 892, 914, 982, 1006, 1042, 1407, 1727, 1995, 2062, 2174, 2237, 2305, 2347, 2362, 2416, 2431, 2476, 2497, 2561, 2637, 3001, 3010, 3284, 3306, 3374, 3503, 3584
- `MEGAVGMDRIVE_SEGAPCM_MIN_DEBUG_PROBE`
  - `rtl/segapcm_sound_module.sv`: 1532, 1567, 1599, 13360, 13385, 13406, 13537
  - `rtl/emu.sv`: 2546, 3053
- `MEGAVGMDRIVE_SEGAPCM_SMOKE_PARSER_RUN_TEST`
  - `rtl/mister_vgm_md_top.sv`: 621
  - `rtl/emu.sv`: 349 (signature only)
- `MEGAVGMDRIVE_SEGAPCM_AB1_MAME_SCRATCH`
  - `third_party/jtcores/cores/outrun/hdl/jtoutrun_pcm.v`: 28
- `MEGAVGMDRIVE_SEGAPCM_AB2_MAME_NONLOOP_END`
  - `third_party/jtcores/cores/outrun/hdl/jtoutrun_pcm.v`: 33
- `MEGAVGMDRIVE_SEGAPCM_C0DRIVE_TICK_SLOW`
  - `third_party/jtcores/cores/outrun/hdl/jtoutrun_pcm.v`: 691
  - `rtl/emu.sv`: 354 (signature only)
- `MEGAVGMDRIVE_START_HOLD_NO_BUSY_CLEAR`
  - `rtl/mister_vgm_md_top.sv`: 611
  - `rtl/emu.sv`: 364 (signature only)
- `MEGAVGMDRIVE_DIRECT_PLAYER_START_DEBUG`
  - `rtl/mister_vgm_md_top.sv`: 616
  - `rtl/emu.sv`: 359 (signature only)
- `MODE5_DEBUG_OVERLAY_ALWAYS_ON`
  - `rtl/emu.sv`: 318
- `MEGAVGMDRIVE_SEGAPCM_USE_C0_LAB_BACKEND`
  - `rtl/mister_vgm_md_top.sv`: 3462
  - `rtl/emu.sv`: 329 (signature only)
