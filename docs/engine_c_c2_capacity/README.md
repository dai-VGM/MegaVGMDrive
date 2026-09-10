# Engine C C2 capacity lab — 4 MiB

Branch: `engine-c-c2-capacity`

Frozen base: `e00601449d0e6d4b880578bb2b21d6cce92dbfb2` (`engine-c-phase-c2`).

This is a new, isolated **simulation-tested lab project**. Windows Quartus fit,
timing closure and real MiSTer playback are **not yet verified**. No RBF was built
on macOS. All files tracked at the base remain byte-for-byte unchanged, including
C0/C1, SID vendor/reset/publication logic, scheduler, A/B, host and Player.
The earlier C2 QPF remains available as the hardware-known-good fallback.

## Root cause and address audit

The old limit is not a 17-bit upload-address wrap. There are TWO explicit
preflight resource limits:

| Layer / frozen source | Width / limit | Consequence |
| --- | --- | --- |
| `shell/emu_c2.sv` and `shell/mister_vgm_md_top_v1_1.sv`: ioctl address | 27-bit byte address | Forwarded without 17-bit truncation |
| `shell/golden_player_shell_upload.sv`: upload address | Zero-extends 27 to 32 bits | Actual address checked by DDR backend |
| `rtl/vgm_ddram_backend.sv`: `ADDR_WIDTH` | 23 in C2 QSF | 8 MiB physical raw-file window; out-of-range upload sets sticky overflow and does not publish load complete |
| Backend file size / profile uploaded size | 32 bits | 4 MiB and 8 MiB are representable |
| `mvgmsid_loader.sv`: position / latched size | 32 bits | Byte read address is checked and uses 23 low bits only within admitted range |
| Loader event index / count / elapsed SID cycle | 64 bits | No 8,192-entry index wrap |
| Loader `MAX_EVENTS=8192` | `128 + 8192*16 = 131200` bytes | **128 KiB + 128-byte header**, not exactly 128 KiB; file-range error 1 above this size, event-count error 6 for incompatible header |
| `engine_c_lab.sv`: `MAX_RECORDS=4096` | 12-bit record address, 13-bit count; 78-bit records | **4,095 WRITEs + EOF**; the 4,096th WRITE produces error 11 even within the file-size limit |
| Header/event addressing | `pos[6:0]` / `pos[3:0]` | Offsets within the 128-byte header / 16-byte event, not whole-file truncation |

Paths in the table are relative to `rtl/engine_c_c2/` unless explicitly prefixed
`rtl/`. The QSF macros retain `MODE5_VGM_ADDR_WIDTH=23`. There is no C2 upload
`0x20000` byte-address modulus or 17-bit byte address.

Direct old/new simulation contrast:

- Valid WAIT/EOF file of 131,200 bytes: old accepts.
- Valid WAIT/EOF file of 131,216 bytes: old error 1 at test SYS cycle 0,
  before any byte-read request; new accepts.
- Valid 131,200-byte file containing 4,096 WRITEs: old error 11 at test
  SYS cycle 270,559; new emits all 4,096 WRITEs at their exact native cycles.

These deterministic source limits explain a capacity cliff around the reported
7s/8s sizes independently of SID audio. The actual Commando files and an on-board
error-code trace were not supplied to this worktree, so which of the two rejects
fired first for each individual hardware file is not claimed as measured.

## Capacity-only implementation

`C2_MAX_FILE_BYTES=4194304` is explicit in the dedicated QSF, with the same
default in `rtl/engine_c_c2_capacity/capacity.vh`. It includes the 128-byte header.

```text
index-1 upload → unchanged raw DDR backend (8 MiB physical window)
                         ↓
              strict whole-file preflight (4 MiB logical limit)
                         ↓ timestamped {EOF, cycle, register, data}
                 descriptor DDR region
                         ↓ burst prefetch
                 64 × 78-bit FIFO
                         ↓ original request/response interface
             UNCHANGED native SID scheduler / SID / audio publication
```

Derived bounds:

- `MAX_EVENTS = (MAX_FILE_BYTES - 128) / 16 = 262136`.
- Strict v1 disallows multiple WRITEs in one native cycle. A maximum-density
  legal stream alternates WRITE and positive WAIT and ends with EOF. Consequently
  maximum WRITEs = `floor(MAX_EVENTS/2) = 131068`.
- `MAX_RECORDS = floor(MAX_EVENTS/2) + 1 = 131069`, including EOF.
- Record address = 17 bits; record count = 18 bits. There is no descriptor wrap.
- Enlarging the old 78-bit BRAM array to this worst case would require
  10,223,382 bits just for descriptors. This change uses DDR, not a huge new BRAM.
- FIFO storage is 4,992 bits. Actual synthesis resource use is not yet measured.

DDRAM bus addresses count **64-bit words**:

