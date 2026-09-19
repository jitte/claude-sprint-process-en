#!/bin/bash
# spec-coverage.sh — clause reference coverage of the base specification (cov / rcov / tcov). It is a metric and does not fail.
#
# Usage:
#   spec-coverage.sh                 Include the SPEC.md of the active sprint
#   spec-coverage.sh --sprint <id>   Select the sprint by sprint ID
#   spec-coverage.sh --spec <path>   Select by the path of a SPEC.md
#   spec-coverage.sh --no-sprint     Base specification only
#   spec-coverage.sh --unreferenced  List the unreferenced clause IDs at the end
#   spec-coverage.sh --untested      List, per document, the specDir clause IDs that no test references
#   spec-coverage.sh --json          Machine-readable
#
# Set the environment variable SPEC_GRAPH_ROOT to replace the scan root (default: the project root).
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib/env.sh"
ROOT="${SPEC_GRAPH_ROOT:-$(sprint_root)}"

# The core is spec-coverage.py in the same directory (you can also start it alone: python3 spec-coverage.py <ROOT> [options]).
exec python3 "$(dirname "$(readlink -f "$0")")/spec-coverage.py" "$ROOT" "$@"
