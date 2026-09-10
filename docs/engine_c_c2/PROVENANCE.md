# Engine C C2 source and license provenance

Local lab work only. **This audit does not establish permission to publish or
distribute the combined SID source/RBF.** No SID RBF has been built or published.

## Fixed inputs

- C1 base: `e7b479d029578a7196779e6aba11a3271e0f9bc2`.
- SID source: [C64_MiSTer, fe6dfe53](https://github.com/MiSTer-devel/C64_MiSTer/tree/fe6dfe53c99122e5a088691f2d358d6caba61de1/rtl/sid).
- Golden Shell source: local repository commit
  `744d51ac6950b617004ad1ce9c83472a878a485c` (v1.1 audio ABI/upload shell files
  retained in the Phase 1B tree).
- C0/C1 codecs, converter, formats, and existing production source files are
  unchanged. No SIDsynth source or third-party SID music is imported.

`rtl/engine_c_c2/vendor/upstream/` contains byte-exact copies of all seven files
in the pinned `rtl/sid` dependency directory. SHA-256 values are locked in
`tools/engine_c_c2/source_lock.json`; `audit.py --upstream PATH` compares them
against `git show <fixed commit>:rtl/sid/<file>`, not a moving branch.

Only `vendor/lab/*.sv` enters the lab QIP. `vendor/upstream/sid.qip` is a
provenance record and is never sourced by the lab project.

## SID module tree (DUAL=0)

```text
sid_session_wrapper
└─ sid_top (DUAL=0, MULTI_FILTERS=1)
   ├─ chip[0].v1/v2/v3 : sid_voice (three instances)
   │  ├─ sid_envelope
   │  ├─ sid_dac BITS=12 (waveform)
   │  └─ sid_dac BITS=8  (envelope)
   ├─ sid_tables (embedded waveform/filter ROM arrays)
   │  └─ sid_dac BITS=11 (cutoff DAC)
   └─ sid_filter (shared time-multiplexed pipeline)
```

There are no external waveform ROM files. Both 6581/8580 tables and arithmetic
remain present; C2's parser admits only PAL/6581 artifacts for execution.

## License evidence, not a blanket license conclusion

| File | Evidence at the pinned commit | Outstanding issue |
| --- | --- | --- |
| `sid_filter.sv` | CERN-OHL-S v2 notice; Alexey Melnikov 2022, based on reDIP-SID by Dag Lem 2022 | Review combined-work/source obligations before distribution |
| `sid_dac.sv` | CERN-OHL-S v2 notice; Dag Lem 2022; references reSID documentation/code | Preserve notice; review transitive provenance/obligations |
| `sid_top.sv` | No file-local license notice | Permission/license chain unresolved |
| `sid_voice.sv` | No file-local license notice | Permission/license chain unresolved |
| `sid_envelope.sv` | No file-local license notice | Permission/license chain unresolved |
| `sid_tables.sv` | No file-local license notice; embedded measured/model tables | Table-data provenance and permission unresolved |
| `sid.qip` | No file-local license notice | Do not infer license from GitHub availability |

The pinned checkout has no root LICENSE/COPYING supplying an obvious blanket
license for these unannotated files. GitHub hosting and the MiSTer organization
name are not evidence of a redistribution license. All upstream notices are
retained. The new lab glue is marked GPL-2.0-or-later; that does **not** relicense
the imported SID implementation or settle compatibility with CERN-OHL-S v2.

## Exact local SID changes

Compare `vendor/upstream` to `vendor/lab` to obtain the complete patch. No
frequency/envelope/filter/compressor/DAC formula, ROM value, or 6581/8580
selection formula is changed.

1. Add synchronous reset to missing per-session state (see RESET_AUDIT.md).
2. Add a one-shot output-publication token/pulse to `sid_top`; preserve the
   original audio result assignments and their state-8/state-15 timing.
3. Change top's procedural waveform-feedback arrays from `wire` to `reg`.
4. Guard unused single-SID lookup slots 7/9/11 against out-of-range reads.
   The state-7 voice-3 result still commits using the old `v=2`; only the unused
   next lookup is suppressed. DUAL logic and tables are not simplified.
5. Replace `wire` by `input` in six function formal argument declarations:
   standard SystemVerilog syntax accepted by Verilator. Function bodies are
   unchanged.
6. `sid_dac.sv` is byte-identical in both directories.

The source retains upstream width/unused-pin/inactive-parameter-branch warnings.
In particular sid_dac's constant BITS branches reference indexes outside the
other BITS variants; the selected live branch is unchanged. Open-source lint
uses `-Wno-fatal`, records warnings, and does not represent a clean Quartus
timing/synthesis result.

## Golden Shell import/adaptation

Versioned copies under `rtl/engine_c_c2/shell/` avoid modifying the original
production `emu.sv`, top, or upload backend.

- `golden_player_shell_upload.sv`: byte-exact Golden Shell upload adapter.
- `mister_vgm_md_top_v1_1.sv`: copied compatibility shim; C2 adds lab done/error
  publication and exact index-1 download qualification at both profile/upload
  boundaries. Index-2 is inert, not a C2 transition-command implementation.
- `emu_c2.sv`: copied shell with only OSD core/file labels changed (`MVG`).
- `c2_profile.sv`: new lab audio/read adapter.
- Device/pin/platform/QIP/SDC assignments come from the Golden Shell audio-lab
  project. The C2 QSF drops irrelevant sound-engine/debug macros, retains the
  20 MHz PLL and platform assignments, and uses a complete C2 source list.
  An absent legacy `jtag.cdf` assignment is omitted; no production QSF is edited.

This is the minimal physical-upload/audio bring-up boundary, **not** a claim
that C2 implements the production v1.3 status/session/fade ABI. That transport
adaptation belongs to a subsequent phase, before any Profile C registration.
