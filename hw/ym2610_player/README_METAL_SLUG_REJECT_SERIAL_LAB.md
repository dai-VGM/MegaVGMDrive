# Metal Slug YM2610B first-reject UART lab

This lab is based on `c865f7dee7cfe7080309e3c571b207b089f2df8c`.
It sources `MegaVGMPlayer_YM2610B_Bringup_MiSTer.qsf`, which in turn sources
the normal production `MegaVGMPlayer_YM2610_MiSTer.qsf`. The Golden Shell,
HPS/ioctl, reset, menu, video, physical DDR upload, mapper/cache behavior,
JT10, scanner/parser, and watchdog behavior are unchanged. The inherited
upload backend retains MiSTer physical DDRAM base `0x30000000`.

The lab macro adds explicit passive ports to the existing bus, cache, core,
profile, shell, and emu hierarchy. There are no hierarchical references and
no observer output feeds functional logic. A one-cycle context delay retains
the production signals from the cycle that entered the stable reject state;
the observer then freezes the production reject code and that prior context.
The snapshot is transmitted once and remains frozen until reset or the next
raw file download.

## UART

Configure `115200 8-N-1`, no flow control. Exactly one CRLF-terminated,
space-delimited machine-readable line is emitted:

```text
MS_REJECT code=0B class=RANGE scan_class=3 sample=0x01234567 pc=0x0003B40D loop=0x00000002 port=1 reg=28 value=F0 bus_state=2 dout=80 busy=0 watchdog=0000 a_addr=012345 a_bank=0 a_map_hit=0 a_current_hit=0 a_next_hit=1 b_addr=234567 b_map_hit=X b_current_hit=1 b_next_hit=0 req_space=A req_addr=012345 req_active=0 req_pending=1 rsp_valid=1 rsp_space=A rsp_hit=0 rsp_file=000000 fill_valid=1 fill_space=B fill_addr=234566
```

Runtime class decoding is `09=PARSER`, `0A=BUSY`, `0B=RANGE`,
`0C=ADPCM_A`, `0D=ADPCM_B`, `0E=MEMORY`, `0F=SHELL`, otherwise `OTHER`.
`a_map_hit` or `b_map_hit` is `X` unless the captured mapper response belongs
to that space. Response/fill fields use `X` when no valid production-visible
value exists. All logical addresses are full 24-bit values.

## Windows Full Compilation

Do not run Quartus on macOS.

1. Synchronize the complete Mac worktree to Windows.
2. Delete `hw\ym2610_player\db`, `incremental_db`, and `output_files`.
3. Open
   `hw\ym2610_player\MegaVGMPlayer_YM2610B_MetalSlugRejectSerial_MiSTer.qpf`.
4. Run Processing > Start Compilation as a Full Compilation.
5. Use only:

```text
hw\ym2610_player\output_files\MegaVGMPlayer_YM2610B_MetalSlugRejectSerial_MiSTer.rbf
```

On MiSTer, connect UART first, load the specified Metal Slug VGM once, and
retain the first and only `MS_REJECT` line. Do not infer or fix the cause in
this lab stage.
