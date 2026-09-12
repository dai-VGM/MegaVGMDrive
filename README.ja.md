# MegaVGMPlayer v2.2 Engine C C5候補

このbranchは実機確認済みPacked MVGMSID v2 Engine Cを既存production自動routingへ
統合します。prepared SIDの正式拡張子は`.mvgmsid`です。拡張子ではなくstrictな
magic/header/body validationによりPROFILE_Cへ分類します。MVGMSID v1も同じRBFで
継続対応します。

[release README](release/README.ja.md)、[validation](release/VALIDATION.md)、
[実機checklist](release/HARDWARE_CHECKLIST.md)を参照してください。

既存A/B classifier、Player、transport/fade、OSD、SID RTL/audio、4 MiB容量は
変更していません。raw `.sid`はこのstageでは対象外です。旧v2.1 RBFはrollback用に
保持します。