| Storage | Byte range (end exclusive) | DDR word base |
| --- | --- | --- |
| Existing raw file allocation | `0x30000000 .. 0x30800000` | `0x06000000` |
| C2 descriptor allocation | `0x30800000 .. 0x30c00000` | `0x06100000` |

The latter is the unused PCM region already named by the frozen C2 upload
adapter's `SEGAPCM_ROM_BASE_ADDR`. C2 has no PCM consumer or copy request. This
reuse is **C2-only**, not an A/B allocation change. Descriptor slots are 16 bytes,
with the original 78-bit record in the low bits and zero upper padding. Slot
address is `BASE_WORD + (record_index << 1)`, NOT a byte-address cast.
At 4 MiB the used descriptor bytes total 2,097,104, within the 4 MiB reservation.

The new arbiter queues one registered command per client and permits only one
outstanding read burst, routing every returned beat to its owner. It drains
outstanding transactions across per-download resets; only core reset resets the
arbiter. The writer waits for actual queued-command drain before marking storage
available. Byte enables and burst lengths are explicit. Raw and descriptor
addresses are range-asserted in the integration memory model.

Preflight may wait for descriptor write storage, but **SID playback has not yet
started**. All validation, descriptor writes, and initial FIFO availability
precede the existing scheduler launch. FIFO prefill is a storage-readiness
threshold, not a mute/sample delay; no SID samples are discarded. Thereafter CE,
WRITE phase, reset qualification and sample publication use the frozen modules.
The FIFO refills in eight-record bursts. If DDR fails to supply events in time,
the unchanged scheduler reports underflow `0x80` without slowing/stopping CE.
Descriptor storage timeout/corrupt padding/address mismatch is fatal `0x81`.

Over-capacity files are never truncated to fit:

- `4 MiB + 1` and larger logical files reject with error 1 before preflight reads.
  Files up to the physical 8 MiB bound can have been uploaded first; they do not
  become accepted playback streams.
- Misaligned in-range sizes, forged count/size metadata, trailing/truncated
  records and malformed EOF reject under the existing strict validator.
- Byte upload address `0x800000` is rejected by the frozen physical backend;
  load-complete/parser-start is not asserted.
- Parameter guards reject configurations exceeding the raw or descriptor DDR
  window or reducing the record bound below the derived legal maximum. The
  4 MiB setting is tested; larger parameter configurations are not certified.

## Reproduce tests (macOS, no Quartus)

From the new worktree root:

```sh
python3 tools/engine_c_c2_capacity/run_tests.py
python3 tools/engine_c_c2_capacity/audit.py
python3 -m unittest discover -s tools/engine_c_c0 -v
MVGMSID_C1_NATIVE_HELPER=/path/to/frozen/c1/sid_capture \
  python3 -m unittest discover -s tools/engine_c_c1 -v
```

The capacity runner first executes the frozen 47-case C2 regression, then builds
the new storage path. `--reuse-baseline` reuses the previously completed baseline
at `/tmp/megavgm-c2-capacity-baseline`. New outputs are at
`/tmp/megavgm-c2-capacity/`; no generated music or third-party SID is committed.

Coverage/results are recorded in [RESULTS.md](RESULTS.md). Both old and new
synthetic three-second tone PCM are bit-identical. This proves unchanged audio
for that fixture, not real-hardware audio validation.

## Windows Full Compilation

Synchronize the **whole new worktree**, not just the QPF: new storage RTL and
dedicated QIP source resolution are required.

QPF:

```text
/Users/daizo/Projects/MegaVGMPlayer_EngineC_C2_Capacity/hw/engine_c_c2_capacity/MegaVGMPlayer_EngineC_C2_Capacity_MiSTer.qpf
```

In Windows, from that `hw/engine_c_c2_capacity` directory:

```bat
quartus_sh --flow compile MegaVGMPlayer_EngineC_C2_Capacity_MiSTer
```

Expected (not generated on Mac):

```text
hw/engine_c_c2_capacity/output_files/MegaVGMPlayer_EngineC_C2_Capacity_MiSTer.rbf
```

The project is self-contained, has no subtractive QSF overlay, and resolves
the new loader/profile/engine/mux/store exactly once while reusing the old SID,
scheduler, upload backend and platform. Do not overwrite the original C2 RBF.

After Windows fit/timing checks, hardware checklist:

1. Load the distinct capacity-lab RBF using the existing C2 manual procedure.
2. Synthetic 3s and Commando 5s/7s remain working.
3. Commando 8s/9s/10s/30s/60s load, play through EOF, then repeat.
4. Load a maximum-size valid stream; verify EOF and no scheduler/storage fatal.
5. Oversize/malformed input rejects without SID writes or old-session audio;
   a subsequent small valid stream recovers normally.

Windows compilation, DDR hardware latency margin, Commando audio and the above
hardware checklist remain unverified. SID provenance/license caveats remain
those of [frozen C2](../engine_c_c2/PROVENANCE.md).
