import React from "react";
import ReactDOM from "react-dom/client";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { ThemeProvider, createTheme } from "@mui/material/styles";
import CssBaseline from "@mui/material/CssBaseline";
import GlobalStyles from "@mui/material/GlobalStyles";
import Box from "@mui/material/Box";
import MegaVGMPlayer from "./components/MegaVGMPlayer";
import MegaVGMStandaloneStyles from "./components/MegaVGMStandaloneStyles";
import { getTheme } from "./lib/themes";
import { MEGAVGM_HEADER_LOGO, MEGAVGM_HEADER_LOGO_STYLE } from "./components/remoteHeaderPresentation";
import "@fontsource/roboto/300.css";
import "@fontsource/roboto/400.css";
import "@fontsource/roboto/500.css";
import "@fontsource/roboto/700.css";

const queryClient = new QueryClient();
const theme = createTheme(getTheme("dark").options);

// One scroll owner: the unchanged Player's music-content element.
// The v2.0 standalone viewport choice (lvh) is retained for iOS hardware.
function Shell() {
  return <>
    <CssBaseline />
    <GlobalStyles styles={{
      "html, body, #root": { height: "100%", margin: 0, overflow: "hidden", overscrollBehavior: "none", backgroundColor: "#10151C" },
      "[data-standalone-shell]": { height: "100vh", display: "flex", flexDirection: "column", overflow: "hidden" },
      "@supports (height: 100dvh)": { "[data-standalone-shell]": { height: "100dvh" } },
      "[data-standalone-shell] > main": { flex: "1 1 0", minHeight: 0, minWidth: 0, display: "flex", flexDirection: "column", overflow: "hidden", paddingLeft: "env(safe-area-inset-left)", paddingRight: "env(safe-area-inset-right)" },
      "[data-standalone-shell] [data-testid=player-shell]": { flex: "1 1 0", height: "auto", minHeight: 0, overflow: "hidden" },
      "[data-standalone-shell] [data-testid=music-content]": { flex: "1 1 0", minHeight: 0, overflowY: "auto", overflowX: "hidden", overscrollBehavior: "none", WebkitOverflowScrolling: "touch" },
    }} />
    <MegaVGMStandaloneStyles />
    <Box data-standalone-shell>
      <Box component="header" sx={{ flex: "0 0 auto", backgroundColor: "#18212B", paddingTop: "env(safe-area-inset-top)", paddingLeft: "env(safe-area-inset-left)", paddingRight: "env(safe-area-inset-right)" }}>
        <Box sx={{ height: { xs: 44, sm: 64 }, display: "flex", alignItems: "center", justifyContent: "center" }}>
          <Box component="img" src={MEGAVGM_HEADER_LOGO} alt="MegaVGMPlayer / FPGA MUSIC PLAYER" width={1851} height={300} sx={MEGAVGM_HEADER_LOGO_STYLE} />
        </Box>
      </Box>
      <Box component="main"><MegaVGMPlayer /></Box>
    </Box>
  </>;
}
ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode><QueryClientProvider client={queryClient}><ThemeProvider theme={theme}><Shell /></ThemeProvider></QueryClientProvider></React.StrictMode>
);
