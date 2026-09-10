# C2 reset and audio-publication proof boundary

## Stateful inventory

| Owner | State | C2 treatment |
| --- | --- | --- |
| `sid_top` register file | Three voices' frequency, PW, control, AD/SR; filter cutoff, resonance/routing, mode/volume | Existing reset retained |
| `sid_top` bus/config staging | bus_data, Fc_offset | Explicit reset added |
| `sid_top` waveform lookup pipeline | state, v, f_acc_t and four feedback arrays per voice | Explicit reset added; state starts at idle 15 |
| `sid_top` output | local audio0 and audio array | Explicit reset added |
| `sid_top` publication | publish_pending, sample_pulse | Reset zero; one token per CE, consumed only on completed output commit |
| `sid_voice` oscillator | oscillator, previous sync MSB, test_delay | Unconditional SYS-clock reset instead of requiring a coincident CE |
| `sid_voice` waveform/noise | saw_tri, pulse, noise, osc_edge, LFSR, noise_age | Existing reset retained; missing local clk/clk_d reset added |
| `sid_voice` waveform output | norm_dac, wave_out | Explicit reset added |
| `sid_voice` floating DAC/envelope product | keep_cnt, env_dac, dac_out, dca_out | Explicit reset added |
| `sid_envelope` | FSM, gate edge, rate counter, exponential counter/period, envelope, hold_zero | Existing resets retained; reset gate_edge is zero, not old gate |
| `sid_tables` | Four registered waveform outputs, f0, f0_adj | Explicit reset added |
| `sid_tables` table contents | Initialized waveform/filter ROMs | Not session state; cfg fixed, loader write permanently disabled |
| `sid_dac` | Initialized DAC coefficients/bit values, combinational network | Constants, not session history; unchanged |
| `sid_filter` integrators | vlp/vlp2, vbp/vbp2, vhp/vhp2 | Reset port and clears added |
| `sid_filter` MAC/input/compressor pipeline | c,s,a,b,vi,vd,_1_Q_lsl10,tmix_s,center_s,tmix_c_r | Explicit reset added; arithmetic unchanged |
| C2 wrapper | model latch, pipeline_running, audio_ready | Reset/latch per session |
| C2 parser/scheduler | counts, cursor, phase, fetch state, head | Reset per accepted lab download; validated descriptor range rebuilt |

Combinational `*_next`, `o`, `dv`, `tmix`, `center`, `tmix_c`, waveform and
coefficient expressions are not storage and are not artificially reset.
Descriptor RAM contents need not be cleared: `loaded=0` disables scheduling
until all live descriptors, including EOF, have been rewritten and validated.

## Definition of readiness

1. **Pipeline running**: a post-reset `ce_sid` has occurred.
2. That CE launches state 0. The first-pass filter MAC/compressor result is
   captured into `audio0` at CE + 9 SYS edges (pre-edge state 8).
3. At CE + 16 SYS edges (pre-edge state 15), that result is committed into the
   public audio register. `sample_pulse` is asserted only if a CE-owned
   `publish_pending` token exists, then consumes it.
4. **First qualified sample**: this first completed, post-reset publication.
   It may legitimately be zero. All state feeding it was reset or comes from
   immutable tables/new-session inputs; no magnitude threshold is used.
5. A synchronous consumer sees that registered pulse/data on CE + 17.
   `audio_ready` becomes sticky at this consumer edge; reset clears it.
6. `state==15` remains a saturating idle state upstream. It is **not** exposed
   as a valid level. A long state-15 residence cannot produce extra pulses.

The final lab output is zero while validating, before ready, at EOF/fatal,
or while downloading. There is no time-based unmute timer or N-sample counter.
The first internal publication is normally zero with this original synthetic
stream; the adapter opens after receiving its readiness notification. This is
not yet a production no-head-loss/fade transport qualification.

## Simulation evidence

`tb_contracts.sv` first drives all three voices (saw/noise/pulse), ADSR and a
resonant routed filter. It observes 9,805 nonzero publications, then applies
**one SYS-clock reset edge with CE low**. A separate reference has remained in
reset throughout the dirty session. Both are released together.

For 100,000 SYS clocks after release, every output and valid flag must match
the clean reference; every audio value must be zero without new writes. There
are 4,925 new valid publications, so this is not a permanent-mute comparison.

The full stream test also compares two identical three-second sessions:
2,955,743 internal publications per session, exact waveform/pulse equality
against both the first session and a separately reset reference. The final
output stays zero after EOF. Assertions run with `--assert`.

These are finite simulation proofs for the exercised states, not a formal
proof over all chip configurations. Verilator is a two-state simulator; X
propagation, FPGA power-up behavior, Quartus timing, analog output, digi,
8580 and NTSC remain outside the C2 evidence boundary.
