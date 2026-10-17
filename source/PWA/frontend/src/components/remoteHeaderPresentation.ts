export const MEGAVGM_HEADER_BACKGROUND = "#18212B";
export const MEGAVGM_HEADER_FOREGROUND = "#E8EEF4";
export const MEGAVGM_HEADER_ACCENT = "#49C6D8";
export const MEGAVGM_HEADER_SIDE_WIDTH_PX = 44;
export const MEGAVGM_HEADER_GAP_PX = 4;
export const MEGAVGM_HEADER_TITLE = "MegaVGMPlayer";
export const MEGAVGM_HEADER_LOGO =
  "/megavgm-header-wordmark-transparent-v2.png";
export const MEGAVGM_HEADER_LOGO_STYLE = {
  display: "block",
  width: "100%",
  maxWidth: 196,
  height: 34,
  objectFit: "contain",
  justifySelf: "center",
  minWidth: 0,
};

export function isMegaVGMRoute(pathname: string): boolean {
  return pathname === "/megavgm" || pathname.startsWith("/megavgm/");
}
