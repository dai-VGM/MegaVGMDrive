#!/usr/bin/env python3
"""Read-only equality audit against frozen source worktrees."""
from pathlib import Path
import hashlib
import re
import subprocess
root=Path(__file__).resolve().parents[1]
projects=root.parent
backend=projects/'mrext-track-chip-status/cmd/remote/megavgm'
frontend=projects/'mrext-client-final-header-logo/src/components'
c5_backend_changes = {
    'browse_play_test.go', 'favorites.go', 'favorites_test.go', 'megavgm.go',
    'sound_chips.go', 'sound_chips_test.go', 'track_files.go',
    'transport_status.go', 'transport_status_test.go',
}
c5_frontend_changes = {
    'MegaVGMPlayer.tsx', 'megavgmFavorites.ts', 'megavgmPresentation.ts',
    'megavgmTransportDisplay.test.ts',
}
for directory, commit in [(backend.parents[2], '6ef56324b91df854080f65f5c4c0f0535740b4ca'), (frontend.parents[1], '8dc1988b106276e215de5e3164a2307e90aa9017')]:
    assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=directory,text=True).strip()==commit
for p in sorted(backend.glob('*.go')):
    if p.name in c5_backend_changes:
        continue
    expected=p.read_text()
    if p.name=='megavgm_test.go':
        expected=expected.replace('\treturn newAdapter(config, runner)\n', '\tadapter := newAdapter(config, runner)\n\tt.Cleanup(func() { retireFixture(adapter) })\n\treturn adapter\n')
    assert (root/'internal/megavgm'/p.name).read_text()==expected,p
for p in sorted((root/'frontend/src/components').glob('*')):
    if p.name == 'MegaVGMStandaloneStyles.tsx' or p.name in c5_frontend_changes:
        continue  # Dedicated shell or reviewed C5 prepared-SID integration.
    assert p.read_bytes()==(frontend/p.name).read_bytes(),p
allowed = {
    'frontend/src/components/' + name for name in c5_frontend_changes
} | {
    'frontend/src/lib/models.ts', 'tests/service_gate.py'
} | {
    'internal/megavgm/' + name for name in c5_backend_changes
}
changed = set(subprocess.check_output(
    ['git', 'diff', '--name-only', '3dbce89..8af356a'], cwd=root, text=True
).splitlines())
assert changed == allowed, (sorted(changed - allowed), sorted(allowed - changed))
print('Frozen backend/Player files match; C5 source delta is the exact reviewed allowlist')
old=(backend.parent/'main.go').read_text()
new=(root/'cmd/megavgm_remote/http.go').read_text()
routes=lambda s: sorted(re.findall(r'HandleFunc\("(/megavgm[^\"]*)", \w+\.(\w+)\)\.Methods\("(\w+)"\)',s))
assert len(routes(old))==21 and routes(old)==routes(new)
print('21 path/method/handler mappings: exact match')
oldapi=(frontend.parent/'lib/api.ts').read_text()
newapi=(root/'frontend/src/lib/api.ts').read_text()
methods=oldapi[oldapi.index('  async megaVGMStatus'):oldapi.index('  // games')]
assert methods in newapi
assert 'window.location.origin + "/api"' in newapi
print('MegaVGM API method bodies unchanged; same-origin base URL')
helper=projects/'MegaVGMPlayer_Remote3/megavgm_ctl-transport-m5'
assert helper.stat().st_size==961808
assert hashlib.sha256(helper.read_bytes()).hexdigest()=='378905c80c22f0b072e248d6fdb67238f2727a38287f4407b2596c8c2a9ae45b'
print('Production helper size/SHA exact match')
