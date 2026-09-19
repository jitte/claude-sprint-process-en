#!/bin/bash
# impl-sync — compare the public route set of the implementation and the route set written in the spec in both directions (TEST gate).
#
# Usage: impl-sync.sh [routes]
#   routes : harness/tools/api-routes.sh verify (public route set of the implementation ↔ route set written in 05)
#
# Do not get the implementation set with a regex. Import the implementation and make it print the set (dump-routes.ts).
# A regex cannot list all key notations, comments, and braces in strings, and the elements it misses silently disappear
# from the set. A failure that shrinks the set makes the gate itself hide the state that this gate must detect.
#
# Project-specific set comparisons are in the project part of gateToolsDirs
# (the gates in the config call them as separate tools).
#
# Environment variables (entry point for the tests):
#   API_ROUTES_IMPL_CMD / API_ROUTES_ROOT   routes (api-routes.sh reads them)
#
# Exit code = failure class.
#   1 = spec (in the implementation but not in the spec → back to PLAN)
#   2 = impl (in the spec but not in the implementation → back to BUILD)
#   4 = infra (cannot read the target, or getting the implementation set failed)
set -uo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib/env.sh"
sprint_config_require
REPO_ROOT=$(sprint_root)
CHECKS=("$@")
[ ${#CHECKS[@]} -gt 0 ] || CHECKS=(routes)

for c in "${CHECKS[@]}"; do
  case "$c" in
    routes) bash "$(dirname "$(readlink -f "$0")")/../tools/api-routes.sh" verify; exit $? ;;
    *) echo "unknown check: $c"; exit 4 ;;
  esac
done
