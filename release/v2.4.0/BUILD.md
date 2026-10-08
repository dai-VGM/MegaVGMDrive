# Reproducing the selected engines

Mac is source authority. Windows Quartus 17.0.0 Build 595 Lite targets Cyclone V 5CSEBA6U23I7. Do not run Quartus on Mac or patch Windows RTL/QSF/QIP.

A/B/D: extract the exact ZIP in source/engines/<engine>/ into an empty directory, open the sole root canonical QPF in Quartus GUI, run Full Compilation and inspect output/. BUILD.bat is optional. Canonical QPF/QSF/QIP are exact archived bytes, not generated Tcl rewrites.

| Engine | Implementation/config | Project / revision | Seed |
|---|---|---|---:|
| A | b4e1b9c (A1+A2), evidence a1fc3cb | MegaVGMDrive_A_vNext_Production_MiSTer | 1 |
| B | 99d4928, seed config 2241e0f, evidence b7a001d | MegaVGMDrive_B_vNext_MiSTer | 3 |
| C | 82402ec, unchanged legacy snapshot | MegaVGMPlayer_EngineC_C7_2_OSD_Visual_MiSTer | retained legacy settings |
| D | 26d5078 | MegaVGMDrive_D_vNext | retained Artifact setting |

C is an explicit legacy carry-forward: source/engines/C contains 89 exact source-closure files with the original nested QPF under hw/engine_c_packed_v2/. No new root-layout claim, configuration rewrite, new RTL or RBF is made for C. Recovering its original producing environment is a separate provenance task. Do not rebuild C and silently replace the accepted hash.

Authorized SSH flow: freeze/hash Mac source and Artifact → transfer to isolated Windows root → verify hashes → compile → collect map/fit/STA/RBF and hashes back to Mac. Record seed/settings/tool and all four corners/five checks/TNS/violating endpoints. Protect prior accepted RBFs. B has independent reproduction evidence; A/D do not. Any new build requires its own output identity and hardware acceptance.

The integrated repository's tools/build_v240.py assembles this distribution from the immutable public v2.3 ZIP and selected artifacts; it performs no Quartus build, deployment, tag, push or publication.
