# MegaVGMPlayer v2.1 — Independence Day

MegaVGMPlayer v2.1 separates the FPGA music player from MiSTer Remote. The Player and API now run in the dedicated `megavgm_remote` daemon on port **8183**, while the normal MiSTer Remote can continue independently on port 8182.

MegaVGMPlayer v2.1 no longer requires a modified MiSTer Remote.

## Highlights

- Standalone MegaVGMPlayer daemon and independent PWA/UI
- Dedicated MegaVGMPlayer URL: `http://<MiSTer-IP>:8183/megavgm`
- Coexists with MiSTer Remote on port 8182
- Existing Favorites and Playlists are used without migration
- Existing Phase2A automatic FPGA sound-engine switching is preserved
- Mixed-engine A→B→A playlists and same-profile transitions
- Restarting only the HTTP daemon does not stop FPGA playback
- UI reconnects to the current authoritative playback state
- Standalone service starts automatically after MiSTer reboot while MiSTer remains STOCK
- Playlist completion and Exit restore stock MiSTer

The automatic engine selection, transition fades, Previous/Next/Stop, Repeat One, Repeat Context, Shuffle, Favorites, Playlists, and sound-chip support from v2.0 remain unchanged.

## Install

1. Download and extract `MegaVGMPlayer-v2.1.zip`.
2. Copy the contents of `media/fat/` to `/media/fat/` on MiSTer, preserving the directory structure, or copy the package and use `install.sh`.
3. Reboot MiSTer.
4. Open `http://<MiSTer-IP>:8183/megavgm` from a browser on the same LAN.

Advanced users can use the included checksum-verifying `install.sh`, `upgrade.sh`, and `rollback.sh`. Read the included README and return MegaVGMPlayer to STOCK before installation or rollback.

## Upgrading from v2.0

- Favorites/Playlists require no migration: `/media/fat/Scripts/.config/megavgm/playlists.json` is preserved.
- The VGM library remains `/media/fat/MegaVGMDrive/`.
- The RBF location remains `/media/fat/_Custom Cores/Cores/`.
- Use port 8183 for MegaVGMPlayer v2.1.
- Do not operate the old v2.0 MegaVGMPlayer UI on port 8182 concurrently.
- Recreate an iPhone/iPad Home Screen shortcut from the new 8183 URL; an existing v2.0 shortcut uses the old origin.

The package does not contain or overwrite `/media/fat/Scripts/remote.sh`. It does not automatically replace a potentially customized v2.0 Remote with an unverified upstream version. Leaving the existing Remote installed does not prevent standalone operation on 8183.

## Runtime layout

```text
/media/fat/_Custom Cores/Cores/
  MegaVGMPlayer_Transport13FadeOnly_A_MiSTer.rbf
  MegaVGMPlayer_Transport13FadeOnly_B_MiSTer.rbf

/media/fat/MegaVGMPlayer/
  MiSTer.megavgm
  megavgm_supervisor
  megavgm_playlist-phase2a
  megavgm_remote

/media/fat/Scripts/
  megavgm_ctl
  vgm_md_import.sh
```

## Notes

- Cold start may take a few seconds while the FPGA sound engine initializes.
- Sound-chip labels are informational and depend on available VGM/package metadata.
- Mega CD / RF5C164 and 32X PWM are not supported.
- Pause and authoritative elapsed/remaining progress are not included.

SHA-256 values and exact component provenance are included in the package's `SHA256SUMS` and `ARTIFACT_MANIFEST.md`.
