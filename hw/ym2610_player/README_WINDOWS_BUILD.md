# MegaVGMPlayer YM2610 profile

This is an independent standard-YM2610 MiSTer profile. It accepts ordinary
YM2610 VGM files and a deliberately narrow class of YM2610B-tagged files whose
complete register trace uses only standard four-FM-channel YM2610 semantics.
It does not implement the two additional YM2610B FM channels.

The player performs a complete pre-play scan before releasing audio. Dual-chip
files, B-only key-on or setup writes, unknown registers, unsupported commands,
compressed/unknown blocks, overlapping ROM descriptors and out-of-range type
82/83 blocks are rejected before JT10 receives a playback write.

The common 23-bit DDR loader, `MVGMTTL` title receiver, title panel, font and
native MiSTer video timing are referenced directly. The production parser,
production top, production QSF/QIP and HW-0 sequencer/video/self-test ROM are
not part of this profile. The only HW-0-named RTL referenced is the already
verified standalone JT10 wrapper/core source set; those files remain unchanged.

The PCM frontend keeps payloads in the loaded VGM image in DDR. A/B descriptors
map logical ROM addresses to file offsets. A shared cache shadows ADPCM start
registers and holds A or B START until the first two bytes of every selected
stream are resident. Current/+1 prefetch continues while playing. Any range,
underflow, stale response or owner mismatch is sticky and mutes the profile.

The load sequence is download/mute, full compatibility and descriptor scan,
JT10 reset, 64 known-zero samples, explicit FM/SSG/ADPCM silence writes, 32
settling samples, then one start pulse. A rejected file never reaches the
silence writes or the playback bus. Header clock bits 30/31 are separated from
the 8 MHz clock value; JT10 CEN is fractional and VGM waits use 44.1 kHz.

Debug Parser shows raw variant (`RV`), compatibility class (`CL`), rejection
code (`RJ`), first bad PC and packed port/address/data (`BP`/`BD`), parser PC,
opcode, wait, port write counts, start/loop counts and unsupported PC/opcode.
Debug PCM shows descriptor counts, A/B fetch request/response counts, JT10 A/B
pin request counts and last addresses, cache occupancy, underflow/stale/owner
flags and final L/R peaks. Both pages remain below the 29-row limit.

Pre-scan rejection codes `01`–`08` cover header, dual, B-required, unknown
register, opcode, block, range and descriptor errors. Runtime codes `09`–`0E`
cover parser, BUSY, PCM range, A underflow, B underflow and memory ownership or
response failure.

## Windows build

1. Close Quartus.
2. Synchronize the complete Mac repository to Windows.
3. Delete `hw\ym2610_player\db`, `incremental_db`, and `output_files` if present.
4. Open `hw\ym2610_player\MegaVGMPlayer_YM2610_MiSTer.qpf`.
5. Confirm revision `MegaVGMPlayer_YM2610_MiSTer`.
6. Run Full Compilation.
7. Use `hw\ym2610_player\output_files\MegaVGMPlayer_YM2610_MiSTer.rbf`.

On MiSTer, open the OSD, choose **Load VGM**, and select the unmodified Olga
Breeze file. A prepared file displays its Directory and Basename on the normal
navy panel. A raw file plays with the same parser/audio path and no title.
`Debug View` defaults to Off; Parser and PCM pages show the latched compatibility
and transport fields without changing playback.

Quartus is intentionally not run on macOS. A successful non-Quartus audit is
not a claim that Windows fitting or hardware listening has passed.
