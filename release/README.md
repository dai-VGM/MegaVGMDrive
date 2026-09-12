# MegaVGMPlayer v2.2 Engine C C5 candidate

This candidate adds the hardware-tested Packed MVGMSID v2 Engine C to the
existing automatic A/B production route. The same Phase2A owner now selects
PROFILE_A, PROFILE_B, or PROFILE_C. Player and transport semantics, SID audio
RTL, OSD, and existing A/B classification decisions are unchanged.

## Production paths

```text
/media/fat/_Custom Cores/Cores/MegaVGMDrive_A.rbf
/media/fat/_Custom Cores/Cores/MegaVGMDrive_B.rbf
/media/fat/_Custom Cores/Cores/MegaVGMDrive_C.rbf
```

Engine A and B remain byte-identical copies of the v2.1 production RBFs. Engine C
is the exact hardware-validated Packed v2 artifact (`0f205de6…`) and is routed
through its final path. Same-profile C→C keeps the resident RBF; A↔C and B↔C use
the established fade/park/switch/rebind transaction.

All three RBFs keep the exact core name `MegaVGMDrive`. Do not rename CORENAME
to include A, B, or C.

Prepared SID files use `.mvgmsid` for both frozen v1 and Packed v2. The host
requires valid `MVGMSID\0` bytes and the complete strict Engine C header/body
contract before selecting PROFILE_C. Raw `.sid` and experimental `.mvgmsid2`
files are not library/playback inputs in this stage. The status API preserves
model, PAL/NTSC timing, subtune, capture-limit, and source digest metadata; the
Player displays `SID 6581` or `SID 8580`.

## Install or upgrade

Return MegaVGMPlayer to STOCK, close Player tabs, and preserve the backup path
printed by the script.

```sh
cd /path/to/MegaVGMPlayer-v2.2
sh install.sh
# upgrade.sh is an alias for the same transactional operation
```

The installer verifies the complete package, stages files on the FAT volume,
backs up every replaced target, and replaces each target by rename. It installs
the three new RBF names and release-matched Supervisor/controller artifacts.
Existing v2.1 RBFs under `_Custom Cores/Cores` or `_Utility` are not deleted or
modified. User Remote files, playlists, Favorites, and the VGM library are not
payloads.

The existing v2.1 standalone startup block is deliberately retained because
service semantics did not change. An unrecognized or duplicated startup block,
symlink target, non-STOCK state, checksum mismatch, or concurrent install causes
a safe refusal.

After a normal reboot, `/tmp/megavgm_supervisor.status` and the Supervisor control
socket may legitimately be absent. If `status` returns `STATUS_UNAVAILABLE`, the
preflight does not ignore it and does not call `supervisor exit`. Instead it requires
exactly one `MiSTer` process whose executable is `/media/fat/MiSTer` and whose live
executable SHA-256 is
`7ca3cd2f224b9264d0889f593a0d77aafa5adda61910baba92c5ae401e26fcce`.
It also rejects any controller/Supervisor/modified-Main process, extra MiSTer
process, playlist/session status, control FIFO/socket, or Phase2A channel. The
same strict gate runs again after the standalone HTTP daemon is drained.

Reboot after installation, then follow [HARDWARE_CHECKLIST.md](HARDWARE_CHECKLIST.md).
Host tests are not evidence of real FPGA switching.

## Runtime and data

- Standalone Player: `http://<MiSTer-IP>:8183/megavgm`
- Runtime: `/media/fat/MegaVGMPlayer/`
- Engines: `/media/fat/_Custom Cores/Cores/`
- Helper/importer: `/media/fat/Scripts/megavgm_ctl`, `vgm_md_import.sh`
- Music: `/media/fat/MegaVGMDrive/`
- Favorites/Playlists: `/media/fat/Scripts/.config/megavgm/playlists.json`

## Rollback to v2.1

Return to STOCK first, then use the checkpoint printed by install:

```sh
sh rollback.sh
# or
sh rollback.sh '/media/fat/MegaVGMPlayer/backups-v2.2-YYYYMMDD-HHMMSS-XXXXXX'
```

Rollback validates the checkpoint, restores the former Supervisor/controller
and other replaced runtime bytes, and recoverably moves files introduced by the
v2.2 transaction into `backup/retired/`. The untouched old-name v2.1 RBFs remain
available, so the restored v2.1 Supervisor can use its original exact paths.
Later user edits cause rollback to refuse rather than overwrite them.

## Scope

No RBF was synthesized for this integration. A/B RBF bytes, Main, importer,
transport, OSD, and chip implementation are unchanged. Host/Remote changes are
limited to strict prepared-SID classification, PROFILE_C switching, persistence,
and read-only SID metadata. Production A/B/C integration still requires the
included MiSTer checklist; host/QEMU results are not reported as hardware PASS.
