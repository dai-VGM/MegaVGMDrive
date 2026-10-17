# MegaVGMPlayer v2.5 corresponding source

This fixed snapshot provides the source and license materials corresponding to the six Engine RBFs and common Host/Remote/PWA distributed as MegaVGMPlayer v2.5. It is a source publication, not a new implementation or build.

- `source/Engine_A` through `Engine_F/SourceBuild.zip`: unchanged complete engine Build Artifacts; extract and open the root QPF using Quartus Prime Lite 17.0.0 Build 595, seed 1.
- `source/Runtime`, `source/Remote`, `source/PWA`: fixed common software; original build scripts and manifests are retained.
- `source/Main-corresponding-source.tar`: unchanged corresponding Main source archive.
- `source/megavgm_sid_prepare`: SID preparer source, libsidplayfp original archive and patch.
- `source-dependencies/GNU`, `Go`, `PWA`: retained matching library/dependency source materials.
- `LGPL-SOURCE-ROUTE-CLARIFICATION.txt` and `MANUAL-RELINK-COMMANDS.txt`: application build/relink flags and source access route. No new restriction on modified-library relinking is added. Actual binary-identical relinking is not claimed.
- `SOURCE_IDENTITY.json` and `SHA256SUMS.txt`: fixed revisions and source hashes.
- `LICENSE.txt`, `NOTICE.txt`, `licenses/`, `MODIFICATIONS.txt` and `modifications/`: original notices, full license texts and modification history/diffs.

Sources/dependencies are the same retained materials previously published beside the binary. Internal Gate reports, test logs, legal questions and audit dossiers are not part of this source snapshot. The original development records remain preserved separately.

# Credits

MegaVGMPlayer uses and adapts work from:

- [MiSTer-devel/Genesis_MiSTer](https://github.com/MiSTer-devel/Genesis_MiSTer) and the MiSTer FPGA community.
- [Jotego jtcores](https://github.com/jotego/jtcores), including [JTOUTRUN SegaPCM RTL](https://github.com/jotego/jtcores/tree/master/cores/outrun). Original Jotego notices and license terms are retained.
- [MiSTer-devel/NES_MiSTer](https://github.com/MiSTer-devel/NES_MiSTer): Engine E uses derived APU and related support code. APU clock/reset, connections, DMC/session observation and T65 bus-addressing behavior were adapted. See MODIFICATIONS.txt and the unchanged source notices/diffs. Upstream reference: 49a0a662e244469ca77b2155746a066df704ffae.
- T65 CPU authors Daniel Wallner, Mike Johnson, Wolfgang Scherr and Morten Leikvoll; full source and synthesized-form notices are included.
- MiSTer Golden/Shell contributors, TEMLIB scaler, SID/libsidplayfp contributors, GNU/Go/Gorilla/PWA dependency authors and Roboto contributors; their individual notices are retained.
- The VGM preservation community.

These credits supplement the full LICENSE/NOTICE and individual source headers; they do not replace license terms or grant a different license to third-party code.

MegaVGMPlayer v2.5 licensing status

Original third-party copyright notices and licenses remain in effect. See LICENSE.txt, NOTICE.txt, OWNED_CONTRIBUTIONS_LICENSE.txt, full licenses/, individual source headers and modifications/.
The Intel PLL reconfiguration soft-RTL/GPLv3 combination permission/scope question remains UNRESOLVED. This source snapshot and public distribution do not assert that it was legally cleared. Existing audit findings and the user's publication decision are preserved in development records; no additional Altera inquiry or legal audit is being performed.
