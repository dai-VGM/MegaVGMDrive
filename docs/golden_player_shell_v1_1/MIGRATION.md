# Golden Player Shell v1.1 migration policy

No existing profile moves automatically. v1.0 projects remain pinned to the
hardware-PASS v1.0 shim. Migration is stage-gated:

1. Build and hardware-validate v1.1 Stage A.
2. Build and hardware-validate v1.1 Audio Contract Lab.
3. In a later task, migrate Stage B as scan-only with audio zero and obtain a
   separate MiSTer PASS.
4. Only then migrate Stage C and validate Olga FM on MiSTer.

Stage B/C migration, JT10, Olga, PCM clients, production release, manifest
promotion, and a public tag are outside this candidate commit.
