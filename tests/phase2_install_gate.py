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
def run(fat, script, *args, ok=True, extra_env=None):
    env={**os.environ, 'MEGAVGM_FAT_ROOT':str(fat), 'MEGAVGM_INSTALL_OFFLINE':'1'}
    if extra_env: env.update(extra_env)
    p = subprocess.run(['sh',str(package/script),*map(str,args)], env=env,
      text=True,capture_output=True)
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

def preflight_fixture(name, supervisor_state='unavailable', main='stock',
                      controller=False, multiple=False, active_session=False,
                      wrong_sha=False):
    fat=root/('preflight-'+name); proc=root/('proc-'+name); runtime=root/('runtime-'+name)
    fat.mkdir(parents=True); proc.mkdir(); runtime.mkdir()
    stock=put(fat,'MiSTer',b'STOCK MAIN KNOWN FIXTURE')
    modified=put(fat,'MegaVGMPlayer/MiSTer.megavgm',b'MODIFIED MAIN FIXTURE')
    supervisor=put(fat,'MegaVGMPlayer/megavgm_supervisor',b'')
    if supervisor_state == 'unavailable':
        supervisor.write_text("""#!/bin/sh
if [ "$1" = exit ]; then
  echo 'EXIT_FAILED: supervisor control unavailable: No such file or directory' >&2
else
  echo 'STATUS_UNAVAILABLE: No such file or directory' >&2
fi
exit 1
""")
    elif supervisor_state == 'stock':
        supervisor.write_text("#!/bin/sh\nprintf 'mode=STOCK\\nmain=STOCK\\ncontroller=STOPPED\\n'\n")
    else:
        supervisor.write_text("#!/bin/sh\nprintf 'mode=PLAYING\\nmain=MODIFIED\\ncontroller=RUNNING\\n'\n")
    supervisor.chmod(0o755)
    expected=hashlib.sha256(stock.read_bytes()).hexdigest()
    if wrong_sha: stock.write_bytes(b'WRONG STOCK MAIN')
    def process(pid, comm, exe):
        d=proc/str(pid); d.mkdir(); (d/'comm').write_text(comm+'\n'); (d/'exe').symlink_to(exe)
    if supervisor_state != 'stock' and supervisor_state != 'active':
        process(100,'MiSTer',modified if main=='modified' else stock)
        if multiple: process(101,'MiSTer',stock)
        if controller:
            ctl=put(fat,'MegaVGMPlayer/megavgm_playlist-phase2a',b'CONTROLLER')
            process(200,'megavgm_playlis',ctl)
    if active_session: (runtime/'MegaVGMPlayer.status').write_text('state=PLAYING\n')
    env={'MEGAVGM_PREFLIGHT_TEST':'1','MEGAVGM_PROC_ROOT':str(proc),
         'MEGAVGM_RUNTIME_ROOT':str(runtime),'MEGAVGM_TEST_STOCK_SHA256':expected}
    return fat,env

# A reboot normally leaves no Supervisor status/control plane. The strict
# fallback must prove stock Main identity directly; every ambiguity is fatal.
fat,env=preflight_fixture('reboot-stock')
supervisor=fat/'MegaVGMPlayer/megavgm_supervisor'
exit_result=subprocess.run([str(supervisor),'exit'],text=True,capture_output=True)
assert exit_result.returncode != 0 and exit_result.stderr.startswith('EXIT_FAILED:')
status_result=subprocess.run([str(supervisor),'status'],text=True,capture_output=True)
assert status_result.returncode != 0 and status_result.stderr.startswith('STATUS_UNAVAILABLE:')
p=run(fat,'upgrade.sh',extra_env=env)
assert 'Verified STOCK without persisted Supervisor status' in p.stdout
installed(fat)
for name, options, evidence in (
    ('modified-main', {'main':'modified'}, 'Modified Main process is active'),
    ('wrong-main-sha', {'wrong_sha':True}, 'Active Main SHA mismatch'),
    ('controller-running', {'controller':True}, 'controller/Supervisor process is active'),
    ('multiple-main', {'multiple':True}, 'Expected exactly one SHA-verified stock MiSTer process'),
    ('active-session', {'active_session':True}, 'Active/ambiguous MegaVGM runtime state exists'),
):
    fat,env=preflight_fixture(name,**options)
    rejected=run(fat,'upgrade.sh',ok=False,extra_env=env)
    assert evidence in rejected.stderr,(name,rejected.stderr)
    assert not (fat/'_Custom Cores/Cores/MegaVGMDrive_A.rbf').exists(),name
fat,env=preflight_fixture('persisted-stock',supervisor_state='stock')
run(fat,'upgrade.sh',extra_env=env); installed(fat)
fat,env=preflight_fixture('megavgm-active',supervisor_state='active')
run(fat,'upgrade.sh',ok=False,extra_env=env)
assert not (fat/'_Custom Cores/Cores/MegaVGMDrive_A.rbf').exists()
print('reboot-like strict STOCK fallback and persisted-status regressions PASS')

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
