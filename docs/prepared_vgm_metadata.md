# Prepared VGM display-name metadata

`scripts/vgm_md_import.sh` appends a MegaVGMDrive-specific 128-byte
metadata trailer to each prepared `.vgm` file. The trailer records display
names derived from the final destination path:

- `directory`: the immediate parent directory component;
- `basename`: the final filename with its last `.vgm` extension removed,
  case-insensitively.

For example, `Out Run/01_Magical Sound Shower.vgm` produces:

```text
directory = Out Run
basename  = 01_Magical Sound Shower
```

## Binary layout

All integers are little-endian. The trailer is exactly 128 bytes.

| Offset | Size | Content |
|---:|---:|---|
| `0x00` | 8 | Magic `MVGMTTL\0` |
| `0x08` | 1 | Version, currently `1` |
| `0x09` | 1 | Flags |
| `0x0a` | 1 | Directory length, `0..32` |
| `0x0b` | 1 | Basename length, `0..48` |
| `0x0c` | 2 | Trailer size, `128` |
| `0x0e` | 2 | Reserved, zero |
| `0x10` | 4 | Original VGM size before this trailer |
| `0x14` | 12 | Reserved, zero |
| `0x20` | 32 | Directory, NUL padded |
| `0x40` | 48 | Basename, NUL padded |
| `0x70` | 16 | Reserved for future use, zero |

Flag bit 0 indicates a non-empty directory. Flag bit 1 indicates a non-empty
basename. All other flag bits are zero.

## Binary construction

The helper writes binary header bytes directly to a temporary file with the
shell `printf` builtin and writes zero-filled regions with `dd`. Binary data is
never stored in a shell variable and never passes through `awk`, command
substitution, or another text-oriented utility. Only printable octal digits
used to select one output byte are held in a shell variable.

This is required for compatibility with awk implementations that discard a
NUL produced by `printf("%c", 0)`. Directory and basename conversion may use
awk because those intermediate files contain printable ASCII only; their NUL
padding is added afterward with `dd`.

## Name conversion

Names are limited to printable ASCII bytes `0x20..0x7e`. Decimal digits,
spaces, underscores, punctuation, and letter case are preserved. Directory
names are truncated to 32 display characters and basenames to 48. No scrolling
or transliteration is performed.

The helper decodes UTF-8 structurally using byte values, without depending on
the host locale. One well-formed non-ASCII UTF-8 sequence becomes one `?`.
Invalid UTF-8 leading or continuation bytes also become safe `?` characters.
The result is truncated after this conversion and then NUL padded.

## File and version handling

The VGM bytes before the trailer are not modified. In particular, the helper
does not rewrite the VGM header, EOF offset, GD3 offset, command stream, data
blocks, or `0x66` end command. The metadata is a physical-file trailer after
the archive-original VGM bytes and is not part of the playback command stream.

A prepared output is therefore not an archive-original VGM. Compatibility
with strict standard VGM players and validators is not guaranteed. An
unprepared VGM remains playable by MegaVGMDrive as before, but a future title
renderer will leave its title blank when no supported trailer is present.

Before adding version 1 metadata, the helper removes a final trailer only when
all of these checks pass:

- exact `MVGMTTL\0` magic;
- version `1`;
- valid version 1 flags and name lengths;
- trailer size `128`;
- reserved header bytes at `0x0e..0x0f` are zero;
- original-size field equals physical file size minus 128.

This makes repeated preparation idempotent. A magic mismatch, unknown version,
invalid length, or original-size mismatch is treated as ordinary input data:
the helper does not truncate it and appends a new valid version 1 trailer after
it. Future versions must use a new version value and must not be removed by a
version 1 helper.

Generated cache files are reused only when they are newer than their source
and already have a valid version 1 trailer. Older cache files without metadata
are regenerated even if their timestamps would previously have caused a
cache hit.

Every newly generated file is validated before publication. The helper checks
the physical size, 128-byte trailer position, magic, version, flags, field
lengths, little-endian original-size field, and every reserved or padding byte.
Conversion takes place in a destination-side temporary file. The temporary
file is atomically renamed to the final destination only after validation
passes. On failure, the temporary file is removed and any older destination
file is left unchanged.

The current prepared-file limit is 4 MiB (`4,194,304` bytes), including the
128-byte trailer. Inputs that would exceed this physical size are rejected.
