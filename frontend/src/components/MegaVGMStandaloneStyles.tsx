import GlobalStyles from "@mui/material/GlobalStyles";

// Adapt the v2.0 PASS root contract, not the Remote fixed-header/spacer layout.
// Our header is in normal flex flow; main must consume only the remaining space.
export default function MegaVGMStandaloneStyles() {
  return <GlobalStyles styles={{
    "@media (display-mode: standalone)": {
      "html, html body, html body #root": {
        height: "100vh",
        minHeight: "100vh",
        maxHeight: "100vh",
        margin: 0,
        overflow: "hidden",
        overscrollBehavior: "none",
        backgroundColor: "#10151C",
      },
      "@supports (height: 100lvh)": {
        "html, html body, html body #root": {
          height: "100lvh",
          minHeight: "100lvh",
          maxHeight: "100lvh",
        },
      },
      "[data-standalone-shell]": {
        height: "100%",
        maxHeight: "100%",
        minHeight: 0,
        overflow: "hidden",
      },
      "[data-standalone-shell] > main": {
        minHeight: 0,
        boxSizing: "border-box",
      },
      "[data-standalone-shell] [data-testid=mini-player], [data-standalone-shell] [data-testid=player-shell] > nav": {
        flex: "0 0 auto",
      },
    },
  }} />;
}
