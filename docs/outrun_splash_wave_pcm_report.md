# OutRun Splash Wave 0–10 s SegaPCM investigation

This investigation is fixed to the channel Hold feed. Fresh mode is not part
of the comparison. No production RTL was changed and Quartus was not run.

## Start times

The VGM is version 1.51. Its YM2151 and SegaPCM clocks are both 4,000,000 Hz;
the SegaPCM update rate is therefore 31,250 Hz. The SegaPCM interface word is
`0x0000000c` (bank shift 12 and default mask `0x70`).

| chip/event | VGM sample | time | file offset | detail |
|---|---:|---:|---:|---|
| YM2151 first write | 0 | 0.000000000 s | `0x00eaec` | reg `01` = `00` |
| YM2151 first key-on | 83 | 0.001882086 s | `0x00eb76` | reg `08` = `78` |
| SegaPCM first C0 setup write | 730 | 0.016553288 s | `0x00eecc` | ch1 offset `00` = `00` |
| SegaPCM first enabled voice | 733 | 0.016621315 s | `0x00eef3` | ch1 control = `c2` |

Other enabled voices in the first ten seconds begin at ch3 0.017075 s
(volume is initially zero; audible setup at 0.106961 s), ch5 0.017619 s, ch7
0.027098 s, ch9 0.107596 s, and ch11 0.410816 s. There are 1,777 C0 writes
in the interval.

## First PCM voice

The first ch1 initialization is sequential and complete before enable:

| time | file offset | C0 address | write | resulting relevant value |
|---:|---:|---:|---|---|
| 0.016553288 | `00eecc` | `0008` | scratch = `00` | scratch `00` |
| 0.016553288 | `00eed0` | `000a` | volume L = `27` | L/R `27/ff` |
| 0.016575964 | `00eed5` | `000b` | volume R = `28` | L/R `27/28` |
| 0.016575964 | `00eed9` | `000c` | loop low = `e6` | loop `ffe6` |
| 0.016575964 | `00eedd` | `008c` | current mid = `e6` | current `ffe600` |
| 0.016598639 | `00eee2` | `000d` | loop high = `3b` | loop `3be6` |
| 0.016598639 | `00eee6` | `008d` | current high = `3b` | current `3be600` |
| 0.016598639 | `00eeea` | `000e` | end = `7f` | end `7f` |
| 0.016621315 | `00eeef` | `000f` | delta = `90` | delta `90` |
| 0.016621315 | `00eef3` | `008e` | control = `c2` | enabled, non-loop |

Final reference state:

| item | value |
|---|---:|
| channel | 1 |
| current | `3be600` (16.8) |
| loop | `3be6` |
| end | `7f` |
| delta | `90` |
| volume L/R | `27/28` |
| raw control | `c2` |
| bank | `(c2 & 70) << 12 = 40000` |
| full first ROM address | `40000 | 3be6 = 43be6` |
| type80 block / payload index | block 3 / `02d09` |
| first ROM bytes | `7f 85 82 7b 85 89 74 77 ...` |

Block 3 starts at ROM destination `0x43be6`, has length `0x441a`, and ends at
`0x48000`. Thus the intended first address is exactly the start of a loaded
payload block.

## Hold-path cycle trace

The current wrapper converts a control write as
`{0, raw[5:3], 0, raw[2:0]}`. For raw `c2`, this becomes `02`. JT then takes
`cfg_en[6:4]` as its three-bit bank, so the first JT ROM request is `03be6`,
not `43be6`.

The diagnostic TB uses the real JT FSM and the production Hold/range rules.
TB time is local to the reduced test and is not VGM time:

```
TRACE request t=3475000 ch=1 st=9 addr=03be6 match=0 fifo_push=0
TRACE consume t=3725000 ch=1 st=14 hold_valid=0 hold=80 jt_data=80 jt_ok=0 mul=0
TRACE request t=16275000 ch=1 st=9 addr=03be6 match=0 fifo_push=0
TRACE consume t=16525000 ch=1 st=14 hold_valid=0 hold=80 jt_data=80 jt_ok=0 mul=0
SUMMARY request=2 fifo_push=0 fifo_pop=0 ddr_accept=0 ddr_response=0
        hold_update=0 consume=2 mixer_nonzero=0 audio_nonzero=0
```

The request is issued in JT state 8; because `rom_cs` is registered, the
wrapper's edge detector observes it while the displayed state has advanced to
9. The first loss is unambiguously the payload range qualification/FIFO push,
before DDR issue or response ownership:

```
C0 control c2
  -> wrapper control 02
  -> JT bank 0, request 03be6
  -> no type80 block match
  -> FIFO push 0
  -> DDR issue/accept/response 0
  -> ch1 hold remains invalid/80
  -> JT state14 consumes 80
  -> mixer 0
  -> audio contribution 0
```

## Galaxy Force comparison

| item | OutRun Splash Wave | Galaxy Force Try-Z slap |
|---|---:|---:|
| VGM SegaPCM interface | `0000000c` | `00f8000d` |
| bank rule | mask `70`, shift 12 | mask `f8`, shift 13 |
| raw control | `c2` | `8a` |
| enable / loop-disable bits | `10b` | `10b` |
| current | `3be600` | `d10042` |
| end | `7f` | `e1` |
| delta | `90` | `85` |
| correct full ROM address | `043be6` | `11d100` |
| JT-visible 19-bit address needed | `43be6` | `1d100` |
| type80 block / payload index | block 3 / `02d09` | block 8 / `14b00` |
| current wrapper result | `03be6` (miss) | `1d100` (hit) |

Galaxy Force happens to fit the current repacking: raw `8a[5:3]` is bank 1,
which is the low-19-bit bank of full address `11d100`. OutRun requires bank 4
from raw bit 6, but that bit is forced to zero by the wrapper. The JT core can
represent bank 4; the failure is in adapting the VGM interface/control format
to JT, not in its three-bit bank field.

## Ranked cause assessment

1. **Confirmed: the VGM SegaPCM interface/bank layout is not applied to the
   JT control conversion.** This changes every relevant OutRun request by
   `0x40000` and makes it miss all loaded payloads.
2. **Confirmed consequence: payload selection rejects the bad request before
   FIFO insertion.** Ownership, response tagging, and channel Hold logic never
   get a transaction to process.
3. **Control enable/loop semantics are not the fault.** Both `c2` and Galaxy
   Force `8a` have enable=0 and loop-disable=1; only their bank-bearing bits
   differ.
4. **Current initialization is not the fault for the first voice.** Current,
   loop, end, delta, and volume are all written while the voice is disabled,
   and control is written last.
5. **A JT OutRun-only playback assumption is unlikely.** JT's bank field is
   wide enough for bank 4 and its sample rate comment matches 4 MHz / 128. The
   observed failure precedes sample consumption and mixing.

The complete chronological C0 table is `docs/outrun_splash_wave_0_10_c0.csv`.
The diagnostic is `tb/tb_jtoutrun_pcm_outrun_bank_trace.sv`.
