#!/usr/bin/env python3
"""Run only in an isolated Linux VM. No MiSTer paths are written.

Exercises the supplied executable itself, including start/stop/exec children.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import tempfile
import time
import threading
import urllib.request
import urllib.error

binary = str(Path(sys.argv[1]).resolve())
foreground = '--foreground' in sys.argv[2:]
child = None
root = Path(tempfile.mkdtemp(prefix='megavgm-phase1-gate-'))
runtime = root / 'runtime'
runtime.mkdir()
fixture = root / 'fixture'
fixture.mkdir()
(fixture / 'library').mkdir()
track = fixture / 'library' / '01 Coin.vgm'
track.write_bytes(b'Vgm ' + b'\0'*64)
sid_track = fixture / 'library' / '02 Commando.mvgmsid'
sid_track.write_bytes(b'MVGMSID\0' + b'\0'*120)
playlist = {'version': 1, 'playlists': {'Favorites': [str(track)], 'Existing': [str(track)]}}
(fixture / 'playlists.json').write_text(json.dumps(playlist))
os.mkfifo(fixture / 'playlist.cmd')
supervisor = 'mode=MEGAVGM\nmain=MODIFIED\ncontroller=RUNNING\ndetail=isolated fixture\nrbf=test.rbf\nplaylist='+str(track.parent)+'\n'
transport = 'switch_epoch=megavgm-phase2a.fixture\nswitch_generation={generation}\nswitch_state={state}\ncurrent_profile={profile}\nrequired_profile={required}\nswitch_domain=1\nswitch_baseline=0\nswitch_changed=1\nswitch_path='+str(track)+'\n'
def status(profile='PROFILE_A', generation=1, state='PLAYING', session=57, chip='YM2612', sid=False):
    (fixture / 'supervisor.status').write_text(supervisor + transport.format(generation=generation,state=state,profile=profile,required=profile))
    selected = sid_track if sid else track
    sid_metadata = ('sid_format_version=2\nsid_model=6581\nsid_timing=PAL\n'
                    'sid_subtune=1\nsid_capture_limited=1\n'
                    'sid_source_sha256=' + 'ab'*32 + '\n') if sid else ''
    (fixture / 'playlist.status').write_text(f'state=PLAYING\nindex=1\ncount=1\npath={selected}\nsession={session}\nloop_count=0\ncontext=PLAYLIST\nplaylist=Favorites\nrepeat=OFF\nshuffle=0\ntraversal=ORDERED\nsound_chips={chip}\n{sid_metadata}')
status()
# Commands go only to fixture scripts, never real hardware helpers.
for helper in ('ctl', 'supervisor'):
    p=fixture/helper
    p.write_text('#!/bin/sh\nprintf "%s\\n" "$*" >> "'+str(fixture/'commands')+'"\nif test -f "'+str(fixture/'hold')+'"; then sleep 0.25; fi\n')
    p.chmod(0o755)

base = [binary, '-runtime-dir', str(runtime), '-test-root', str(fixture)]
def svc(action, expected=0):
    global child
    # QEMU user-mode rewrites /proc/self but not /proc/<other-pid> identically.
    # Verify service identity on native Linux; use exact ARM foreground for HTTP.
    if foreground:
        if action == 'restart':
            svc('stop'); return svc('start')
        if action == 'stop':
            if child is not None and child.poll() is None:
                child.terminate(); child.wait(timeout=60)
            return subprocess.CompletedProcess([], 0)
        if action == 'status':
            running = child is not None and child.poll() is None
            assert running == (expected == 0)
            return subprocess.CompletedProcess([], 0 if running else 1)
        p = subprocess.Popen(base+['-service','exec'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        if expected != 0:
            out,err=p.communicate(timeout=15)
            assert p.returncode != 0
            return subprocess.CompletedProcess([],p.returncode,out,err)
        child=p
        for _ in range(200):
            assert p.poll() is None, p.communicate()
            if (runtime/'megavgm_remote.pid').exists(): return subprocess.CompletedProcess([],0)
            time.sleep(.05)
        raise AssertionError('foreground readiness timeout')
    p=subprocess.run(base+['-service',action],text=True,capture_output=True,timeout=60)
    assert (p.returncode==0)==(expected==0), (action,p.returncode,p.stdout,p.stderr)
    return p
def get(path):
    with urllib.request.urlopen('http://127.0.0.1:8183'+path,timeout=5) as r:
        assert r.status==200
        return r.read()
def api(path, method='GET', data=None):
    req=urllib.request.Request('http://127.0.0.1:8183/api/megavgm'+path,method=method,
       data=None if data is None else json.dumps(data).encode(),headers={'Content-Type':'application/json'})
    try:
        with urllib.request.urlopen(req,timeout=5) as r: return r.status,json.load(r)
    except urllib.error.HTTPError as e: return e.code,json.load(e)
def no_commands():
    return (fixture/'commands').read_text() if (fixture/'commands').exists() else ''

try:
    # Occupied port must fail with an explicit error, without fallback or PID publication.
    conflict=socket.socket(); conflict.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
    conflict.bind(('0.0.0.0',8183)); conflict.listen()
    result=svc('start',1)
    assert 'cannot bind' in result.stderr, result.stderr
    assert not (runtime/'megavgm_remote.pid').exists()
    conflict.close()
    svc('start'); svc('status'); svc('start',1)
    # Exact binary static serving, all linked asset paths, and PWA metadata.
    html=get('/megavgm').decode()
    assert get('/megavgm/')==html.encode()
    paths=re.findall(r'(?:src|href)="([^"]+)"',html)
    for p in paths: get(p)
    manifest=json.loads(get('/megavgm-manifest.json'))
    for icon in manifest['icons']: get(icon['src'])
    js=next(p for p in paths if p.endswith('.js'))
    print('EMBEDDED_JS',js,'SHA256',hashlib.sha256(get(js)).hexdigest())
    for p in ('/api/ws','/api/sysinfo','/api/settings/remote/peers','/api/music/status'):
        try: get(p); raise AssertionError('Remote endpoint reachable: '+p)
        except urllib.error.HTTPError as e: assert e.code==404
    code,s=api('/status'); assert code==200 and s['state']=='PLAYING',s
    assert s['soundChips']==['YM2612'] and s['transport']['currentProfile']=='PROFILE_A',s
    assert api('/favorites')[1]['entries'][0]['path']==str(track)
    assert api('/playlists/Existing')[0]==200
    assert api('/browse', 'GET')[0]==200
    assert api('/playlists','POST',{'name':'New'})[0] in (200,201)
    assert api('/playlists/New','PATCH',{'name':'Renamed'})[0]==200
    assert api('/playlists/Renamed/tracks','POST',{'path':str(track)})[0]==200
    assert api('/playlists/Renamed/tracks','DELETE',{'path':str(track)})[0]==200
    assert api('/playlists/Renamed','DELETE')[0]==200
    for p,data in [('/next',{}),('/prev',{}),('/stop',{}),('/repeat',{'mode':'one'}),('/repeat',{'mode':'all'}),('/shuffle',{'enabled':True}),('/play',{'path':str(track)})]:
        assert api(p,'POST',data)[0]==202,(p,api(p,'POST',data))
    assert api('/repeat','POST',{'mode':'invalid'})[0]==400
    baseline=no_commands()
    # HTTP disconnect/restart must not dispatch a Stop or Exit.
    sock=socket.create_connection(('127.0.0.1',8183)); sock.sendall(b'GET /api/megavgm/status HTTP/1.1\r\nHost: localhost\r\n\r\n'); sock.close()
    svc('restart')
    assert api('/status')[1]['session']==57
    assert no_commands()==baseline
    # A service restart drains an already-dispatched command, without killing it.
    (fixture/'hold').touch()
    completed=[]
    request_thread=threading.Thread(target=lambda: completed.append(api('/next','POST',{})))
    request_thread.start()
    for _ in range(100):
        if no_commands()!=baseline: break
        time.sleep(.01)
    assert no_commands()!=baseline
    svc('restart'); request_thread.join(timeout=5)
    assert completed and completed[0][0]==202,completed
    (fixture/'hold').unlink()
    baseline=no_commands()
    # Authoritative A->B->A and reset sessions are forwarded, not globally compared.
    for profile,gen,session,chip in [('PROFILE_B',2,1,'YM2610B'),('PROFILE_B',2,2,'YM2610'),('PROFILE_A',3,1,'YM2151,SegaPCM')]:
        status(profile,gen,session=session,chip=chip)
        code,s=api('/status'); assert code==200,(code,s)
        assert s['session']==session and s['transport']['currentProfile']==profile,s
    status('PROFILE_C',4,session=1,chip='SID 6581',sid=True)
    code,s=api('/status'); assert code==200 and s['transport']['currentProfile']=='PROFILE_C',s
    assert s['title']=='02 Commando' and s['soundChips']==['SID 6581'],s
    assert s['sid']=={'formatVersion':2,'model':'6581','timing':'PAL','subtune':1,
                     'captureLimited':True,'sourceSha256':'ab'*32},s
    (fixture/'supervisor.status').write_text('mode=STOCK\nmain=STOCK\ncontroller=STOPPED\nrbf=\nplaylist=\ndetail=fixture complete\n')
    assert api('/status')[1]['mode']=='STOCK'
    assert no_commands()==baseline
    svc('stop'); svc('status',1)
    if foreground:
        print('EXACT_ARM_HTTP_API_GATE PASS (QEMU; service identity tested natively)',root)
        sys.exit(0)
    # Repeated and concurrent starts; exactly one contender succeeds.
    a=subprocess.Popen(base+['-service','start'],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    b=subprocess.Popen(base+['-service','start'],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    a.communicate(timeout=20); b.communicate(timeout=20)
    assert sorted([a.returncode,b.returncode])==[0,1],(a.returncode,b.returncode)
    svc('stop')
    # Crash leaves stale files, but a manual restart can safely take the free lock.
    svc('start')
    crashed_pid=int((runtime/'megavgm_remote.pid').read_text())
    os.kill(crashed_pid,9)
    time.sleep(.1)
    svc('restart'); svc('stop')
    # A forged/stale PID never signals an unrelated process.
    sleeper=subprocess.Popen(['sleep','30'])
    (runtime/'megavgm_remote.pid').write_text(str(sleeper.pid))
    (runtime/'megavgm_remote.identity').write_text(json.dumps({'pid':sleeper.pid,'start':'0','sha256':'wrong'}))
    svc('stop',1); assert sleeper.poll() is None
    sleeper.terminate(); sleeper.wait()
    svc('start'); svc('stop')
    print('SERVICE_AND_EXACT_HTTP_GATE PASS (Linux host/QEMU only)',root)
finally:
    if foreground:
        svc('stop')
    else:
        subprocess.run(base+['-service','stop'],capture_output=True,timeout=60)
