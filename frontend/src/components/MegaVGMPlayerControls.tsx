import { useState } from "react";
import Box from "@mui/material/Box";
import IconButton from "@mui/material/IconButton";
import Menu from "@mui/material/Menu";
import MenuItem from "@mui/material/MenuItem";
import AllInclusiveIcon from "@mui/icons-material/AllInclusive";
import RepeatIcon from "@mui/icons-material/Repeat";
import ShuffleIcon from "@mui/icons-material/Shuffle";
import SkipNextIcon from "@mui/icons-material/SkipNext";
import SkipPreviousIcon from "@mui/icons-material/SkipPrevious";
import StopIcon from "@mui/icons-material/Stop";
import { MegaVGMRepeatMode } from "./megavgmPlaybackMode";

interface MegaVGMPlayerControlsProps {
  navigationDisabled: boolean;
  stopDisabled: boolean;
  repeat: MegaVGMRepeatMode;
  repeatDisabled: boolean;
  shuffle: boolean;
  shuffleDisabled: boolean;
  onPrevious: () => void;
  onStop: () => void;
  onNext: () => void;
  onRepeat: (mode: MegaVGMRepeatMode) => void;
  onShuffle: (enabled: boolean) => void;
}
const activeColor = "#40C5D8";
const inactiveColor = "#AAB8C8";
function controlSx(active = false) {
  return {
    width: 48,
    height: 48,
    minWidth: 48,
    minHeight: 48,
    border: 0,
    borderRadius: "50%",
    color: active ? activeColor : inactiveColor,
    bgcolor: "transparent",
    transition: "transform 100ms ease, background-color 100ms ease",
    "& .MuiSvgIcon-root": { fontSize: 22 },
    "&:hover": { bgcolor: "rgba(64,197,216,0.08)" },
    "&:active": {
      bgcolor: "rgba(64,197,216,0.14)",
      transform: "scale(0.94)",
    },
    "&.Mui-disabled": { color: "rgba(154,169,183,0.36)" },
  };
}
export default function MegaVGMPlayerControls({
  navigationDisabled,
  stopDisabled,
  repeat,
  repeatDisabled,
  shuffle,
  shuffleDisabled,
  onPrevious,
  onStop,
  onNext,
  onRepeat,
  onShuffle,
}: MegaVGMPlayerControlsProps) {
  const [repeatAnchor, setRepeatAnchor] = useState<HTMLElement | null>(null);
  return (
    <Box
      role="group"
      aria-label="Player controls"
      sx={{
        width: "100%",
        maxWidth: 380,
        mx: "auto",
        display: "flex",
        justifyContent: "space-evenly",
        alignItems: "center",
        gap: 0.5,
        minHeight: 56,
      }}
    >
      <IconButton
        className="MegaVGM-playerControl"
        aria-label="Shuffle"
        aria-pressed={shuffle}
        disabled={shuffleDisabled}
        onClick={() => onShuffle(!shuffle)}
        sx={controlSx(shuffle)}
      >
        <ShuffleIcon />
      </IconButton>
      <IconButton
        className="MegaVGM-playerControl"
        aria-label="Previous track"
        disabled={navigationDisabled}
        onClick={onPrevious}
        sx={controlSx()}
      >
        <SkipPreviousIcon />
      </IconButton>
      <IconButton
        className="MegaVGM-playerControl"
        aria-label="Stop"
        disabled={stopDisabled}
        onClick={onStop}
        sx={{
          ...controlSx(),
          width: 52,
          height: 52,
          minWidth: 52,
          minHeight: 52,
          borderRadius: "50%",
          bgcolor: activeColor,
          color: "#101820",
          "&:hover": { bgcolor: "#77DDE8" },
          "&:active": { bgcolor: "#77DDE8", transform: "scale(0.94)" },
          "&.Mui-disabled": {
            bgcolor: "rgba(73,198,216,0.18)",
            color: "rgba(154,169,183,0.36)",
          },
        }}
      >
        <StopIcon />
      </IconButton>
      <IconButton
        className="MegaVGM-playerControl"
        aria-label="Next track"
        disabled={navigationDisabled}
        onClick={onNext}
        sx={controlSx()}
      >
        <SkipNextIcon />
      </IconButton>
      <IconButton
        className="MegaVGM-playerControl"
        aria-label="Repeat"
        aria-haspopup="menu"
        aria-expanded={!!repeatAnchor}
        aria-pressed={repeat !== "OFF"}
        disabled={repeatDisabled}
        onClick={(event) => setRepeatAnchor(event.currentTarget)}
        sx={controlSx(repeat !== "OFF")}
      >
        <Box sx={{ position: "relative", width: 22, height: 22 }}>
          <RepeatIcon sx={{ position: "absolute", inset: 0 }} />
          {repeat === "ONE" && (
            <Box
              component="span"
              aria-hidden="true"
              sx={{
                position: "absolute",
                right: -2,
                bottom: -3,
                fontSize: 9,
                lineHeight: 1,
                fontWeight: 700,
              }}
            >
              1
            </Box>
          )}
          {repeat === "ALL" && (
            <AllInclusiveIcon
              aria-hidden="true"
              sx={{
                position: "absolute",
                right: -4,
                bottom: -4,
                width: 11,
                height: 11,
                fontSize: 11,
              }}
            />
          )}
        </Box>
      </IconButton>
      <Menu
        anchorEl={repeatAnchor}
        open={!!repeatAnchor}
        onClose={() => setRepeatAnchor(null)}
        MenuListProps={{ "aria-label": "Repeat mode" }}
        PaperProps={{ sx: { bgcolor: "#18212B", color: "#E8EEF4" } }}
      >
        {(["OFF", "ONE", "ALL"] as const).map((mode) => (
          <MenuItem
            key={mode}
            selected={repeat === mode}
            disabled={repeatDisabled}
            onClick={() => {
              setRepeatAnchor(null);
              onRepeat(mode);
            }}
            sx={{
              minHeight: 44,
              "&.Mui-selected": {
                color: activeColor,
                bgcolor: "rgba(73,198,216,0.12)",
              },
            }}
          >
            {mode === "OFF"
              ? "Repeat off"
              : mode === "ONE"
              ? "Repeat one"
              : "Repeat current context"}
          </MenuItem>
        ))}
      </Menu>
    </Box>
  );
}
