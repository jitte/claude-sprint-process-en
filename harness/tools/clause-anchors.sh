#!/bin/bash
# clause-anchors.sh — place clause anchors and turn references into links
#
# [[ID]] does not link to its target on GitHub or in Obsidian. Put an explicit
# anchor <a id="ID"></a> directly before each clause heading, and change each reference into a Markdown link.
# An id generated from a heading includes the heading text, so a wording change breaks the link.
#
# Usage:
#   clause-anchors.sh           Apply the conversion (idempotent. A second run does not insert anything twice)
#   clause-anchors.sh --check   Do not write. List the files that need a change
#                               (exit 1 if a change is needed / exit 0 if not)
#
# Set the environment variable CLAUSE_ANCHORS_ROOT to replace the scan root (default: the repository root).
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib/env.sh"
ROOT="${CLAUSE_ANCHORS_ROOT:-$(sprint_root)}"

# The core is clause-anchors.py in the same directory.
exec python3 "$(dirname "$(readlink -f "$0")")/clause-anchors.py" "$ROOT" "$@"
