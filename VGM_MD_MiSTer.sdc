# Minimal timing constraints for the first VGM MD Quartus skeleton.
#
# A full MiSTer template normally provides sys_top-specific clocks, generated
# clocks, and interface constraints. Keep this file small until a known-working
# template sys_top is imported.

create_clock -name CLK_50M -period 20.000 [get_ports {CLK_50M}]

derive_pll_clocks
derive_clock_uncertainty
