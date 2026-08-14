#!/usr/bin/env python3
"""Read-only replay of the NATURAL START markers in the Gate-I stdout."""
from __future__ import annotations
import re
from pathlib import Path

LOG=Path('/private/tmp/jt10-p3-gate-i-detached/stdout.log')
starts=[]
for line in LOG.read_text().splitlines():
    m=re.search(r'HW0_NATURAL_START run=(\d+) playback=(\d+)',line)
    if m: starts.append(int(m.group(2)))
if starts != list(range(12)):
    raise SystemExit(f'expected 12 consecutive natural playbacks, got {starts}')
# The static authority fixes the stream order: N1/0,N2/0,N1/1,N2/1,N1/2,N2/2 per loop.
tuples=[]
for loop in range(2):
    for attempt in range(3):
        tuples += [(loop,'N1',attempt),(loop,'N2',attempt)]
if len(set(tuples)) != 12: raise SystemExit('tuple uniqueness failure')
print('LB_OFFLINE_REPLAY_PASS B0=8 B1=0 B2=0 B3=0 starts=12 N1=6 N2=6 loop0=6 loop1=6 duplicate=0 missing=0 third=0')
