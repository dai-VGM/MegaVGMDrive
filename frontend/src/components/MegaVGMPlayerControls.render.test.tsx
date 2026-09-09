import React from "react";
import { renderToStaticMarkup } from "react-dom/server";

import MegaVGMPlayerControls from "./MegaVGMPlayerControls";
import { MegaVGMRepeatMode } from "./megavgmPlaybackMode";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

function render(repeat: MegaVGMRepeatMode, shuffle: boolean): string {
  return renderToStaticMarkup(
    <MegaVGMPlayerControls
      navigationDisabled={false}
      stopDisabled={false}
      repeat={repeat}
      repeatDisabled={false}
      shuffle={shuffle}
      shuffleDisabled={false}
      onPrevious={() => undefined}
      onStop={() => undefined}
      onNext={() => undefined}
      onRepeat={() => undefined}
      onShuffle={() => undefined}
    />
  );
}

for (const mode of ["OFF", "ONE", "ALL"] as const) {
  const html = render(mode, mode === "ALL");
  const labels = [...html.matchAll(/<button[^>]*aria-label="([^"]+)"/g)].map(
    (m) => m[1]
  );
  assert(
    JSON.stringify(labels) ===
      JSON.stringify([
        "Shuffle",
        "Previous track",
        "Stop",
        "Next track",
        "Repeat",
      ]),
    "five-control order"
  );
  assert(
    html.includes('aria-label="Repeat" aria-haspopup="menu"'),
    "repeat menu missing"
  );
  assert(
    html.includes("min-width:48px") && html.includes("min-height:48px"),
    "48px targets"
  );
  assert(
    html.includes("width:52px") && html.includes("height:52px"),
    "52px Stop size"
  );
  assert(html.includes("border-radius:50%"), "Stop must be circular");
  assert(html.includes("max-width:380px"), "centered controls");
  assert(
    html.includes(
      mode === "ALL"
        ? 'data-testid="AllInclusiveIcon"'
        : 'data-testid="RepeatIcon"'
    ),
    "repeat icon mapping"
  );
  assert(
    html.includes("font-size:22px") &&
      html.includes("transform:scale(0.94)") &&
      html.includes("#AAB8C8") &&
      html.includes("#40C5D8"),
    "control visual contract"
  );
  assert(
    html.includes('aria-pressed="' + (mode !== "OFF") + '"'),
    "repeat active mapping"
  );
}
console.log("Mini player control rendering: PASS");
