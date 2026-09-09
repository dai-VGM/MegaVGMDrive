import {
  repeatCommand,
  repeatMode,
  toggleRepeatMode,
} from "./megavgmPlaybackMode";

function assert(condition: boolean, message: string): void {
  if (!condition) throw new Error(message);
}

assert(repeatMode() === "OFF", "legacy/missing status must default to OFF");
assert(toggleRepeatMode("OFF", "ONE") === "ONE", "One must enable from OFF");
assert(toggleRepeatMode("ONE", "ONE") === "OFF", "active One must disable");
assert(toggleRepeatMode("ALL", "ONE") === "ONE", "One must replace All");
assert(toggleRepeatMode("OFF", "ALL") === "ALL", "All must enable from OFF");
assert(toggleRepeatMode("ALL", "ALL") === "OFF", "active All must disable");
assert(toggleRepeatMode("ONE", "ALL") === "ALL", "All must replace One");
assert(repeatCommand("ONE") === "one", "controller command must be lowercase");
assert(repeatCommand("ALL") === "all", "Repeat All command must be preserved");
assert(repeatCommand("OFF") === "off", "Repeat Off command must be preserved");
