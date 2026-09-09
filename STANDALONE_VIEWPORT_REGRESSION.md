# Phase 1 standalone viewport contract correction

## Evidence and root cause

Hardware reference: user-supplied IMG_4763.png, iPhone 15 Pro 1179×2556
(393×852 CSS px at DPR 3). The image shows navigation beginning normally near
773–774 CSS px, then clipping around 793 px; approximately 59 px of dark canvas
remains below. This is not evidence that 34 px safe-bottom was added outside nav.
Pixels establish the clipping pattern, not the iPhone's computed DOM dimensions.

Source comparison against v2.0 PASS frontend
`8dc1988b106276e215de5e3164a2307e90aa9017` proves a shell extraction omission:

| Contract | v2.0 PASS | Initial Phase 1 |
|---|---|---|
| html/body/#root | height/min/max=100lvh, fallback 100vh | height=100%, min=0, max=none |
| App shell | height/max=100%, min=0 | independent height=100lvh, no max |
| Standalone styles | Mounted in Remote Layout | Not imported; partial inline adaptation only |
| Nav safe-bottom | Internal padding once | Identical Player component, internal padding once |
| Viewport meta | viewport-fit=cover | Same |
| Header top inset | Once, header toolbar | Once, in-flow header |

An independent lvh child can therefore extend below a shorter percentage-height
ancestor. The ancestor's overflow:hidden clips navigation even though the child's
own measured bottom is correct. Initial Phase 1 browser tests checked shell/nav
rectangles but not the full ancestor min/max contract, so they missed this case.

Controlled host reproduction: old exact embedded Phase 1 bundle, 393×852,
safe-top 59/safe-bottom 34, test-only preferred html height=793. It gives:
html/body/root=793, shell=852, nav=773..852, tab content=774..818, cutoff=793.
Only the first 19 px of tab content remain visible, matching the supplied image's
pattern. This is a controlled clipping-path reproduction, not a claim that Chrome
emulates iOS's viewport calculation or that iPhone DOM values were remotely read.

## Minimal correction

`frontend/src/components/MegaVGMStandaloneStyles.tsx` now mounts from the dedicated
entry and restores the v2.0 root height/min/max and shell percentage constraints.
Selectors target `data-standalone-shell`, not the absent Remote Layout selector.
The explicit non-shrinking footer rule is adapted from the production stylesheet.

Do not transplant v2.0's `main height:100%` and fixed-header spacer: the dedicated
header already occupies flex flow. Main remains flex:1/min-height:0, consuming the
remaining space exactly once. No extra wrapper, padding, fixed/sticky, gesture lock
or production JavaScript viewport correction was introduced. Normal browser-mode
CSS is unchanged; new rules are entirely inside display-mode:standalone.

## Corrected host geometry (393×852)

| Box | Top | Bottom | Height |
|---|---:|---:|---:|
| html/body/#root/app shell | 0 | 852 | 852 |
| Header (59 safe + 44 content) | 0 | 103 | 103 |
| Scroll content | 103 | 624.39 | 521.39 |
| Mini player | 624.39 | 773 | 148.61 |
| Navigation | 773 | 852 | 79 |
| Tab content (after 1px border) | 774 | 818 | 44 |
| Internal bottom safe area | 818 | 852 | 34 |

These satisfy the v2.0 viewport/inset contract, with the same unchanged Player
geometry for the same fixture data. Both normal and reduced-root stress conditions
pass after the change. Before it, the new test fails against the old bundle.

## Verification

- Production TypeScript/Vite build PASS: `assets/megavgm-36f68731.js`.
- 320/393 standalone: labels fully contained, full root chain, nav bottom=852,
  safe-bottom=34 inside nav; scroll/tab restoration and stationary footer PASS.
- Reduced-root controlled A/B: old bundle fails; corrected bundle PASS.
- Original state/render/API regression tests PASS, including cold/late operations
  and 100-transition cases; Player/controls and five backend files byte-identical.
- Existing ARM/helper SHA checks unchanged. No ARM generation or embed-root copy.
- Corrected iPhone hardware validation is PENDING.

Screenshots and measurements:

- [393 Browse](evidence/viewport-contract/standalone-393-browse.png)
- [393 Playlists](evidence/viewport-contract/standalone-393-playlists.png)
- [Corrected geometry](evidence/viewport-contract/browser.json)
- [Old controlled clipping](evidence/reduced-root-before/initial-393.png)
- [Old controlled box values](evidence/reduced-root-before/initial-393.json)
- [Corrected controlled box values](evidence/reduced-root-after/initial-393.json)

Changed files: dedicated entry, new standalone stylesheet component, browser
regression, provenance exception for the new shell adapter, and this audit.
No Player component, controls, service/backend, Phase2A, Main or RBF changes.
