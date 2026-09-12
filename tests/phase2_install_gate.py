#!/usr/bin/env python3
"""Isolated Linux packaging tests. Never uses real /media/fat or services."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

package = Path(sys.argv[1]).resolve()
v2 = Path('/Users/daizo/Projects/MegaVGMPlayer_v2_Release_Final_Staging/MegaVGMPlayer-v2.0/media/fat')
root = Path(tempfile.mkdtemp(prefix='megavgm-v22-install-'))
startup = b'''#!/bin/sh

# mrext/remote
[[ -e /media/fat/Scripts/remote.sh ]] && /media/fat/Scripts/remote.sh -service $1

# Startup favorites
[[ -e /media/fat/Scripts/favorites.sh ]] && /media/fat/Scripts/favorites.sh refresh
'''
payload = sorted(p.relative_to(package/'media/fat') for p in (package/'media/fat').rglob('*') if p.is_file())
assert len(payload) == 9 and Path('Scripts/remote.sh') not in payload
def put(root, rel, data):
    p = root/rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_bytes(data)
    return p
def run(fat, script, *args, ok=True):
    p = subprocess.run(['sh',str(package/script),*map(str,args)], env={**os.environ,
      'MEGAVGM_FAT_ROOT':str(fat),'MEGAVGM_INSTALL_OFFLINE':'1'}, text=True,capture_output=True)
    assert (p.returncode == 0) == ok, (script,p.returncode,p.stdout,p.stderr)
    return p
def user_files(fat):
    return {r: put(fat,r,b'USER-'+r.encode()).read_bytes() for r in (
      'Scripts/remote.sh','Scripts/favorites.sh','Scripts/.config/megavgm/playlists.json',
      '_Utility/MegaVGMPlayer_Transport13FadeOnly_A_MiSTer.rbf',
      '_Utility/MegaVGMPlayer_Transport13FadeOnly_B_MiSTer.rbf',
      '_Custom Cores/Cores/MegaVGMPlayer_Transport13FadeOnly_A_MiSTer.rbf',
      '_Custom Cores/Cores/MegaVGMPlayer_Transport13FadeOnly_B_MiSTer.rbf',
      '_custom_core/user-rescue.rbf','MegaVGMDrive/music.vgm')}
def unchanged(fat, saved):
    for r,data in saved.items(): assert (fat/r).read_bytes() == data, r
def installed(fat):
    for rel in payload: assert (fat/rel).read_bytes() == (package/'media/fat'/rel).read_bytes(), rel
    s=(fat/'linux/user-startup.sh').read_bytes()
    assert s.count(b'# BEGIN MegaVGMPlayer v2.1') == 1
    assert s.endswith((package/'startup.block').read_bytes())

for mode in ('clean','v2upgrade','phase1'):
    fat=root/mode
    saved=user_files(fat)
    before={}
    if mode != 'clean':
        put(fat,'linux/user-startup.sh',startup)
        for rel in payload:
            if str(rel) in ('MegaVGMPlayer/megavgm_remote','Scripts/megavgm_ctl'): continue
            if mode=='v2upgrade' and not str(rel).endswith('.rbf'):
                data=(v2/rel).read_bytes()
            elif mode=='v2upgrade':
                continue
            else:
                data=b'OLD-V2-'+str(rel).encode()
            before[rel] = put(fat,rel,data).read_bytes()
    if mode=='v2upgrade':
        data=(v2/'Scripts/remote.sh').read_bytes()
        assert hashlib.sha256(data).hexdigest()=='720b982c194767ecaac308cec2d87265b66018b6aef6cecec8eacdb23fa94cfa'
        saved['Scripts/remote.sh']=put(fat,'Scripts/remote.sh',data).read_bytes()
    if mode == 'phase1':
        saved['MegaVGMPlayer/megavgm_remote.phase1'] = put(fat,'MegaVGMPlayer/megavgm_remote.phase1',b'RESCUE').read_bytes()
    run(fat,'install.sh' if mode=='clean' else 'upgrade.sh')
    installed(fat); unchanged(fat,saved)
    if mode != 'clean': assert (fat/'linux/user-startup.sh').read_bytes().startswith(startup)
    pointer=(fat/'MegaVGMPlayer/.v22-last-backup').read_text()
    run(fat,'install.sh')
    assert (fat/'MegaVGMPlayer/.v22-last-backup').read_text()==pointer
    installed(fat); unchanged(fat,saved)
    # Playlist edits after installation must survive rollback too.
    saved['Scripts/.config/megavgm/playlists.json']=b'UPDATED FAVORITES'
    put(fat,'Scripts/.config/megavgm/playlists.json',b'UPDATED FAVORITES')
    run(fat,'rollback.sh')
    for rel in payload:
        if rel in before: assert (fat/rel).read_bytes()==before[rel]
        else: assert not (fat/rel).exists()
    if mode=='clean': assert not (fat/'linux/user-startup.sh').exists()
    else: assert (fat/'linux/user-startup.sh').read_bytes()==startup
    unchanged(fat,saved)
    print(mode, 'install + duplicate + rollback + persistence PASS')

# Reject unknown/duplicated startup and symlink destinations without touching payload.
for name, data in [('unknown', startup+b' /tmp/megavgm_remote -service start\n'),
                   ('duplicate',startup+(package/'startup.block').read_bytes()*2)]:
    fat=root/name; put(fat,'linux/user-startup.sh',data)
    run(fat,'install.sh',ok=False)
    assert (fat/'linux/user-startup.sh').read_bytes()==data
    assert not (fat/'Scripts/megavgm_ctl').exists()
fat=root/'symlink'; fat.mkdir(); outside=root/'outside'; outside.mkdir()
(fat/'Scripts').symlink_to(outside, target_is_directory=True)
run(fat,'install.sh',ok=False)
assert not list(outside.iterdir())

# Rollback cannot clobber later startup/user edits.
fat=root/'edited'; put(fat,'linux/user-startup.sh',startup)
run(fat,'install.sh')
p=fat/'linux/user-startup.sh'; p.write_bytes(p.read_bytes()+b'# user later edit\n')
run(fat,'rollback.sh',ok=False)
assert p.read_bytes().endswith(b'# user later edit\n')
installed_payload=(fat/'Scripts/megavgm_ctl').read_bytes()
assert installed_payload==(package/'media/fat/Scripts/megavgm_ctl').read_bytes()
print('unknown/duplicate startup, symlink, later-edit refusal PASS')

# Simulate interruption between individual atomic renames: mixed before/after
# bytes must be recoverable using a PREPARED backup without COMPLETE.
fat=root/'interrupted'; put(fat,'linux/user-startup.sh',startup)
old=put(fat,'Scripts/megavgm_ctl',b'OLD HELPER').read_bytes()
run(fat,'install.sh')
backup=Path((fat/'MegaVGMPlayer/.v22-last-backup').read_text().strip())
(backup/'COMPLETE').unlink()
put(fat,'Scripts/megavgm_ctl',old)
put(fat,'linux/user-startup.sh',startup)
run(fat,'rollback.sh',backup)
assert (fat/'Scripts/megavgm_ctl').read_bytes()==old
assert (fat/'linux/user-startup.sh').read_bytes()==startup
assert not (fat/'MegaVGMPlayer/megavgm_remote').exists()
print('interrupted multi-file transaction recovery PASS')

# Corrupted payload fails checksum before changing existing files.
bad=root/'bad-package'; shutil.copytree(package,bad)
with (bad/'media/fat/Scripts/megavgm_ctl').open('ab') as f: f.write(b'bad')
original=package; package=bad
fat=root/'corrupt'; saved=user_files(fat)
run(fat,'install.sh',ok=False); unchanged(fat,saved)
assert not (fat/'MegaVGMPlayer/megavgm_remote').exists()
package=original

# Execute only the added block with a fixture daemon; test argument forwarding.
block=(package/'startup.block').read_text()
fake=root/'daemon'; calls=root/'calls'
fake.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "'+str(calls)+'"\n'); fake.chmod(0o755)
stub=root/'startup-test.sh'
stub.write_text(block.replace('/media/fat/MegaVGMPlayer/megavgm_remote',str(fake)))
for args in ([],['start'],['stop'],['restart'],['unknown']):
    subprocess.run(['sh',str(stub),*args],check=True)
assert calls.read_text().splitlines()==['-service start','-service start','-service stop','-service restart']
print('startup boot(default)/start/stop/restart forwarding PASS; no ENTER')
print('ALL INSTALL GATES PASS',root)
