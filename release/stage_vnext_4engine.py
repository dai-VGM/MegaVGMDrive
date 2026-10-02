#!/usr/bin/env python3
"""Entry point for final v2.2 authority staging and packaging.

Use --build/--verify/--promote-staging/--archive; --final is retained as an alias.
The historical lab assembler is retired to prevent staging stale authorities.
"""
import sys
from promote_v22 import main

if __name__ == "__main__":
    if "--final" in sys.argv:
        sys.argv.remove("--final")
    main()
