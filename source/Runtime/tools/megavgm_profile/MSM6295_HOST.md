# Engine D isolated Host MSM6295 admission

This is a Host classifier vocabulary extension, default OFF (`MEGAVGM_HOST_MSM6295=0`). The fixed D candidate is explicitly built with `=1`. Existing Generic WRITE/Profile D wire value 6, SwitchOwner, Controller, Supervisor, Remote state transitions and FPGA parser are unchanged. Input VGM bytes and original paths remain unchanged.

Authority: canonical Platform/Engine Contract and Bringup Runbook, 2026-10-13; D FPGA capability source `73a5b2f60a0917570d820259bb218f18e4ac4927`. VGM B8 encodes MSM register writes as specified at https://vgmrips.theclassicgamer.net/VGM_Specification (B8 is OKIM6295, not HuC6280 B9); ROM block 8B is OKIM6295. The candidate admits only the current D FPGA subset, not all possible VGM features.

B8 is a three-byte Generic WRITE; operand bit 7 selects chip instance, low 7 bits are register. Single instance only; registers 0,8..12,15; clock <=4MHz and bank/pin7 0/1. MSM clock header/version, required D YM2151 header, clock updates, ROM capacity/order/spans, paired key-on and loop state are checked. 8B and C140 8D ROM blocks remain distinct. Unsupported mixtures, dual instance, unknown register, bad clock, oversized/overlapping ROM, incomplete command and missing resident ROM are rejected. Resource preparation/pass1 and actual audio remain FPGA gates.

Actual write commands determine sound-chip metadata. YM2151, C140 and MSM6295 labels share existing Runtime/Remote/PWA metadata fields. Clocks or a ROM block alone do not fabricate chip activity. A/B/C/E/F and existing C140/YM routes are covered by the existing suite and default-OFF suite.

Reproduce: `MEGAVGM_HOST_MSM6295=1 sh tools/megavgm_profile/build_and_test.sh NEW_ABSOLUTE_OUT host` (or arm using existing GCC10/QEMU Lima). Run `run_msm6295_regression.py --binaries OUT --corpus SAVED_FIXTURES --audit fixture-audit.json --out NEW_REPORT` against the 64 immutable local real VGMs. This compares full-file command counts/identity against the independent previous audit and exercises existing generic Controller with mock Main. It does not render audio or prove hardware compatibility. Negative controls deliberately drop B8, misroute 8B and remove the dual-clock check and must fail. Never compile a mutable shared VM worktree: archive committed inputs into a fresh VM directory and hash the actual extracted inputs.

No FPGA RTL, canonical source, SDC, existing package or production edits. Hardware integration and SSH authentication changes require separate approval. Production HOLD.
