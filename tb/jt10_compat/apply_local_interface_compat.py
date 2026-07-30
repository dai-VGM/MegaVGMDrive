#!/usr/bin/env python3
"""Adapt pinned JT10 to the local JT12 fork in a temporary source tree."""

from pathlib import Path
import sys


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if text.count(old) != 1:
        raise SystemExit(f"{path}: expected exactly one compatibility anchor")
    path.write_text(text.replace(old, new, 1))


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: apply_local_interface_compat.py TEMP_SOURCE_ROOT")

    root = Path(sys.argv[1])
    top = root / "rtl/genesis_audio/jt12/jt12_top.v"
    wrapper = root / "rtl/genesis_audio/jt12/standard_jt10/jt10.v"
    acc = root / "rtl/genesis_audio/jt12/standard_jt10/jt10_acc.v"

    # The pinned driver gates each of the six ADPCM-A voices with this mask.
    replace_once(
        top,
        "        .pcm55_l    ( adpcmA_l      ),\n"
        "        .pcm55_r    ( adpcmA_r      )\n",
        "        .pcm55_l    ( adpcmA_l      ),\n"
        "        .pcm55_r    ( adpcmA_r      ),\n"
        "        .ch_enable  ( 6'h3f         )\n",
    )

    # MMR asserts this one-cycle pulse when ADPCM-B control register 0x10 is written.
    replace_once(
        top,
        "        //.acmd_up_b  ( acmd_up_b     ),  // Control - New command received",
        "        .acmd_up_b  ( acmd_up_b     ),  // Control - New command received",
    )
    replace_once(
        top,
        "    jt10_acc u_acc(\n        .clk",
        "    jt10_acc u_acc(\n        .rst        ( rst           ),\n        .clk",
    )

    # The local single accumulator has an explicit opt-in reset port.
    replace_once(
        acc,
        "module jt10_acc(\n    input               clk,",
        "module jt10_acc(\n    input               rst,\n    input               clk,",
    )
    if acc.read_text().count("jt12_single_acc #(.win(16),.wout(16))") != 2:
        raise SystemExit(f"{acc}: expected two standard stereo accumulators")
    text = acc.read_text().replace(
        "jt12_single_acc #(.win(16),.wout(16))",
        "jt12_single_acc #(.win(16),.wout(16),.use_rst(1))",
    )
    acc.write_text(text)
    if acc.read_text().count("    .clk        ( clk            ),") != 2:
        raise SystemExit(f"{acc}: expected two accumulator clock anchors")
    acc.write_text(
        acc.read_text().replace(
            "    .clk        ( clk            ),",
            "    .rst        ( rst            ),\n"
            "    .clk        ( clk            ),",
        )
    )

    # Match local production's known-safe unused inputs.  ladder=0 is the
    # YM2203/local test setting and is outside the JT10 use_pcm=0 data path.
    replace_once(
        wrapper,
        "    .wr_n           ( wr_n         ),\n",
        "    .wr_n           ( wr_n         ),\n"
        "    .ladder         ( 1'b0         ),\n",
    )
    replace_once(wrapper, "    .IOA_in         (),", "    .IOA_in         ( 8'h00        ),")
    replace_once(wrapper, "    .IOB_in         (),", "    .IOB_in         ( 8'h00        ),")
    replace_once(
        wrapper,
        "    .debug_view     (              )",
        "    .debug_bus      ( 8'h00        ),\n"
        "    .debug_view     (              )",
    )


if __name__ == "__main__":
    main()
