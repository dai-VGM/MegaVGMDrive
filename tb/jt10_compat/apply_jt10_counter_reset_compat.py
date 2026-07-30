#!/usr/bin/env python3
"""Add the JT10-only FM sequencer reset to a temporary source tree."""

from hashlib import sha256
from pathlib import Path
import sys


LEGACY_BLOCK = """end else begin : gen_counter_legacy
    always @(posedge clk) begin : up_counter
        if( clk_en ) begin
            { cur_op, cur_ch } <= { next_op, next_ch };
            zero <= next == 5'd0;
        end
    end
end
"""

RESET_BLOCK = """end else begin : gen_counter_legacy
    // JT10 standalone compatibility: use the existing sequencer reset
    // contract without changing the post-reset recurrence.
    always @(posedge clk) begin : up_counter
        if( rst ) begin
            cur_op <= 2'd0;
            cur_ch <= 3'd0;
            zero   <= 1'b1;
        end else if( clk_en ) begin
            { cur_op, cur_ch } <= { next_op, next_ch };
            zero <= next == 5'd0;
        end
    end
end
"""


def digest(text: str) -> str:
    return sha256(text.encode()).hexdigest()


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(
            "usage: apply_jt10_counter_reset_compat.py TEMP_SOURCE_ROOT"
        )

    path = (
        Path(sys.argv[1])
        / "rtl/genesis_audio/jt12/jt12_reg.v"
    )
    before = path.read_text()
    legacy_count = before.count(LEGACY_BLOCK)
    reset_count = before.count(RESET_BLOCK)

    if legacy_count == 1 and reset_count == 0:
        after = before.replace(LEGACY_BLOCK, RESET_BLOCK, 1)
        # Reversing only the intended replacement must recover every byte.
        if after.replace(RESET_BLOCK, LEGACY_BLOCK, 1) != before:
            raise SystemExit(f"{path}: reset-only reverse check failed")
        path.write_text(after)
        action = "applied"
    elif legacy_count == 0 and reset_count == 1:
        after = before
        action = "already-applied"
    else:
        raise SystemExit(
            f"{path}: expected one legacy or patched counter block "
            f"(legacy={legacy_count}, patched={reset_count})"
        )

    if after.count("{ cur_op, cur_ch } <= { next_op, next_ch };") != 2:
        raise SystemExit(f"{path}: sequencer recurrence count changed")
    if after.count("zero <= next == 5'd0;") != 2:
        raise SystemExit(f"{path}: zero recurrence count changed")

    print(
        "JT10_COUNTER_RESET "
        f"{action} sha256={digest(after)} reset_only=PASS"
    )


if __name__ == "__main__":
    main()
