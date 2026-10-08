#!/usr/bin/env python3
"""Current entry point. Immutable original verifier is in history/96edaa2/tools/."""
from verify_v240 import verify
import json
if __name__=='__main__':print(json.dumps(verify(),indent=2))
