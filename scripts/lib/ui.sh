# scripts/lib/ui.sh — shared stdout formatters for diagnostic / setup scripts.
# Sourced by doctor.sh, ai-audit.sh, ai-repair.sh, status.sh, post-setup.sh, ai-secrets.sh.
#
# Tone convention (keep consistent across callers — tests grep on these glyphs):
#   section  : bold "[Heading]" line, blank line above. Top-level grouping.
#   subgroup : dim "── Heading ──" rule. Visual separator between bands of
#              related sections (e.g. doctor.sh optional checks split into
#              shell / runtimes / cloud / etc). Skipped when not needed.
#   ok       : green check — operation succeeded or invariant holds.
#   warn     : yellow ⚠ — attention but not a failure (drift detected, etc.).
#   info     : neutral hyphen bullet — metadata / context detail.
#
# `fail()` is intentionally not defined here. doctor.sh owns its own fail() that
# increments REQUIRED_FAILED; ai-audit.sh / status.sh use warn() instead since
# they are read-only and never short-circuit a run.

section()  { printf '\n\033[1m[%s]\033[0m\n' "$*"; }
subgroup() { printf '\n\033[2m── %s ──\033[0m\n' "$*"; }
ok()       { printf '  \033[1;32m✓\033[0m  %s\n' "$*"; }
warn()     { printf '  \033[1;33m⚠\033[0m  %s\n' "$*"; }
info()     { printf '  - %s\n' "$*"; }
