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

# Read a field from a JSON file using python3.
# Usage: ai_config_json_read <file> <python_expr>
#   python_expr receives the parsed JSON as `d`.
#   Example: ai_config_json_read ~/.claude.json 'd.get("mcpServers",{}).get("serena",{}).get("command","")'
# Returns empty string and exit 1 if file missing or field absent.
ai_config_json_read() {
  local file="$1"
  local expr="$2"
  [[ -f "${file}" ]] || return 1
  python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    v = ${expr}
    if v is None or v == '':
        sys.exit(1)
    print(v)
except Exception:
    sys.exit(1)
" "${file}"
}

# Upsert a key into a JSON file's mcpServers map.
# Usage: ai_config_json_upsert_mcp <file> <server_name> <json_value>
#   Creates the file (with mcpServers only) if it doesn't exist.
ai_config_json_upsert_mcp() {
  local file="$1"
  local name="$2"
  local value="$3"
  python3 -c "
import json, sys, os

fpath = sys.argv[1]
name  = sys.argv[2]
value = json.loads(sys.argv[3])

if os.path.isfile(fpath):
    with open(fpath) as f:
        d = json.load(f)
else:
    d = {}

d.setdefault('mcpServers', {})[name] = value

with open(fpath, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "${file}" "${name}" "${value}"
}

# Check MCP registration state in a JSON file.
# Usage: ai_config_mcp_registration_state <file> <server_name> <expected_command>
# Prints one of: ok, wrong-command, missing
ai_config_mcp_registration_state() {
  local file="$1"
  local name="$2"
  local expected_command="$3"

  local actual_command
  if actual_command="$(ai_config_json_read "${file}" "d.get('mcpServers',{}).get('${name}',{}).get('command','')")"; then
    if [[ "${actual_command}" == "${expected_command}" ]]; then
      printf 'ok\n'
    else
      printf 'wrong-command\n'
    fi
  else
    printf 'missing\n'
  fi
}

# Check Codex serena MCP state in config.toml.
# Usage: ai_config_codex_mcp_state <config_toml> <expected_command>
# Prints one of: ok, wrong-command, missing
ai_config_codex_mcp_state() {
  local file="$1"
  local expected_command="$2"

  [[ -f "${file}" ]] || { printf 'missing\n'; return; }

  local actual_command
  actual_command="$(python3 -c "
import sys, re
content = open(sys.argv[1]).read()
# Simple TOML parsing for [mcp_servers.serena] command
m = re.search(r'^\[mcp_servers\.serena\]\s*\n(?:.*\n)*?command\s*=\s*\"([^\"]+)\"', content, re.MULTILINE)
if m:
    print(m.group(1))
else:
    sys.exit(1)
" "${file}" 2>/dev/null)" || { printf 'missing\n'; return; }

  if [[ "${actual_command}" == "${expected_command}" ]]; then
    printf 'ok\n'
  else
    printf 'wrong-command\n'
  fi
}

# Upsert serena MCP entry in Codex config.toml.
# Usage: ai_config_codex_upsert_mcp <config_toml> <server_name> <command> <arg>
ai_config_codex_upsert_mcp() {
  local file="$1"
  local name="$2"
  local command="$3"
  local arg="$4"

  python3 -c "
import sys, re, os

fpath   = sys.argv[1]
name    = sys.argv[2]
command = sys.argv[3]
arg     = sys.argv[4]

section_header = f'[mcp_servers.{name}]'
new_block = f'{section_header}\ncommand = \"{command}\"\nargs = [\"{arg}\"]\n'

if os.path.isfile(fpath):
    content = open(fpath).read()
else:
    content = ''

# Replace existing section or append
pattern = re.compile(
    r'^\[mcp_servers\.' + re.escape(name) + r'\]\s*\n(?:(?!\[).*\n)*',
    re.MULTILINE,
)
if pattern.search(content):
    content = pattern.sub(new_block, content)
else:
    content = content.rstrip('\n') + '\n\n' + new_block

with open(fpath, 'w') as f:
    f.write(content)
" "${file}" "${name}" "${command}" "${arg}"
}
