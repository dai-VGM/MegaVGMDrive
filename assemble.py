from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED
from hashlib import sha256
from io import BytesIO
from subprocess import check_output
import json, stat, sys, tarfile

root = Path(__file__).resolve().parent
p = json.loads((root/'inputs.json').read_bytes())
base, exit_elf, sid_elf, host_tree, sid_tree, setup_tree, output = map(Path, sys.argv[1:])
base_zip = base/'MegaVGMPlayer-v2.6-Full-Install-RC8.zip'
base_src = base/'MegaVGMPlayer-v2.6-RC8-Corresponding-Source-Inputs.zip'
output.mkdir(exist_ok=True)
out_zip = output/'MegaVGMPlayer-v2.6-Full-Install-RC9.zip'
out_src = output/'MegaVGMPlayer-v2.6-RC9-Corresponding-Source.zip'

def sha(data):
    return sha256(data).hexdigest()

def j(data):
    return (json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True)+'\n').encode()

def git(repo, *args):
    return check_output(['git','-C',str(repo),*args])

def tree(repo, commit, *paths):
    tar = git(repo,'archive','--format=tar',commit,*paths)
    with tarfile.open(fileobj=BytesIO(tar)) as archive:
        for member in archive:
            if member.isfile():
                data = archive.extractfile(member).read()
                assert not data.startswith((b'\x7fELF',b'!<arch>\n')), member.name
                yield member.name, data, member.mode

def fresh_entry(name, mode=0o644):
    entry = ZipInfo(name,(2026,11,10,0,0,0))
    entry.create_system = 3
    entry.external_attr = (stat.S_IFREG|mode)<<16
    entry.compress_type = ZIP_DEFLATED
    return entry

def zipread(z):
    assert len(z.namelist())==len(set(z.namelist()))
    assert z.testzip() is None
    return {entry.filename: sha(z.read(entry)) for entry in z.infolist()}

assert not out_zip.exists() and not out_src.exists()
assert sha(base_zip.read_bytes())==p['base_zip_sha256']
assert sha(base_src.read_bytes())==p['base_source_zip_sha256']
assert git(host_tree,'rev-parse',p['host']+'^').decode().strip()==p['base_host']
assert git(sid_tree,'rev-parse',p['sid']+'^').decode().strip()==p['base_sid']
git(setup_tree,'merge-base','--is-ancestor',p['remote'],p['setup'])
assert sha(exit_elf.read_bytes())==p['supervisor_sha256']
assert sha(sid_elf.read_bytes())==p['sid_sha256']
commit=git(root,'rev-parse','HEAD').decode().strip()
identity=dict(p,integration_commit=commit)
payload='MegaVGMPlayerFull_Install/payload/'
manifest='MegaVGMPlayerFull_Install/manifest.json'
sums='SHA256SUMS.txt'
with ZipFile(base_zip) as z:
    before=zipread(z)
    assert dict((name,h) for h,name in (line.split('  ',1) for line in z.read(sums).decode().splitlines()))=={n:h for n,h in before.items() if n!=sums}
    m=json.loads(z.read(manifest))
    orig=json.loads(z.read('SOURCE-IDENTITY.json'))
    assert orig['source']['host']==p['base_host'] and orig['source']['setup']==p['setup']
    assert orig['source']['remote']==p['remote'] and orig['distribution_port']==p['port']
    assert m['files']=={n.removeprefix(payload):h for n,h in before.items() if n.startswith(payload)}
    assert m['main_sha256'].encode() in exit_elf.read_bytes()
    assert p['sid'].encode() in sid_elf.read_bytes()
    replacements={payload+'megavgm_supervisor':exit_elf.read_bytes(),payload+'megavgm_sid_prepare':sid_elf.read_bytes()}
    m['version']='v2.6-full-rc9'
    m['files'].update({n.removeprefix(payload):sha(data) for n,data in replacements.items()})
    orig['candidate']='v2.6 Full RC9'
    orig['source'].update(host=p['host'],sid=p['sid'])
    orig['rc9_integration']=identity
    orig.update(hardware_clean_SD='NOT_RUN_RC9',SS1='NOT_RUN_RC9',release_adoption='HOLD_UNPUBLISHED')
    guide=z.read('Full-README.ja.md').decode().replace('v2.6 Full RC8','v2.6 Full RC9').replace('RC8の物理実機検証','RC9の物理実機検証')
    replacements.update({manifest:j(m),'SOURCE-IDENTITY.json':j(orig),'Full-README.ja.md':guide.encode()})
    expected={**before,**{n:sha(b) for n,b in replacements.items()}}
    checksums=''.join(f'{h}  {n}\n' for n,h in sorted(expected.items()) if n!=sums).encode()
    expected[sums]=sha(checksums)
    replacements[sums]=checksums
    with ZipFile(out_zip,'x',ZIP_DEFLATED,compresslevel=6) as out:
        for entry in z.infolist():
            out.writestr(entry,replacements[entry.filename] if entry.filename in replacements else z.read(entry))
    with ZipFile(out_zip) as check:
        assert zipread(check)==expected
        assert all(z.getinfo(n).external_attr==check.getinfo(n).external_attr for n in before)
        assert sum(n.startswith(payload+'cores/') and n.endswith('.rbf') for n in before)==7
        assert {n for n in before if before[n]!=expected[n]}==set(replacements)
    lines=['status\tRC8_SHA256\tRC9_SHA256\tpath']
    lines.extend(f'{"identical" if h==expected[n] else "changed"}\t{h}\t{expected[n]}\t{n}' for n,h in sorted(before.items()))
    (output/'FILE-DIFF.tsv').write_text('\n'.join(lines)+'\n')

