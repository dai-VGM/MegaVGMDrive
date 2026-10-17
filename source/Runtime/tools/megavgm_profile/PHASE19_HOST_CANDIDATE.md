# Phase 1.9 isolated Runtime candidate

Base81bc14d19e7ef530322728d51bc785c9cad6e395 (existing NSFe preparation route). Production HOLD; device deployment NOT_AUTHORIZED.

Controller user Stop issues generic MV02/02 FADE_ONLY on index2 using a separate immutable Stop payload. Public STOPPED is published only after same-owned-session ENDED, with source/context retained. Reset-to0/old-session DONE/FATAL do not count as Stop completion. Reload uses the retained ended-session baseline. LOADING Stop waits for accepted ownership and Main generation acknowledgment before control transfer; it never fabricates PLAYING. Pre-admission container preparation cancellation remains in existing park/Supervisor responsibilities. Cross-engine transaction still uses generic SwitchOwner and its own fade/replace boundary. User Stop superseding fade waits same-session ENDED, preserving generation/domain checks.

Profile F appends wire8 (A-E/error values unchanged), accepts explicit single3579545Hz HuC6280 VGM1.61 metadata and B9 register0..9 facts, rejects other-profile mixtures/dual/missing clock/truncation. Existing classifier/status/RBF/schema vocabulary is extended; no engine-specific switch algorithm. Request/reply serialization accepts wire8. E NSF/NSFe→NSF1 preparation is reused.

Host tests: Stop/Reload and20cycles, LOADING Stop/no fakePLAYING, ownedENDED, oldDONE/reset0 rejection, StopFATAL, immutable payload mismatch rejection, A-F same/cross switch, generation/late status/latest intent, NSF/VGM/SID/native preparation/cancel/cache. Local native binaries are test results, not ARM deployable packages.

Rollback plan: production Host unchanged. Before any separate device deployment approval, freeze compatible Runtime/Remote/preparer/PWA ARM identities, preserve installed hashes and runtime config; stop existing Controller via its normal owner, install only separately approved exact package, verify served and executing PWA identities. On failure use saved exact normal Runtime/Remote/Main/RBF and restore original configuration; recheck hashes. No runtime/RBF path overwrite or deployment is authorized by this source commit.
