#!/usr/bin/env python3
from collections import Counter
from pathlib import Path
import re, subprocess

ROOT=Path(__file__).resolve().parents[1]
HW=ROOT/'hw/engine_c_packed_v2'
PROD=HW/'MegaVGMPlayer_EngineC_C7_2_Validation_MiSTer.qsf'
VIS=HW/'MegaVGMPlayer_EngineC_C7_2_OSD_Visual_MiSTer.qsf'

def resolve(path):
    out=subprocess.check_output(['tclsh','tools/engine_c_c2/audit_qsf.tcl',str(path)],cwd=ROOT,text=True)
    return [line.split('\t',1) for line in out.splitlines()]

prod=resolve(PROD); vis=resolve(VIS)
def files(rows): return [v for k,v in rows if k in ('SYSTEMVERILOG_FILE','VERILOG_FILE','VHDL_FILE')]
pf,vf=files(prod),files(vis)
assert len(pf)==len(set(pf)); assert len(vf)==len(set(vf))
old=str((ROOT/'rtl/megavgm_title_renderer.sv').resolve())
new=str((ROOT/'rtl/engine_c_packed_v2/megavgm_title_renderer_engine_c.sv').resolve())
hist=str((ROOT/'rtl/engine_c_packed_v2/sid_activity_history.sv').resolve())
assert pf.count(old)==1 and old not in vf
assert vf.count(new)==1 and vf.count(hist)==1 and new not in pf and hist not in pf
common=set(pf)-{old}; assert common==set(vf)-{new,hist}
macros=[v for k,v in vis if k=='MACRO']
assert macros.count('MEGAVGMDRIVE_ENGINE_C_ACTIVITY_OSD=1')==1
prod_assign=Counter((k,v) for k,v in prod if k not in ('SYSTEMVERILOG_FILE','VERILOG_FILE','VHDL_FILE'))
vis_assign=Counter((k,v) for k,v in vis if k not in ('SYSTEMVERILOG_FILE','VERILOG_FILE','VHDL_FILE'))
prod_assign[('QIP_FILE',str((HW/'files_engine_c_packed_v2.qip').resolve()))]-=1
vis_assign[('QIP_FILE',str((HW/'files_engine_c_c7_2_osd_visual.qip').resolve()))]-=1
vis_assign[('MACRO','MEGAVGMDRIVE_ENGINE_C_ACTIVITY_OSD=1')]-=1
assert +prod_assign==+vis_assign
for path in (VIS,HW/'files_engine_c_c7_2_osd_visual.qip'):
    text=path.read_text()
    assert not re.search(r'^\s*(set\s+::|unset\s+::|remove_global_assignment)',text,re.M)
    assert '-remove' not in text
emu=(ROOT/'rtl/engine_c_c2/shell/emu_c2.sv').read_text()
assert '"F1,MVG,Load prepared SID;"' in emu
conf_start=emu.index('localparam CONF_STR')
conf_dev=emu.index('`ifdef MEGAVGMDRIVE_DEV_OSD',conf_start)
visual_menu=emu[emu.index('"F1,MVG,Load prepared SID;"',conf_start):conf_dev]
assert '`ifndef MEGAVGMDRIVE_ENGINE_C_ACTIVITY_OSD' in emu[conf_start:conf_dev]
assert 'Audio Gain' in visual_menu and 'SegaPCM Audio' in visual_menu
sys=(ROOT/'sys/sys_top.v').read_text()
assert '`ifndef MEGAVGMDRIVE_ENGINE_C_ACTIVITY_OSD' in sys
assert '`ifdef MEGAVGMDRIVE_ENGINE_C_ACTIVITY_OSD\n\tvgm_status_heartbeat_pixel = 1\'b0;' in sys
engine=(ROOT/'rtl/engine_c_packed_v2/engine_c_lab.sv').read_text()
assert 'assign sid_model_8580=session_model;' in engine
assert 'assign sid_timing_ntsc=(session_timing==8\'d2);' in engine
print('ENGINE_C_OSD_STATIC_GRAPH_PASS production=%d visual=%d'%(len(pf),len(vf)))
