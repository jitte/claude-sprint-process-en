#!/bin/bash
# Test runner of the harness. It does not depend on bun / node.
set -euo pipefail

python3 -m unittest discover -s "$(dirname "$(readlink -f "$0")")" -p 'test_*.py' -v