host_dirs=('tools/megavgm_autoplay2','tools/megavgm_playlist','tools/megavgm_profile','tools/megavgm_rbf_bench','tools/megavgm_supervisor','tools/engine_g','tools/k053260_window')
with ZipFile(base_src) as z, ZipFile(out_src,'x',ZIP_DEFLATED,compresslevel=6) as out:
    assert z.testzip() is None
    for entry in z.infolist():
        n=entry.filename
        if n.startswith('Host/') or n in ('Remote/Setup-RC7.patch','SOURCE-ACCESS.md'):
            continue
        if n.startswith('SID/'):
            path='tools/engine_c_c6/'+n.removeprefix('SID/')
            if git(sid_tree,'ls-tree',p['sid'],path).strip():
                out.writestr(entry,git(sid_tree,'show',p['sid']+':'+path))
                continue
        out.writestr(entry,z.read(entry))
    for prefix, repo, ref, paths in (
        ('Host',host_tree,p['host'],host_dirs),
        ('Setup',setup_tree,p['setup'],('cmd/megavgm_full_setup','internal/fullinstall','go.mod','go.sum','LICENSE.backend')),
        ('SID',sid_tree,p['sid'],('tools/engine_c_packed_v2','tools/engine_c_c0')),
    ):
        for name,data,mode in tree(repo,ref,*paths):
            out.writestr(fresh_entry(f'{prefix}/{name}',mode),data)
    for file in ('inputs.json','assemble.py','SOURCE-ACCESS.md'):
        name = file if file=='SOURCE-ACCESS.md' else 'Provenance/RC9/'+file
        out.writestr(fresh_entry(name),(root/file).read_bytes())
    out.writestr(fresh_entry('Provenance/RC9/integration.json'),j(identity))
with ZipFile(out_src) as z:
    source=zipread(z)
    assert source['Setup/internal/fullinstall/sid_cache.go']==sha(git(setup_tree,'show',p['setup']+':internal/fullinstall/sid_cache.go'))
    assert source['Host/tools/megavgm_supervisor/runtime_support.cpp']==sha(git(host_tree,'show',p['host']+':tools/megavgm_supervisor/runtime_support.cpp'))
    assert source['SID/native/megavgm_sid_prepare.cpp']==sha(git(sid_tree,'show',p['sid']+':tools/engine_c_c6/native/megavgm_sid_prepare.cpp'))
for path in (out_zip,out_src):
    print(path.name,path.stat().st_size,sha(path.read_bytes()))
