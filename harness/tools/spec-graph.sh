#!/bin/bash
# spec-graph.sh — reference graph of the specification (clause ID reference resolution, cycle and section-number reference detection, stale detection)
#
# Stop the structure where each SPEC restates the common items. Write each "clause" of the base
# specification once and reference it with [ID](path#ID). Machine-verify that each reference exists,
# that references do not form a cycle, and that no string reference by section number remains.
# The frontmatter xref-prefix declaration decides which files have clauses.
# The referrers include documents and also test names (the [[ID]] in the first argument of describe / it / test).
#
# Usage:
#   spec-graph.sh verify            Verify V1 to V3 / V5 / V6 / V8 to V11 (0 violations = exit 0 / violations = exit 1)
#   spec-graph.sh index             Print the graph as JSON to stdout (nodes carry a content hash)
#   spec-graph.sh diff <git-ref>    Print the clauses whose content changed since <git-ref>, and their referrers
#   spec-graph.sh reverse <ID>      List the places that reference <ID> as file:line
#   spec-graph.sh deps <FILE>       List the clauses that <FILE> references
#   spec-graph.sh files             List the files that have clauses (prefix, layer, clause count, referenced count)
#   spec-graph.sh layers            Table of reference edge counts, layer x layer (the direction is a metric, not a constraint)
#   spec-graph.sh resolve <FILE>    Print the source text and the body of each clause reached from it
#
# Set the environment variable SPEC_GRAPH_ROOT to replace the scan root (default: the repository root).
# All output goes to stdout (the caller judges by both the exit code and the output).
set -euo pipefail
. "$(dirname "$(readlink -f "$0")")/../lib/env.sh"
ROOT="${SPEC_GRAPH_ROOT:-$(sprint_root)}"

# The core is spec-graph.py in the same directory (you can also start it alone: python3 spec-graph.py <ROOT> <cmd>).
exec python3 "$(dirname "$(readlink -f "$0")")/spec-graph.py" "$ROOT" "$@"
