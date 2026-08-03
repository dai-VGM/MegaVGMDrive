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

The profile reset controller asynchronously asserts on PLL unlock, synchronizes
video release to `clk_sys`, and holds player/backend/JT10 reset for 25,000,000
stable 20 MHz cycles (1.25 seconds). Shell or software reset restarts only that
player POR; it never resets the video counter. A reset during upload aborts the
current transfer until the HPS download level returns low, so a partial file
cannot be scanned.

The load sequence is download/mute, a two-cycle stable upload completion fence,
full compatibility and descriptor scan, JT10 reset, 64 known-zero samples,
explicit FM/SSG/ADPCM silence writes, 32 settling samples, then one start pulse.
The fence requires the original size to be committed, upload FIFO and partial
word empty, no finish/write pending, DDR idle, and no read/write strobe. A
rejected file never reaches the silence writes or playback bus. Header clock
bits 30/31 are separated from the 8 MHz clock value; JT10 CEN is fractional and
VGM waits use 44.1 kHz.

The runtime memory arbiter uses a transparent one-entry request hold: the old
zero-wait timing is retained when DDR is ready, while address, owner and load
generation are latched and held across backpressure. Only an accepted request
creates one outstanding transaction. Its captured owner/address/generation
routes the response. Parser and PCM alternate whenever both remain eligible;
the maximum wait is one accepted transaction from the other client. The PCM
frontend similarly holds its mapped file address and alternates simultaneous
active A and B misses; an idle lane cannot displace an active lane. An
old-generation or ownerless response is discarded and latched as a fatal
memory error, never delivered to a client.

Runtime fatal state stops scanner/parser/JT10 writes and new DDR requests,
mutes audio, and leaves the native video generator and OSD free-running. A
`YM2610 FAT` page overrides Debug View=Off and shows the first fatal code,
player/scanner/parser states, live request/busy and held/outstanding owners,
last DDR accept/response addresses and generations, reset source, load
generation, video-reset count, and video/player/DDR heartbeats. Reset or a new
Load VGM recovers without a power cycle.

Debug Parser shows raw variant (`RV`), compatibility class (`CL`), rejection
code (`RJ`), first bad PC and packed port/address/data (`BP`/`BD`), parser PC,
opcode, wait, port write counts, start/loop counts and unsupported PC/opcode.
Debug PCM shows descriptor counts, A/B fetch request/response counts, JT10 A/B
pin request counts and last addresses, cache occupancy, underflow/stale/owner
flags, final L/R peaks, request/owner state and heartbeats. Both pages remain
below the 29-row limit.

Pre-scan rejection codes `01`–`08` cover header, dual, B-required, unknown
register, opcode, block, range and descriptor errors. Runtime codes `09`–`0E`
cover parser, BUSY, PCM range, A underflow, B underflow and memory ownership or
response failure.

## Video contract

`CLK_VIDEO`, `CE_PIXEL`, sync polarity, 638x262 totals, 529x240 active raster,
4:3 aspect and `VGA_SCALER=0` intentionally match production MegaVGMPlayer.
This is a native approximately 15.7 kHz source; an analog LCD connected to the
native VGA output can therefore describe it as CRT/15 kHz. HDMI/LCD scaling is
performed by the MiSTer `sys_top` path. The profile now also routes
`direct_video`, `forced_scandoubler`, gamma and the direct-video menu mask in
the same form as production, but does not guess new sync totals or enable a
different scaler contract.

## Windows build and hardware check

1. Close Quartus.
2. Synchronize the complete Mac repository to Windows.
3. Delete `hw\ym2610_player\db`, `hw\ym2610_player\incremental_db`, and
   `hw\ym2610_player\output_files` if present.
4. Open `hw\ym2610_player\MegaVGMPlayer_YM2610_MiSTer.qpf`.
5. Confirm revision `MegaVGMPlayer_YM2610_MiSTer`.
6. Run Full Compilation.
7. Use `hw\ym2610_player\output_files\MegaVGMPlayer_YM2610_MiSTer.rbf`.
8. Load the RBF and, without pressing software Reset, select the unmodified
   `03 Olga Breeze.vgm` from **Load VGM**.
9. Confirm the display follows the normal MegaVGMPlayer presentation. On HDMI,
   confirm the MiSTer scaler produces the expected LCD mode; native VGA remains
   the production 15 kHz contract described above.
10. Let playback run for at least 30 seconds and record observations at 5, 10,
    and 30 seconds.
11. Open Menu/OSD during playback and confirm video and input remain live.
12. Press software Reset once; confirm video timing/OSD do not reset and the
    player returns to Load-wait after its 1.25 second POR.
13. Reload Olga Breeze and run for at least 30 seconds again.
14. Inspect Debug Parser and Debug PCM. Record fatal code, player state, DDR
    owner/outstanding and video/player/DDR heartbeats.
15. If a fatal occurs, confirm `YM2610 FAT` remains visible even with Debug View
    Off, Menu/OSD still opens, software Reset recovers, and no power cycle is
    needed.

A prepared file displays its Directory and Basename on the normal navy panel.
A raw file plays through the same parser/audio path without a title.

Quartus is intentionally not run on macOS. A successful non-Quartus audit is
not a claim that Windows fitting or hardware listening has passed.
