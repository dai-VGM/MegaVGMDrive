// DOM integration: run bundled with jsdom and fake timers initialized first.
// No backend, controller or hardware calls: the existing axios transport is stubbed.
import React from "react";
import { createRoot } from "react-dom/client";
import { act } from "react-dom/test-utils";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import axios from "axios";
import MegaVGMPlayer, { MegaVGMTab } from "./MegaVGMPlayer";
import type { MegaVGMStatus } from "../lib/models";

function assert(v: unknown, text: string): asserts v {
  if (!v) throw new Error(text);
}
const clock = (globalThis as any).testClock;
const names = [
  "01 Coin",
  "02 Effect",
  "03 Effect",
  "04 Urban Trail",
  "05 Next",
];
const entries = names.map((title) => ({
  title,
  filename: `${title}.vgm`,
  path: `/media/fat/MegaVGMDrive/Night Striker/${title}.vgm`,
  directory: "Night Striker",
  available: true,
}));
const browsePath = "Night Striker";
const browseEntries = names.map((title) => ({
  name: `${title}.vgm`,
  type: "file" as const,
}));
const stock: MegaVGMStatus = {
  mode: "STOCK",
  main: "STOCK",
  supervisorController: "STOPPED",
  controllerRunning: false,
};
const playing = (n: number, session = n, state = "PLAYING"): MegaVGMStatus => ({
  mode: "MEGAVGM",
  main: "MODIFIED",
  supervisorController: "RUNNING",
  controllerRunning: true,
  state,
  session,
  index: n,
  count: 5,
  path: entries[n - 1].path,
  title: names[n - 1],
  context: "PLAYLIST",
  playlist: "Favorites",
  repeat: "OFF",
  shuffle: false,
  clientPollStartedMs: performance.now(),
  clientPollReceivedMs: performance.now(),
});
const directoryPlaying = (
  n: number,
  session = n,
  state = "PLAYING"
): MegaVGMStatus => ({
  ...playing(n, session, state),
  context: "DIRECTORY",
  playlist: undefined,
});

interface PendingRequest {
  endpoint: "browse" | "playlist";
  index: number;
  path: string;
  resolve: () => void;
  reject: () => void;
}

