import { MegaVGMStatus } from "../lib/models";

export type MegaVGMRepeatMode = "OFF" | "ONE" | "ALL";

export function repeatMode(status?: MegaVGMStatus): MegaVGMRepeatMode {
  return status?.repeat ?? "OFF";
}

export function toggleRepeatMode(
  mode: MegaVGMRepeatMode,
  selected: Exclude<MegaVGMRepeatMode, "OFF">
): MegaVGMRepeatMode {
  return mode === selected ? "OFF" : selected;
}

export function repeatCommand(mode: MegaVGMRepeatMode): "off" | "one" | "all" {
  return mode.toLowerCase() as "off" | "one" | "all";
}
