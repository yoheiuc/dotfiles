# scripts/lib/ui.sh — shared section / ok / warn / info helpers.
# Sourced by doctor.sh, ai-audit.sh, ai-repair.sh, status.sh, post-setup.sh, ai-secrets.sh.
# Note: doctor.sh defines its own fail() that increments REQUIRED_FAILED.

section() { printf '\n\033[1m[%s]\033[0m\n' "$*"; }
ok()      { printf '  \033[1;32m✓\033[0m  %s\n' "$*"; }
warn()    { printf '  \033[1;33m⚠\033[0m  %s\n' "$*"; }
info()    { printf '  - %s\n' "$*"; }