async function scenario(
  name: string,
  run: (h: any) => Promise<void>,
  initial = stock,
  initialTab: MegaVGMTab = "playlists"
) {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false, cacheTime: Infinity } },
  });
  let current = initial;
  const requests: PendingRequest[] = [];
  axios.defaults.adapter = async (config) => {
    let data: any = {};
    if (config.url === "/megavgm/status") data = current;
    else if (config.url === "/megavgm/playlists")
      data = {
        version: 1,
        playlists: [
          { name: "Favorites", reserved: true, count: 5, availableCount: 5 },
        ],
      };
    else if (config.url === "/megavgm/playlists/Favorites")
      data = { version: 1, name: "Favorites", reserved: true, entries };
    else if (config.url === "/megavgm/favorites")
      data = { version: 1, playlist: "Favorites", entries };
    else if (config.url === "/megavgm/browse")
      data = { path: browsePath, parent: "", entries: browseEntries };
    else if (config.url === "/megavgm/play") {
      const path = JSON.parse(config.data).path;
      const index = browseEntries.findIndex(
        (entry) => `${browsePath}/${entry.name}` === path
      );
      assert(index >= 0, `${name}: unknown Browse path ${path}`);
      await new Promise<void>((resolve, reject) =>
        requests.push({
          endpoint: "browse",
          index,
          path,
          resolve,
          reject: () => reject(new Error("fixture rejection")),
        })
      );
      data = {
        accepted: true,
        mode: "MEGAVGM",
        path: entries[index].path,
      };
    } else if (config.url?.endsWith("/play")) {
      const index = JSON.parse(config.data).index;
      await new Promise<void>((resolve, reject) =>
        requests.push({
          endpoint: "playlist",
          index,
          path: entries[index].path,
          resolve,
          reject: () => reject(new Error("fixture rejection")),
        })
      );
      data = {
        accepted: true,
        mode: "MEGAVGM",
        playlist: "Favorites",
        path: entries[index].path,
        index,
        count: 5,
      };
    }
    return {
      data,
      status: config.method === "post" ? 202 : 200,
      statusText: "OK",
      headers: {},
      config,
    };
  };
  client.setQueryData(["megavgm", "status"], initial);
  client.setQueryData(["megavgm", "favorites"], {
    version: 1,
    playlist: "Favorites",
    entries,
  });
  client.setQueryData(["megavgm", "playlists"], {
    version: 1,
    playlists: [
      { name: "Favorites", reserved: true, count: 5, availableCount: 5 },
    ],
  });
  client.setQueryData(["megavgm", "playlist", "Favorites"], {
    version: 1,
    name: "Favorites",
    reserved: true,
    entries,
  });
  client.setQueryData(["megavgm", "browse", browsePath], {
    path: browsePath,
    parent: "",
    entries: browseEntries,
  });
  const container = document.createElement("div");
  document.body.appendChild(container);
  const root = createRoot(container);
  const flush = () =>
    act(async () => {
      await clock.tickAsync(1);
    });
  const rows = () =>
    Array.from(container.querySelectorAll("[data-track-state]"));
  const state = (n: number) => rows()[n - 1]?.getAttribute("data-track-state");
  const click = async (button: HTMLButtonElement | null) => {
    assert(button, `${name}: button missing`);
    await act(async () => {
      button.click();
    });
    await flush();
  };
  await act(async () => {
    root.render(
      <QueryClientProvider client={client}>
        <MegaVGMPlayer initialTab={initialTab} initialBrowsePath={browsePath} />
      </QueryClientProvider>
    );
  });
  await flush();
  try {
    await run({
      requests,
      state,
      tap: (n: number) => click(rows()[n - 1]?.querySelector("button") || null),
      control: (label: string) =>
        click(container.querySelector(`button[aria-label="${label}"]`)),
      exit: async () => {
        await click(
          container.querySelector('button[aria-label="Player options"]')
        );
        await click(
          (Array.from(
            document.querySelectorAll<HTMLElement>('[role="menuitem"]')
          ).find(
            (item) => item.textContent === "Exit MegaVGMPlayer"
          ) as HTMLButtonElement) || null
        );
      },
      publish: async (s: MegaVGMStatus) => {
        await clock.tickAsync(2);
        current = {
          ...s,
          clientPollStartedMs: performance.now(),
          clientPollReceivedMs: performance.now(),
        };
        await act(async () => {
          client.setQueryData(["megavgm", "status"], current);
        });
        await flush();
      },
      ack: async (i = 0) => {
        await act(async () => {
          requests[i].resolve();
        });
        await flush();
      },
      fail: async (i = 0) => {
        await act(async () => {
          requests[i].reject();
        });
        await flush();
      },
      advance: async (ms: number) => {
        await act(async () => {
          await clock.tickAsync(ms);
        });
        await flush();
      },
      text: () => container.textContent || "",
    });
    console.log(`React DOM ${name}: PASS`);
  } finally {
    await act(async () => root.unmount());
    client.clear();
    container.remove();
  }
}

