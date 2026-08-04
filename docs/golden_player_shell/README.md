# Golden Player Shell

このdirectoryは、実機安定済みMegaVGMPlayer v1.0.1を正本とするstandard YM2610 profileの段階移植契約です。正本commitは`5ecce555edb80bdcb010a322ee46ba8837a6ee27`、port開始commitは`951fea6b9644b774d8eb8c98cb22e9b2bde6f5dd`です。

Stage Aはstable shell、OSD、video、title、physical DDR uploadだけを含みます。parser、scanner、DDR read、sound device、playbackは含みません。

- `stable_source_manifest.json`: source/blob/SHA-256/role/classification
- `IMMUTABLE_CONTRACT.md`: Stage Aで固定するproduction契約
- `PORT_MAPPING.md`: stable emuと将来profileの境界
- `STAGE_ROADMAP.md`: Stage B–Fの順序と解禁条件
- `SOURCE_AUDIT.md`: QSF/QIP/source graphと非Quartus検証

MacではQuartusを実行しません。最初のQuartus compileと実機確認はStage AのWindows手順に従います。
