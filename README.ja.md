# MegaVGMPlayer v2.2 Engine C C6候補

このbranchは実機確認済みPacked MVGMSID v2 Engine Cを既存production自動routingへ
統合し、raw SIDのon-demand prepareを追加します。single-SID `.sid`を
`/media/fat/MegaVGMDrive/`へ置くと、Browseには元trackだけが表示され、HPSがstrictな
Packed MVGMSID v2 cacheを生成してから既存PROFILE_C routeへ渡します。

[release README](release/README.ja.md)、[validation](release/VALIDATION.md)、
[実機checklist](release/HARDWARE_CHECKLIST.md)を参照してください。

既存A/B classifier、Player semantics、transport/fade、OSD、SID RTL/audio、4 MiB容量は
変更していません。prepared cacheはmusic library外に置かれBrowseには表示されません。
旧v2.1 RBFはrollback用に保持します。
