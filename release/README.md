# MegaVGMPlayer v2.2 Engine C C6 candidate

This candidate adds automatic raw SID preparation to the hardware-tested C5
A/B/C route. Put a `.sid` file under `/media/fat/MegaVGMDrive/`, select it in
Browse, and MegaVGMPlayer prepares a Packed MVGMSID v2 cache before using the
unchanged PROFILE_C path. The original SID remains the queue, Favorites, and
status identity; cache files are not shown in Browse.

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

Raw `.sid` files are never sent to FPGA or classified as playable PROFILE_C
payloads. The HPS preparer executes the selected start subtune with pinned
libsidplayfp, captures native-cycle SID bus WRITEs, emits Packed v2 directly,
strictly validates it, then atomically publishes it under
`/media/fat/MegaVGMPlayer/cache/sid/`. Only that cache artifact enters the
existing C5 classifier and index-1 path. The Player displays `Preparing SID…`
during a cache miss; a valid cache hit follows the normal load path.

Initial C6 supports one SID chip and the PSID/RSID start subtune. Exact declared
6581/8580 and PAL/NTSC metadata are used. Unknown/any metadata needs an exact
SHA/subtune `.sid.megavgm` sidecar; it is never silently defaulted. BASIC-ROM
compatibility and multi-SID files are rejected. No C64 ROM or copyrighted SID
tune is included.

Duration priority is an optional `MegaVGMPlayer/sid/Songlengths.md5` exact
content-MD5/subtune lookup, then an exact sidecar duration, then a documented
300-second capture limit. No basename matching or loop guessing is used.

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

Before declaring the transaction complete, the installer re-hashes every installed
production target against the packaged payload, restarts the standalone Remote,
and verifies that the package, installed Remote, runtime `/tmp/megavgm_remote`,
service-reported SHA, and `/proc/<pid>/exe` identity all agree. Any mismatch leaves
the transaction incomplete and eligible for recovery; the mere presence of staged
or replaced files is not an install-success condition.

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
- SID cache: `/media/fat/MegaVGMPlayer/cache/sid/`
- Optional duration DB: `/media/fat/MegaVGMPlayer/sid/Songlengths.md5`

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
limited to raw-SID discovery, preparation ownership, PREPARING publication, and
the existing strict PROFILE_C handoff. Production C6 integration still requires the
included MiSTer checklist; host/QEMU results are not reported as hardware PASS.
