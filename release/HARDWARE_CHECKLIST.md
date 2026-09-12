# v2.2 Stage 1 exact hardware acceptance — NOT YET RUN

1. Return to STOCK and record current Supervisor/controller/RBF hashes.
2. Run `upgrade.sh`; preserve its printed `backups-v2.2-*` path.
3. Confirm all old v2.1 RBFs under `_Custom Cores/Cores` and `_Utility` still
   exist with their pre-upgrade hashes.
4. Confirm the new files and exact hashes:
   - `MegaVGMDrive_A.rbf`: `5755b74d9b1e10e1da1d6c101892bc95ca8960851a851cc9076d1861c9571f1e`
   - `MegaVGMDrive_B.rbf`: `b435417f268a81a39af6bf2408f364945d151e391425775ab7d01ed4899bec95`
   - `MegaVGMDrive_C.rbf`: `117adcd8d9360388826f60f4207c5b547daee58f5f0ba2e456f10e7bf41abed8`
5. Reboot with no test-profile; verify STOCK and standalone Remote on 8183.
6. Play A→B→A and inspect `active_rbf_argv`: it must use only exact
   `/media/fat/_Custom Cores/Cores/MegaVGMDrive_A.rbf` or `_B.rbf` paths.
7. Play same-profile tracks and verify no RBF reload.
8. Complete a playlist and verify automatic STOCK restoration.
9. Confirm Stage 1 never automatically selects `MegaVGMDrive_C.rbf`.
10. Return to STOCK, run rollback, reboot, and verify the restored v2.1
    Supervisor uses its old exact RBF paths. Confirm all legacy RBF bytes survived.

If any item fails, capture runtime hashes and Supervisor/controller logs, return
to STOCK, and use the preserved backup. Do not delete either old or new RBFs.
