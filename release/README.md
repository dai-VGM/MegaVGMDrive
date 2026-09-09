# MegaVGMPlayer v2.1 “Independence Day”

FPGA Music Player for MiSTer — Phase 2 productionization candidate.

MegaVGMPlayer now runs as its own `megavgm_remote` service on **8183**.
The payload is byte-identical to the user-confirmed Phase 1 hardware-PASS daemon.
This package does not contain, download, stop, replace, or re-register MiSTer Remote.
Existing Remote on 8182 is left alone. Use only `http://<MiSTer-IP>:8183/megavgm`
for MegaVGMPlayer; do not operate the old 8182 MegaVGMPlayer UI concurrently.

## Install / upgrade

Back up the SD card first. Stop using both Player UIs, finish playback or explicitly
Exit to STOCK, and keep them closed through installation. Copy/extract this entire
package to a temporary directory on MiSTer, not directly over runtime files.

```sh
cd /path/to/MegaVGMPlayer-v2.1
sha256sum -c SHA256SUMS
sh install.sh                 # new install
# OR: sh upgrade.sh          # v2.0 or Phase 1 upgrade, same transaction
```

The scripts require STOCK when the Supervisor is installed. They stage and verify
all eight payload files, make a unique timestamp backup, then rename each file
atomically on the same FAT filesystem. A multi-file update is not globally atomic;
on interruption, do not open Player. Use the printed prepared backup with rollback.
Stage and backup directories are retained for inspection. Concurrent installers
are rejected by a lock; after a crash, inspect the transaction before manually
removing its empty `.v21-install-lock` directory.

The script appends the exact `startup.block` once to `linux/user-startup.sh`.
All existing Remote/favorites text is preserved, including user customizations.
An unknown or duplicate standalone invocation causes a safe refusal rather than
rewriting user startup. A second identical install is a no-op and retains the
original rollback checkpoint. Symlink targets/parents are rejected.

If standalone was already running, its verified identity is recorded, HTTP is
drained using its unchanged service stop, then the formal daemon is started.
No Stop/Exit playback command is issued by service operations. Installation itself
requires STOCK because the package includes unchanged Main/controller/Supervisor.
If it was not running, installation leaves it stopped until reboot.

Reboot and follow [HARDWARE_CHECKLIST.md](HARDWARE_CHECKLIST.md). Autostart only
starts HTTP; it does not ENTER MegaVGMPlayer. Stock MiSTer remains active until Play.
The block forwards `start`, `stop`, and `restart`; no argument defaults to `start`.
This matches the existing supplied user-startup service forwarding convention.
Actual boot/shutdown invocation on MiSTer is a hardware acceptance item, not a host claim.

## Service

```sh
/media/fat/MegaVGMPlayer/megavgm_remote -service status
/media/fat/MegaVGMPlayer/megavgm_remote -service start
/media/fat/MegaVGMPlayer/megavgm_remote -service stop
/media/fat/MegaVGMPlayer/megavgm_remote -service restart
```

Runtime executable: `/tmp/megavgm_remote`; log: `/tmp/megavgm_remote.log`.
PID/start-time/executable-SHA verification and flock ownership are unchanged.
An occupied 8183 fails explicitly without alternate port or killing its owner.
Crash recovery is explicit service start/restart or next reboot; no new watchdog.
Do not add this service through MiSTer Remote registration or update_all hooks.
Existing `remote.sh` autostart/update ownership remains independent.

## Data and paths

- Runtime: `/media/fat/MegaVGMPlayer/`
- Engines: `/media/fat/_Custom Cores/Cores/` (existing Transport13 filenames)
- Helper/importer: `/media/fat/Scripts/megavgm_ctl`, `vgm_md_import.sh`
- Music: `/media/fat/MegaVGMDrive/`
- Existing Favorites/Playlists: `/media/fat/Scripts/.config/megavgm/playlists.json`

No playlist migration, deletion, or overwrite occurs, including on rollback.
The package does not remove old RBFs or Phase 1 rescue executables.

## Existing MiSTer Remote restoration

The v2.0 bundled modified Remote is identifiable by SHA-256
`720b982c194767ecaac308cec2d87265b66018b6aef6cecec8eacdb23fa94cfa`.
However, v2.0 backups contain arbitrary pre-install bytes without authoritative
upstream provenance. Knowing the current hash does not prove a backup is original
Remote rather than a user customization. Therefore **no automatic restoration**
is performed. Existing Remote and its startup block remain byte-for-byte intact.

If you want original Remote back, independently identify and verify your trusted
pre-v2.0 backup, preserve the current Remote under a new backup name, then use that
Remote version's own documented stop/replacement/start procedure. Do not guess from
the backup filename and do not overwrite an unknown customized Remote. This is
optional and separate from installing MegaVGMPlayer; 8183 needs none of its APIs.

## Rollback

Close Player and return to STOCK first:

```sh
sh rollback.sh
# Or pass the exact Backup path printed by install (also for interrupted updates):
sh rollback.sh '/media/fat/MegaVGMPlayer/backups-v2.1-YYYYMMDD-HHMMSS-XXXXXX'
```

Rollback validates backup hashes and refuses to overwrite later edits. It stops
only the standalone daemon, restores pre-install runtime files and startup bytes,
and moves newly introduced files into the backup's `retired/` directory. If a
verified standalone service was running before install, its exact saved executable
is restarted, including when it originally used a Phase 1 filename. Otherwise it
remains stopped. Remote is unchanged throughout; JSON updates made after install
are also retained. Reboot after rollback and verify the previous service state.

## Validation scope

Phase 1 playback and iPhone PASS are user-reported. Phase 2 host/QEMU checks do not
prove hardware reboot/autostart or real FPGA switching. A→B→A and STOCK in the
HTTP test suite are authoritative-status fixtures. Final hardware acceptance is
pending until the checklist is completed. No new UI, API, Player, or audio feature
is included in this phase.
