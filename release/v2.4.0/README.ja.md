# MegaVGMPlayer v2.4.0 — Architecture Refresh RC

未公開・未配備のRelease Candidateです。A1+A2版A、seed3最適化版B、変更なしの安定版C、D vNextを採用します。新音源追加やA+D一本化は行いません。

Main/Controller/Supervisor/Remote/PWA/helperの8payloadとC RBFはv2.3とbyte一致です。A/B/C/Dのcanonical起動名と既存自動切替を維持します。

実機PASSはユーザーが報告した各RBFの確認範囲のみです。長時間・全曲互換性・全admission試験は新たにPASSとしません。詳細はREADME.md、RELEASE_NOTES.md、HARDWARE_ACCEPTANCE.md、KNOWN_LIMITATIONS.md、TIMING.mdを参照してください。

配備承認前はinstall/upgradeを実行しないでください。承認後はSTOCKへ戻してPlayerを閉じ、install.sh/upgrade.shを実行しbackup pathを保存します。rollback.shは同transactionの旧状態へ復旧します。今回の統合作業では実機・productionへ書き込んでいません。
