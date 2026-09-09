import { RefObject, useLayoutEffect, useRef } from "react";

// Only the content viewport scrolls. Keep positions per view, not per
// playback session. Query/status refreshes must not initiate another restore.
export function useMegaVGMScroll(
  key: string,
  ready: boolean,
  viewport: RefObject<HTMLDivElement>
) {
  const positions = useRef(new Map<string, number>());
  const restored = useRef<string>();
  const activeKey = useRef(key);

  const remember = () => {
    if (restored.current === activeKey.current) {
      positions.current.set(
        activeKey.current,
        viewport.current?.scrollTop ?? 0
      );
    }
  };

  useLayoutEffect(() => {
    activeKey.current = key;
    restored.current = undefined;
    // Data can arrive after navigation. Do not lose a saved offset while the
    // temporarily short loading placeholder clamps document scroll height.
  }, [key]);

  useLayoutEffect(() => {
    const element = viewport.current;
    if (!element) return;
    if (ready && restored.current !== key) {
      element.scrollTop = positions.current.get(key) ?? 0;
      restored.current = key;
    }
    const onScroll = () => remember();
    element.addEventListener("scroll", onScroll, { passive: true });
    return () => element.removeEventListener("scroll", onScroll);
  }, [key, ready]);

  return remember;
}