export async function main() {
  for (const profileChanged of [false, true]) {
    await scenario(
      `Browse cold immediate ${
        profileChanged ? "cross-engine" : "same-engine"
      } retarget`,
      async (h) => {
        await h.tap(1);
        assert(h.requests.length === 1, "first Browse POST was not dispatched");
        assert(
          h.requests[0].endpoint === "browse" &&
            h.requests[0].path === `${browsePath}/${browseEntries[0].name}`,
          "first Browse POST payload mismatch"
        );

        const firstTransport = {
          epoch: "megavgm-browse-cold.fixture",
          switchGeneration: "1",
          switchState: "PLAYING" as const,
          currentProfile: "PROFILE_A" as const,
          requiredProfile: "PROFILE_A" as const,
          domain: "1",
          baseline: 0,
          profileChanged: false,
          path: entries[0].path,
        };
        await h.publish({
          ...directoryPlaying(1, 1),
          transport: firstTransport,
        });
        assert(h.state(1) === "playing", "first Browse track not PLAYING");

        // The first cold-start HTTP request intentionally remains unsettled.
        // A second row tap must still dispatch its own POST immediately.
        await h.tap(2);
        assert(
          h.requests.length === 2,
          "second Browse tap was queued instead of issuing HTTP"
        );
        assert(
          h.requests[1].endpoint === "browse" &&
            h.requests[1].path === `${browsePath}/${browseEntries[1].name}`,
          "second Browse POST payload mismatch"
        );

        const secondTransport = {
          ...firstTransport,
          switchGeneration: "2",
          switchState: "SWITCHING" as const,
          requiredProfile: profileChanged
            ? ("PROFILE_D" as const)
            : ("PROFILE_A" as const),
          profileChanged,
          path: entries[1].path,
        };
        await h.publish({
          ...directoryPlaying(2, 2, "LOADING"),
          transport: secondTransport,
        });
        assert(h.state(2) === "pending", "second Browse LOADING not shown");
        await h.ack(1);
        await h.publish({
          ...directoryPlaying(2, 2),
          transport: {
            ...secondTransport,
            switchState: "PLAYING" as const,
            currentProfile: secondTransport.requiredProfile,
          },
        });
        assert(h.state(2) === "playing", "second Browse track not PLAYING");

        await h.ack(0);
        assert(
          h.state(1) === "idle" && h.state(2) === "playing",
          "late first Browse response overrode the newer selection"
        );
      },
      stock,
      "browse"
    );
  }

  await scenario(
    "Browse rapid taps dispatch and latest selection wins",
    async (h) => {
      await h.tap(1);
      await h.tap(2);
      await h.tap(3);
      assert(h.requests.length === 3, "rapid Browse POSTs were serialized");
      assert(
        h.requests.every(
          (request: PendingRequest, index: number) =>
            request.endpoint === "browse" && request.index === index
        ),
        "rapid Browse POST order mismatch"
      );
      await h.ack(0);
      await h.ack(1);
      assert(h.state(3) === "pending", "older ACK retired latest Browse tap");
      await h.publish(directoryPlaying(3, 3));
      await h.ack(2);
      assert(h.state(3) === "playing", "latest Browse selection did not win");
    },
    stock,
    "browse"
  );

  await scenario("A/E short cold before ACK", async (h) => {
    await h.tap(1);
    assert(h.state(1) === "pending", "tap must show loading");
    await h.publish(playing(1));
    assert(h.state(1) === "playing", "pre-ACK playing must clear spinner");
    await h.publish(playing(1, 1, "ENDED"));
    for (const n of [2, 3, 4]) await h.publish(playing(n));
    await h.ack();
    assert(
      h.state(1) === "idle" && h.state(4) === "playing",
      "late ACK restored 01"
    );
    await h.advance(9000);
    assert(!h.text().includes("timed out"), "false timeout");
  });
  await scenario("B/J ACK first, long track", async (h) => {
    await h.tap(1);
    await h.ack();
    await h.publish(playing(1));
    await h.advance(9000);
    assert(h.state(1) === "playing", "long track lost state");
    await h.publish(playing(2));
    assert(h.state(1) === "idle", "old marker");
  });
  await scenario("C missed selected PLAYING", async (h) => {
    await h.tap(1);
    await h.publish(playing(2));
    await h.ack();
    assert(
      h.state(1) === "idle" && h.state(2) === "playing",
      "missed interval stuck"
    );
  });
  await scenario("D newer request beats late ACK", async (h) => {
    await h.tap(1);
    await h.tap(5);
    assert(
      h.requests.length === 2 &&
        h.requests.every(
          (request: PendingRequest) => request.endpoint === "playlist"
        ),
      "Favorites direct selections were not dispatched immediately"
    );
    await h.ack(0);
    assert(
      h.state(1) === "idle" && h.state(5) === "pending",
      "old callback mutated new receipt"
    );
    await h.publish(playing(5));
    await h.ack(1);
    assert(h.state(5) === "playing", "new request did not settle");
  });
  for (const control of ["Next track", "Previous track", "Stop"]) {
    await scenario(
      `G/H ${control}`,
      async (h) => {
        await h.tap(1);
        await h.control(control);
        await h.ack();
        assert(h.state(1) !== "pending", `${control} did not supersede`);
      },
      playing(4, 20)
    );
  }
  await scenario("I explicit failure", async (h) => {
    await h.tap(1);
    await h.fail();
    assert(h.text().includes("could not be started"), "real failure hidden");
    assert(h.state(1) !== "pending", "failure spinner");
  });
  await scenario(
    "Exit supersedes pending",
    async (h) => {
      await h.tap(1);
      await h.exit();
      await h.ack();
      assert(h.state(1) !== "pending", "Exit late ACK resurrected spinner");
    },
    playing(4, 20)
  );
  await scenario(
    "100 warm/short transitions",
    async (h) => {
      for (let session = 21; session < 121; session++) {
        const n = (session % 5) + 1;
        await h.tap(n);
        await h.publish(playing(n, session));
        await h.ack(session - 21);
        assert(h.state(n) === "playing", `session ${session} stuck`);
      }
      assert(!h.text().includes("timed out"), "stress false timeout");
    },
    playing(4, 20)
  );
  await scenario(
    "F warm",
    async (h) => {
      await h.tap(1);
      await h.ack();
      await h.publish(playing(1, 21));
      assert(h.state(1) === "playing", "warm stuck");
    },
    playing(4, 20)
  );
  await scenario("8s HTTP-unsettled cleanup", async (h) => {
    await h.tap(1);
    await h.advance(8100);
    assert(h.state(1) !== "pending", "unbounded HTTP spinner");
    assert(!h.text().includes("timed out"), "timeout masquerades as failure");
    await h.ack();
    assert(h.state(1) !== "pending", "late ACK re-armed expiry");
  });
  for (const changed of [false, true]) {
    await scenario(
      `authoritative ${changed ? "switch" : "same-profile"} label`,
      async (h) => {
        const transport = {
          epoch: "megavgm-phase2a.fixture",
          switchGeneration: "7",
          switchState: "SWITCHING",
          currentProfile: "PROFILE_A",
          requiredProfile: "PROFILE_B",
          domain: "1",
          baseline: 0,
          profileChanged: changed,
          path: entries[0].path,
        };
        await h.tap(1);
        await h.publish({ ...playing(1, 21, "LOADING"), transport });
        assert(
          h.text().includes(changed ? "Switching…" : "Loading…"),
          "wrong pending label"
        );
        await h.publish({
          ...playing(1, 21),
          transport: {
            ...transport,
            switchState: "PLAYING",
            currentProfile: "PROFILE_B",
          },
        });
        await h.ack();
        assert(
          !h.text().includes("Switching…") && h.state(1) === "playing",
          "completed switch stuck"
        );
        await h.publish({ ...playing(1, 21), transport });
        assert(
          !h.text().includes("Switching…"),
          "late active telemetry resurrected spinner"
        );
        await h.tap(2);
        await h.publish({
          ...playing(2, 22, "LOADING"),
          transport: {
            ...transport,
            switchGeneration: "8",
            path: entries[1].path,
            profileChanged: true,
          },
        });
        await h.control("Stop");
        assert(
          !h.text().includes("Switching…") && h.state(2) !== "pending",
          "Stop did not retire display"
        );
      },
      playing(4, 20)
    );
  }
  const baselineTransport = {
    epoch: "megavgm-phase2a.rebase",
    switchGeneration: "40",
    switchState: "PLAYING" as const,
    currentProfile: "PROFILE_A" as const,
    requiredProfile: "PROFILE_A" as const,
    domain: "4",
    baseline: 1,
    profileChanged: false,
    path: entries[3].path,
  };
  await scenario(
    "Volfied long load with same-number session rebase",
    async (h) => {
      await h.tap(1);
      const engineC = {
        ...baselineTransport,
        switchGeneration: "41",
        switchState: "READY" as const,
        currentProfile: "PROFILE_C" as const,
        requiredProfile: "PROFILE_C" as const,
        domain: "5",
        baseline: 0,
        profileChanged: true,
        // Prepared path is transport-only; Player identity remains entries[0].path.
        path: "/media/fat/MegaVGMPlayer/cache/sid/key.mvgmsid",
      };
      await h.publish({ ...playing(1, 1, "LOADING"), transport: engineC });
      await h.advance(9000);
      assert(
        h.state(1) === "pending" && h.text().includes("Loading…"),
        "long authoritative LOADING was not retained"
      );
      await h.publish({
        ...playing(1, 1, "PLAYING"),
        transport: { ...engineC, switchState: "PLAYING" as const },
      });
      assert(
        h.state(1) === "playing" && !h.text().includes("Loading…"),
        "authoritative PLAYING did not clear row/bottom Loading"
      );
      await h.ack();
      assert(h.state(1) === "playing", "late HTTP ACK revived Loading");
    },
    { ...playing(4, 1), transport: baselineTransport }
  );
}
