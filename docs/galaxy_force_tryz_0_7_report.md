# Galaxy Force II Try-Z 0–7 s SegaPCM comparison

No production RTL was changed for this investigation. The input is
`08 Try-Z (Scene E - Level 5).vgm`; its SegaPCM clock is 4,026,987 Hz, so the
oracle update rate is 31,460.8359375 Hz.

## Event extraction

The interval contains 946 C0 writes. The complete chronological register
state is in `galaxy_force_tryz_0_7_c0.csv`. Active channels are ch0 and ch2–6;
ch0 is the repeating slap-bass voice.

| generation | control time (s) | current | end | delta | L/R | control | ROM |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 2.305057 | D10042 | E1 | 85 | 26/26 | 8A | 11D100 |
| 2 | 2.407800 | E20043 | ED | 85 | 2C/2C | 8A | 11E200 |
| 3 | 2.510726 | 3A0046 | 3B | A6 | 39/39 | 8A | 113A00 |
| 4 | 2.613469 | 84003F | A4 | 85 | 26/26 | 8A | 118400 |
| 5 | 2.716689 | A50040 | BA | 85 | 2C/2C | 8A | 11A500 |
| 6 | 2.819433 | 3A0046 | 3B | A6 | 39/39 | 8A | 113A00 |
| 7 | 2.922517 | BB0041 | D0 | 75 | 26/26 | 8A | 11BB00 |
| 8 | 3.025238 | EE0044 | FC | 75 | 2C/2C | 8A | 11EE00 |
| 9 | 3.128345 | 84003F | A4 | 75 | 26/26 | 8A | 118400 |
| 10 | 3.230862 | A50040 | BA | 75 | 2C/2C | 8A | 11A500 |
| 11 | 5.598254 | D10042 | E1 | 8B | 26/26 | 8A | 11D100 |
| 12 | 5.700975 | E20043 | ED | 8A | 2C/2C | 8A | 11E200 |
| 13 | 5.803923 | 3A0046 | 3B | B0 | 39/39 | 8A | 113A00 |
| 14 | 5.906644 | 84003F | A4 | 8A | 26/26 | 8A | 118400 |
| 15 | 6.009864 | A50040 | BA | 8A | 2C/2C | 8A | 11A500 |
| 16 | 6.112608 | 3A0046 | 3B | B0 | 39/39 | 8A | 113A00 |
| 17 | 6.215692 | BB0041 | D0 | 7D | 26/26 | 8A | 11BB00 |
| 18 | 6.318435 | EE0044 | FC | 7D | 2C/2C | 8A | 11EE00 |
| 19 | 6.421519 | 84003F | A4 | 7D | 26/26 | 8A | 118400 |
| 20 | 6.524036 | A50040 | BA | 7D | 2C/2C | 8A | 11A500 |

## Oracle and JT comparison

The MAME/libvgm-style oracle applies each C0 write at its VGM time; control is
not treated as an atomic commit. With both MAME A/B options enabled, the
frame-level Hold model's ch0 requested ROM addresses agree with the oracle.
The first remaining consume difference
is at 2.305533144 s (PCM frame 72534): the oracle uses request/address
`11D107` (`7C`), while JT consumes the preceding held request/address
`11D106` (`80`).

This is a fixed one-update pipeline offset. At every later current-generation
boundary exactly one sample from the old generation is consumed, followed by
samples from the new generation. It does not accumulate and it does not remove
the note tail. For example generation 3 stops at 2.523232382 s in both oracle
and the combined A/B model, with 394 non-neutral frames in both. Across ch0,
the oracle and combined model both produce 68,757 non-neutral contributions;
the last differs only by one update (6.873021443 vs 6.873053228 s).

The 0–7 s final-mix comparison also finds no downstream loss: no nonzero ch0
contribution is suppressed by the final mix, and no final-mix clip occurs.
Oracle/JT final CRCs differ because of the one-update offset and JT's per-voice
12-bit `clipDAC`, not because the tail disappears.

| ch | oracle non-neutral / CRC | combined-A/B JT non-neutral / CRC |
|---:|---:|---:|
| 0 | 68,757 / 513414cf | 68,757 / 55c87586 |
| 2 | 193,177 / 96e20827 | 193,176 / 200cf45c |
| 3 | 133,220 / 88dd9298 | 133,220 / 29ad29c1 |
| 4 | 218,935 / c15d3511 | 218,934 / a0debb56 |
| 5 | 85,404 / 4f01af36 | 85,403 / 640b5441 |
| 6 | 196,719 / 70fa705b | 196,718 / 6ec4eef1 |

The one-frame count differences are confined to initial pipeline alignment;
ch0, including every slap generation, has no count reduction at all. Final-mix
CRC is `9ba770a0` for the oracle and `03f2ae32` for combined-A/B JT.

## Hold-only real-JT result

The minimal real-JT test uses the first two slap generations, real type-0x80
bytes, six active voices, the 32-entry FIFO, one response owner, channel holds,
and 50 system clocks of DDR latency. It is fixed to Hold mode.

| request | DDR response | ch0 consume | non-neutral consume | dropped/overflow |
|---:|---:|---:|---:|---:|
| 19,461 | 19,461 | 3,244 | 3,206 | 0/0 |

Generation 1 produces 3,232 final JT sample strobes and 3,196 nonzero outputs.
Its first and last nonzero samples map to approximately 2.305570 and 2.407761 s,
so the output remains present for 102.19 ms, through the next retrigger. The
oracle gives 3,197 non-neutral samples from 2.305533 through 2.407755 s. The
only duration loss is one 31.8 us update.

The first-note absolute stereo energy is 8,933,080 in the oracle and 8,410,160
after JT's 12-bit per-voice clip. In the final 50 ms, it is 4,219,940 versus
4,107,786 (97.3% retained). Thus clipping changes peaks and CRC but does not
remove the audible tail.

At the second boundary, Hold consumes old-generation `B6` exactly once and
then new-generation bytes `82,82,83,83,85,85,89`. The delay is fixed and does
not accumulate.

The cycle-accurate JT trace does expose a separate phase difference while the
C0 current pair is written sequentially. The first generation-2 request is
`1E201` with current `E201A5`; the frame-level oracle begins around `E2009B`.
The difference is exactly two old-delta advances (`2 * 0x85 = 0x10A`). A ch0
update occurs between the current-mid and current-high writes, so the
intermediate register image is played and written back before the pair is
complete. This shifts the address phase but shortens a note by at most a few
PCM updates; it does not account for a roughly 100 ms tail disappearing.

Consequently the current Hold-only TB does **not** reproduce `ベロン→ベッ`.
The verified Hold path retains the tail through JT consume, channel mix, and
final JT sample strobe. The first intrinsic differences are the partial-write
phase and 12-bit clipping, neither of which produces the reported mute.

## Reproduction

The diagnostic test is `tb/tb_jtoutrun_pcm_tryz_generation.sv`; ROM data is
`tb/data/galaxy_force_tryz_ch0_first_two.memh`. Compile with `TRYZ_HOLD_ONLY`
for the focused trace. The test contains all four scratch/end A/B
instantiations when the define is omitted.

No Galaxy Force-specific production behavior or atomic commit was added.
