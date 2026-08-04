# Golden Player Shell v1.1 Stage C hardware validation

Status: pending. Non-Quartus PASS is not a Quartus build or a MiSTer PASS.
Stage A, Audio Lab cold-start audio, and Stage B are recorded hardware PASS;
this Stage C candidate must be validated separately before Stage D begins.

Golden Shell v1.1 Stage C:

- Full Compilation:
- ALM:
- RBF cold start:
- v1.1 Stage A/Bと同じ解像度:
- LCD/HDMI:
- OSD/Menu:
- Olga load:
- Directory:
- Basename:
- scan:
- status:
- playback開始:
- 最初の2.74秒:
- FM開始:
- FMの聴感:
- PCMらしき音:
- 30秒:
- 2分:
- 3分10秒後loop:
- 映像信号維持:
- OSD復帰:
- software Reset:
- reload:
- reload後の曲頭:
- synthetic SSG A:
- synthetic SSG B:
- synthetic SSG C:
- debug自動切替:
- fatal:
- freeze:
- power cycle必要:
- 備考:

Expected: normal video/title/OSD; silence until about 2.74 seconds after
playback starts; FM-only audio thereafter; no PCM-like sound; continuous loop;
working Reset and reload; no automatic debug page, fatal, freeze, video loss,
or required power cycle.
