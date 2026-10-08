# Phase 1 findings — 2026-10-08

## Accepted identities and source graph

All four proposed Mac RBFs exist and match the recorded SHA256/size. A/B/D source ZIPs were freshly extracted: 195/161/132 committed build inputs verified byte-for-byte to their pinned source commits, with JT51 gitlinks handled. Root QPF, revision, top sys_top, device 5CSEBA6U23I7, defines, package order, relative graph, member hashes and no duplicate/stale source passed each engine's current validator. BUILD.bat is not required. This is source/archive validation, not a new synthesis or hardware test.

C remains entirely unchanged. Its 71 HDL sources and 89 required inputs/includes match commit 82402ec. Three absent .cmp files are editor component templates, not synthesis inputs. The original legacy graph and generated build-id behavior are recorded without rewriting C. No root-layout C Build Artifact was found, and no replacement was invented. Windows C's retained older RBF hash differs from the accepted v2.3 registry/Mac RBF: it cannot prove the selected C build.

The current Runtime explicitly selects `/media/fat/_Custom Cores/Cores/MegaVGMDrive_{A,B,C,D}.rbf`. Build revision names are distinct from these deployed names. CORENAME remains MegaVGMDrive and PROFILE_A/B/C/D assignments remain unchanged. No deployment/renaming has been performed. User-reported PWA switching/playback acceptance is recorded; no new on-device test is claimed.

## Common infrastructure

The 10 common Parser/Reader/Scheduler files in A/B/D source artifacts are byte-identical. D's existing Transport owner adds DIRECT_LOAD_REARM gating and envelope re-arm on index-1 load; it originates in commit 5cf9fae (two-loop integration). A/B retain the other owner body. The exact diff is saved. This integration must preserve independent bindings, not force common Transport bytes or impose VGM scheduling on C's native-cycle SID.

OSD profiles also have intentional source differences: A e18264ed… versus B/D 4d57135b…. User hardware UI acceptance is retained; file inequality alone is not evidence of a regression.

## A mandatory Timing discrepancy

Windows root: `C:\Users\dai\Documents\MegaVGMDrive_A_vNext_Production_RC`.

The generated A RBF hash equals the selected Mac RBF. Saved .map/.fit/.flow/.asm/.sta reports were recovered read-only. The exact STA SHA256 is `6a96afa1d73d8847989a552d4525b717a8c9fa39ccdbdb0a12c83ce2bd1d11ea`.

| Check / clock | Saved Slow 1100mV 100°C slack ns | Endpoint TNS ns |
| --- | ---: | ---: |
| setup, emu PLL divclk | −88.815 | −3361.116 |
| setup, HDMI PLL divclk | −0.188 | −2.790 |
| hold minimum | +0.133 | 0 |
| recovery minimum | +4.424 | 0 |
| removal minimum | +0.600 | 0 |
| pulse width minimum | +1.122 | 0 |

Critical Warning 332148 explicitly says Timing requirements not met. Successful compilation/process exit is not Timing closure. Detailed setup path endpoints and violation counts are not included in this saved report; they remain unknown, not zero. No all4corner A signoff exists in this evidence set. Resource usage: 35,665 ALM, 4,147 LAB, 82 M10K. Hardware playback PASS and this Timing FAIL are separate facts.

A Windows input comparison: 197 of 198 checksum members exact, sole QSF mismatch. All RTL inputs match. Canonical QSF hash 10b6ebc7… versus Windows 9e5ed58e…; observed delta is CRLF and existing root_partition assignment moved to the end. Remaining nonempty line order and statement text match. The actor/cause is unknown. Neither file is changed by this audit; this byte mismatch prevents claiming an exact canonical configuration/rebuild reproduction.

## B / D measured results

B seed3 closure evidence records 31,787 ALM, 3,995 LAB, 84 M10K, worst setup +0.467 ns, all4corner setup/hold/recovery/removal/pulse PASS, TNS0. Two independent builds match resources/checks/RBF. Live Windows Run1 inputs and output hash also match. Only the optimized 70392ce7… RBF is the proposed adoption; older canonical B 9f62876a… remains protected.

D 26d5078 evidence records 22,074 ALM, 3,700 LAB, 79 M10K, worst constrained setup +0.495 ns and all4corner checks PASS/TNS0. Live Windows source and result hashes match. Independent second Full Compilation is not demonstrated. Existing 3 input/50 output unconstrained-port limitation is explicit; fully constrained external IO signoff is not claimed.

## Protection and scope

Seven existing repositories (including pre-existing dirty/untracked files), seven top-level RBF identities and twelve v2.3 payloads are checked against before-state. Five canonical documents and BUILD_TARGETS are snapshot-hashed and remain unchanged. No functional source or build setting is modified. No new Quartus invocation, RBF generation, deployment or release publication occurred. Future long-run/admission guarantees are not inferred from the user acceptance receipt.
