#!/usr/bin/env bash

AI_CONFIG_LEGACY_PATTERN='approval_policy[[:space:]]*=[[:space:]]*"never"|sandbox_mode[[:space:]]*=[[:space:]]*"danger-full-access"|BEGIN CCB|END CCB|ai-bridge|cc-bridge|codex-dual|\bccb\b'

ai_config_file_size_bytes() {
  wc -c < "$1" | tr -d '[:space:]'
}

ai_config_describe_file() {
  local label="$1"
  local path="$2"
  local include_size="${3:-0}"

  if [[ -f "${path}" ]]; then
    if [[ "${include_size}" == "1" ]]; then
      printf '%s: present (%s, %s bytes)\n' "${label}" "${path}" "$(ai_config_file_size_bytes "${path}")"
    else
      printf '%s: present (%s)\n' "${label}" "${path}"
    fi
  else
    printf '%s: missing (%s)\n' "${label}" "${path}"
  fi
}

ai_config_has_legacy_settings() {
  local path="$1"
  local pattern="${2:-${AI_CONFIG_LEGACY_PATTERN}}"

  [[ -f "${path}" ]] || return 1
  grep -Eq "${pattern}" "${path}"
}

ai_config_file_contains_regex() {
  local path="$1"
  local pattern="$2"

  [[ -f "${path}" ]] || return 1
  grep -Eq "${pattern}" "${path}"
}

ai_config_backup_matches() {
  local glob_pattern="$1"
  compgen -G "${glob_pattern}" || true
}

ai_config_strip_codex_path_warning() {
  sed '/^WARNING: proceeding, even though we could not update PATH:/d'
}

ai_config_run_with_timeout() {
  local timeout_seconds="$1"
  shift
  python3 - "$timeout_seconds" "$@" <<'PY'
import subprocess
import sys

timeout = float(sys.argv[1])
cmd = sys.argv[2:]

def write_maybe_bytes(stream, value):
    if value is None:
        return
    if isinstance(value, bytes):
        stream.write(value.decode("utf-8", errors="replace"))
    else:
        stream.write(value)

try:
    completed = subprocess.run(cmd, text=True, capture_output=True, timeout=timeout)
except subprocess.TimeoutExpired as exc:
    write_maybe_bytes(sys.stdout, exc.stdout)
    write_maybe_bytes(sys.stderr, exc.stderr)
    sys.stderr.write(f"Timed out after {timeout:g}s\n")
    raise SystemExit(124)

write_maybe_bytes(sys.stdout, completed.stdout)
write_maybe_bytes(sys.stderr, completed.stderr)
raise SystemExit(completed.returncode)
PY
}

ai_config_codex_serena_registration_state() {
  local output="$1"
  local wrapper_path="$2"

  if printf '%s\n' "${output}" | grep -Eq "^serena[[:space:]]+${wrapper_path//\//\\/}[[:space:]].*[[:space:]]enabled[[:space:]]"; then
    printf 'wrapper\n'
  elif printf '%s\n' "${output}" | grep -Eq '^serena[[:space:]]+uvx[[:space:]].*[[:space:]]enabled[[:space:]]'; then
    printf 'legacy-uvx\n'
  elif printf '%s\n' "${output}" | grep -q '^serena[[:space:]]'; then
    printf 'unexpected\n'
  elif printf '%s\n' "${output}" | grep -q '^Timed out after '; then
    printf 'timeout\n'
  else
    printf 'missing\n'
  fi
}

ai_config_claude_serena_registration_state() {
  local output="$1"
  local claude_json_path="$2"

  if printf '%s\n' "${output}" | grep -q '^Timed out after '; then
    if rg -q '"serena"[[:space:]]*:' "${claude_json_path}" 2>/dev/null; then
      printf 'registered-timeout\n'
    else
      printf 'timeout\n'
    fi
  elif printf '%s\n' "${output}" | grep -Eq '^serena:.*- ✓ Connected$'; then
    printf 'connected\n'
  elif printf '%s\n' "${output}" | grep -q '^serena:'; then
    printf 'disconnected\n'
  else
    printf 'missing\n'
  fi
}
