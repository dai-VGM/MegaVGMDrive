# Golden Player Shell Stage A — Windows build and hardware test

Mac側のQSFとrepository全体が正本です。WindowsではQSFを編集しません。MacではQuartusを実行しません。

## 22 steps

1. Quartusを閉じる。
2. repository全体をWindowsへ同期する。
3. `hw\ym2610_golden_shell\db`、`incremental_db`、`output_files`を削除する。
4. `hw\ym2610_golden_shell\MegaVGMPlayer_YM2610_GoldenShell_MiSTer.qpf`を開く。
5. revisionが`MegaVGMPlayer_YM2610_GoldenShell_MiSTer`であることを確認する。
6. Full Compilationを実行する。
7. `hw\ym2610_golden_shell\output_files\MegaVGMPlayer_YM2610_GoldenShell_MiSTer.rbf`が生成されたことを確認する。
8. MiSTerでRBFを起動する。
9. software Resetをまだ押さない。
10. LCD/HDMI表示をstable MegaVGMPlayer v1.0.1と比較する。
11. OSD/Menuを開閉できることを確認する。
12. ordinary raw VGMをロードする。
13. load後も映像/OSDが維持されることを確認する。
14. prepared Olga VGMをロードする（fileはWindowsローカルに置き、repositoryへ追加しない）。
15. Directory/Basename表示を確認する。
16. 音が完全に出ないことを確認する。
17. 2分放置する。
18. OSD/Menuを再確認する。
19. software Resetを実行する。
20. rawまたはprepared VGMをreloadする。
21. reload後さらに2分放置する。
22. 映像信号断、debug自動切替、フリーズが無いことを確認する。

## Hardware report

```text
Golden Shell Stage A:

- Full Compilation:
- ALM:
- RBF cold start:
- stable版と同じ解像度:
- LCD/HDMI表示:
- OSD:
- Menu:
- raw VGM load:
- prepared Olga load:
- Directory:
- Basename:
- audio zero:
- load直後:
- 30秒:
- 2分:
- 映像信号維持:
- OSD復帰:
- software Reset:
- reload:
- reload後2分:
- debug自動切替:
- fatal:
- power cycle必要:
- 備考:
```

期待結果はstable版と同じ表示、OSD/title/upload正常、audio完全無音、playbackなし、2分以上安定、software Reset/reload正常、映像信号断なし、power cycle不要です。
