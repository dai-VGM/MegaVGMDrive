#!/usr/bin/env python3
"""Apply declaration-order-only fixes to a temporary JT10 source tree."""

from pathlib import Path
import sys


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if text.count(old) != 1:
        raise SystemExit(f"{path}: expected exactly one compatibility anchor")
    path.write_text(text.replace(old, new, 1))


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: apply_icarus_syntax_compat.py TEMP_SOURCE_ROOT")

    root = Path(sys.argv[1])
    gain = root / "rtl/genesis_audio/jt12/standard_jt10/adpcm/jt10_adpcm_gain.v"
    top = root / "rtl/genesis_audio/jt12/jt12_top.v"
    gain_before = gain.read_text()
    top_before = top.read_text()

    replace_once(
        gain,
        "reg  [6:0] db5;\nalways @(*)",
        "reg  [6:0] db5;\nreg  [9:0] lin_5b;\nalways @(*)",
    )
    replace_once(
        gain,
        "reg  [9:0] lin_5b, lin1, lin2, lin6;",
        "reg  [9:0] lin1, lin2, lin6;",
    )
    replace_once(
        gain,
        "reg [31:0] pcm2_mul;\nwire signed [15:0] lin2s",
        "reg [31:0] pcm2_mul;\nreg signed [15:0] pcm2;\nwire signed [15:0] lin2s",
    )
    replace_once(
        gain,
        "reg signed [15:0] pcm1, pcm2, pcm3, pcm4, pcm5, pcm6;",
        "reg signed [15:0] pcm1, pcm3, pcm4, pcm5, pcm6;",
    )

    op_declarations = "wire    [ 8:0]  op_result;\nwire    [13:0]  op_result_hd;\n"
    replace_once(top, op_declarations, "")
    replace_once(
        top,
        "wire clk_en_2, clk_en_666, clk_en_111, clk_en_55;\n",
        "wire clk_en_2, clk_en_666, clk_en_111, clk_en_55;\n\n"
        + op_declarations,
    )

    def without_moved_declarations(text: str) -> str:
        declarations = (
            "reg  [9:0] lin_5b;\n",
            "reg  [9:0] lin_5b, lin1, lin2, lin6;\n",
            "reg  [9:0] lin1, lin2, lin6;\n",
            "reg signed [15:0] pcm2;\n",
            "reg signed [15:0] pcm1, pcm2, pcm3, pcm4, pcm5, pcm6;\n",
            "reg signed [15:0] pcm1, pcm3, pcm4, pcm5, pcm6;\n",
        )
        for declaration in declarations:
            text = text.replace(declaration, "")
        return text

    if without_moved_declarations(gain_before) != without_moved_declarations(
        gain.read_text()
    ):
        raise SystemExit(f"{gain}: non-declaration logic changed")
    top_logic_before = "".join(top_before.replace(op_declarations, "").split())
    top_logic_after = "".join(top.read_text().replace(op_declarations, "").split())
    if top_logic_before != top_logic_after:
        raise SystemExit(f"{top}: non-declaration logic changed")


if __name__ == "__main__":
    main()
