# Publication preparation — not executed

Version/tag proposal: `v2.4.0`. Title: **MegaVGMPlayer v2.4.0 — Architecture Refresh**. Notes source: RELEASE_NOTES.md (English with short Japanese clarification).

Live read-only GitHub audit confirmed v2.3 is already public and carries MegaVGMPlayer-v2.3.zip plus its checksum companion. v2.4 proposes the same asset convention: MegaVGMPlayer-v2.4.0.zip and MegaVGMPlayer-v2.4.0.zip.sha256. v2.3 stays untouched.

After DAI's separate final approval only:

1. Recheck GitHub repository/main/tag/release state; do not overwrite an existing v2.4.0 tag/Release/asset. Identify and approve the exact public source commit/branch; this isolated integration repository has not been pushed.
2. Re-run tools/verify_v240.py and tools/verify_artifact_identity.py against the final package; confirm all RBF, member, ZIP and source/config hashes. Review known limits, C legacy provenance and hardware test scopes explicitly.
3. Record the final integration/source commit and package checksum. Complete any additionally requested package/device acceptance. Do not treat RC_READY as deployment or full production admission.
4. Only with explicit tag/push/Release authorization, publish the approved source commit/tag and create the Release with the English notes and the two verified assets. Draft creation is also an external write and has not been performed here.
5. Verify server asset digest/size, tag target, notes and publication state. Preserve v2.3 and rollback artifacts. Deployment remains a separate authorized action.

No tag, push, draft Release, public Release or production deployment occurs in this task.
