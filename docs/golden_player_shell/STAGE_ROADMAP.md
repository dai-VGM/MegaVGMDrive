# Golden Profile stage roadmap

各stageは前stageのWindows Full Compilationと実機試験がPASSした後だけ開始します。

## Stage A — stable shell

OSD、stable video/title、raw/prepared uploadだけ。playback、parser、scanner、DDR read、sound deviceは0。

## Stage B — compatibility scan

full-file compatibility scanだけを追加する。playbackとsound writeは0のまま。scanner owner、read request/response、termination、reloadを独立監査する。

## Stage C — parser + FM

parserとstandard YM2610 FM 4chを追加する。PCM read A/Bは0のまま。wait/loop/`0x66`とsample-validを閉じる。

## Stage D — ADPCM-B

ADPCM-B physical DDR clientを追加する。request/consume/nibble/sample/stop/restartを明示し、ADPCM-A clientは0を維持する。

## Stage E — ADPCM-A

ADPCM-A 6-voice DDR client、mapping、scheduler、simultaneous voice、independent stopを追加する。

## Stage F — simultaneous/loop/reload

ADPCM-A/B simultaneous ownership、FM/SSG/PCM mix、loop、software Reset、same/different reloadをproduction候補として完成する。

Stage順序を飛ばさず、前stageで0だったrequest/write/audio laneを次stageの開始時に明示的に解禁します。
