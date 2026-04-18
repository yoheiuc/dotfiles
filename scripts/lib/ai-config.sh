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

# Resolve a Python 3.11+ interpreter that has `tomllib` in its stdlib. macOS
# ships `/usr/bin/python3` as 3.9 which lacks tomllib, so fall back to
# homebrew-installed pythons when the default is too old. Cached per shell.
ai_config_python_with_tomllib() {
  if [[ -n "${_AI_CONFIG_PY_TOMLLIB:-}" ]]; then
    printf '%s\n' "${_AI_CONFIG_PY_TOMLLIB}"
    return 0
  fi
  local candidate
  for candidate in python3 python3.14 python3.13 python3.12 python3.11; do
    if command -v "${candidate}" >/dev/null 2>&1 \
       && "${candidate}" -c 'import tomllib' 2>/dev/null; then
      _AI_CONFIG_PY_TOMLLIB="${candidate}"
      printf '%s\n' "${_AI_CONFIG_PY_TOMLLIB}"
      return 0
    fi
  done
  # No tomllib-capable Python found — caller will silently degrade (same as
  # the pre-fallback behavior).
  _AI_CONFIG_PY_TOMLLIB="python3"
  printf '%s\n' "${_AI_CONFIG_PY_TOMLLIB}"
  return 1
}

# Read a field from a TOML file using python/tomllib.
# Usage: ai_config_toml_read <file> <python_expr>
#   python_expr receives the parsed TOML as `d`.
ai_config_toml_read() {
  local file="$1"
  local expr="$2"
  [[ -f "${file}" ]] || return 1
  local py
  py="$(ai_config_python_with_tomllib)" || true
  "${py}" -c "
import sys
try:
    import tomllib
except ModuleNotFoundError:
    sys.exit(1)

try:
    with open(sys.argv[1], 'rb') as f:
        d = tomllib.load(f)
    v = ${expr}
    if v is None or v == '':
        sys.exit(1)
    print(v)
except Exception:
    sys.exit(1)
" "${file}"
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

# Remove an entry from a JSON file's mcpServers map. No-op if absent.
# Usage: ai_config_json_remove_mcp <file> <server_name>
# Prints "removed" if the key existed (and was stripped), "absent" otherwise.
ai_config_json_remove_mcp() {
  local file="$1"
  local name="$2"
  [[ -f "${file}" ]] || { printf 'absent\n'; return 0; }
  python3 -c "
import json, sys

fpath = sys.argv[1]
name  = sys.argv[2]

with open(fpath) as f:
    d = json.load(f)

servers = d.get('mcpServers', {})
if name in servers:
    del servers[name]
    with open(fpath, 'w') as f:
        json.dump(d, f, indent=2)
        f.write('\n')
    print('removed')
else:
    print('absent')
" "${file}" "${name}"
}

# Remove a [mcp_servers.<name>] section and any [mcp_servers.<name>.*] child
# sections from a TOML file. No-op if absent.
# Usage: ai_config_toml_remove_mcp_section <file> <server_name>
# Prints "removed" if any section was stripped, "absent" otherwise.
ai_config_toml_remove_mcp_section() {
  local file="$1"
  local name="$2"
  [[ -f "${file}" ]] || { printf 'absent\n'; return 0; }
  python3 -c "
import pathlib, re, sys

fpath = pathlib.Path(sys.argv[1]).expanduser()
name  = sys.argv[2]
content = fpath.read_text()

# Match the exact [mcp_servers.<name>] header or any [mcp_servers.<name>.<...>]
# child header, and the body up to the next section.
pattern = re.compile(
    r'(?m)^\[mcp_servers\.' + re.escape(name) + r'(?:\..*)?\]\s*\n(?:^(?!\[).*(?:\n|$))*'
)
new_content, count = pattern.subn('', content)
if count == 0:
    print('absent')
    sys.exit(0)

# Collapse runs of 3+ blank lines left behind by removal into a single blank line.
new_content = re.sub(r'\n{3,}', '\n\n', new_content)
fpath.write_text(new_content.rstrip('\n') + '\n')
print('removed')
" "${file}" "${name}"
}

# Upsert a top-level JSON key.
# Usage: ai_config_json_upsert_key <file> <key> <json_value>
ai_config_json_upsert_key() {
  local file="$1"
  local key="$2"
  local value="$3"
  python3 -c "
import json, sys, os

fpath = sys.argv[1]
key = sys.argv[2]
value = json.loads(sys.argv[3])

if os.path.isfile(fpath):
    with open(fpath) as f:
        d = json.load(f)
else:
    d = {}

d[key] = value

with open(fpath, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
" "${file}" "${key}" "${value}"
}

ai_config_toml_upsert_top_level() {
  local file="$1"
  local key="$2"
  local value="$3"
  python3 -c "
import pathlib, re, sys

fpath = pathlib.Path(sys.argv[1]).expanduser()
key = sys.argv[2]
value = sys.argv[3]

content = fpath.read_text() if fpath.exists() else ''
section_match = re.search(r'(?m)^\[', content)
prefix_end = section_match.start() if section_match else len(content)
prefix = content[:prefix_end]
suffix = content[prefix_end:]
line = f'{key} = {value}'

pattern = re.compile(rf'(?m)^{re.escape(key)}\s*=.*$')
if pattern.search(prefix):
    prefix = pattern.sub(line, prefix, count=1)
else:
    stripped = prefix.rstrip('\n')
    if stripped:
        prefix = stripped + '\n' + line + '\n\n'
    else:
        prefix = line + '\n\n'

fpath.parent.mkdir(parents=True, exist_ok=True)
fpath.write_text(prefix + suffix.lstrip('\n'))
" "${file}" "${key}" "${value}"
}

ai_config_toml_upsert_section_block() {
  local file="$1"
  local section_header="$2"
  local body="$3"
  python3 -c "
import pathlib, re, sys

fpath = pathlib.Path(sys.argv[1]).expanduser()
section_header = sys.argv[2]
body = sys.argv[3].rstrip('\n')

content = fpath.read_text() if fpath.exists() else ''
new_block = f'{section_header}\n{body}\n'
pattern = re.compile(
    rf'(?m)^{re.escape(section_header)}\s*\n(?:^(?!\[).*(?:\n|$))*'
)

if pattern.search(content):
    content = pattern.sub(new_block, content, count=1)
else:
    stripped = content.rstrip('\n')
    if stripped:
      content = stripped + '\n\n' + new_block
    else:
      content = new_block

fpath.parent.mkdir(parents=True, exist_ok=True)
fpath.write_text(content.rstrip('\n') + '\n')
" "${file}" "${section_header}" "${body}"
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

  local actual_command
  actual_command="$(ai_config_toml_read "${file}" "d.get('mcp_servers',{}).get('serena',{}).get('command','')" 2>/dev/null)" || { printf 'missing\n'; return; }

  if [[ "${actual_command}" == "${expected_command}" ]]; then
    printf 'ok\n'
  else
    printf 'wrong-command\n'
  fi
}

ai_config_codex_mcp_url_state() {
  local file="$1"
  local server_name="$2"
  local expected_url="$3"

  local actual_url
  actual_url="$(ai_config_toml_read "${file}" "d.get('mcp_servers',{}).get('${server_name}',{}).get('url','')" 2>/dev/null)" || { printf 'missing\n'; return; }

  if [[ "${actual_url}" == "${expected_url}" ]]; then
    printf 'ok\n'
  else
    printf 'wrong-url\n'
  fi
}

# ---- Keychain / legacy env credential helpers --------------------------------

# Read a secret from macOS Keychain.
# Usage: ai_config_read_keychain_secret <account>
# Requires SECURITY_BIN and KEYCHAIN_SERVICE to be set by the caller.
ai_config_read_keychain_secret() {
  local account="$1"
  local security_bin="${SECURITY_BIN:-security}"
  local service="${KEYCHAIN_SERVICE:-dotfiles.ai.mcp}"

  if ! command -v "${security_bin}" >/dev/null 2>&1; then
    printf ''
    return 0
  fi
  "${security_bin}" find-generic-password -w -s "${service}" -a "${account}" 2>/dev/null || true
}

# Read a secret from the legacy plaintext env file.
# Usage: ai_config_read_legacy_env_secret <env_name>
# Requires AI_SHARED_ENV_FILE (and optionally AI_SHARED_ENV_FALLBACK_FILE) to
# be set by the caller.
ai_config_read_legacy_env_secret() {
  local env_name="$1"
  local env_file="${AI_SHARED_ENV_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/ai-secrets.env}"
  local fallback="${AI_SHARED_ENV_FALLBACK_FILE:-${HOME}/.config/dotfiles/ai-secrets.env}"

  if [[ ! -f "${env_file}" && "${fallback}" != "${env_file}" && -f "${fallback}" ]]; then
    env_file="${fallback}"
  fi

  if [[ ! -f "${env_file}" ]]; then
    printf ''
    return 0
  fi

  env -i bash -lc "
    set -a
    source '${env_file}'
    set +a
    printf '%s' \"\${${env_name}:-}\"
  " 2>/dev/null
}

# Resolve a secret — try Keychain first, fall back to legacy env file.
# Usage: ai_config_resolve_secret <env_name> <keychain_account>
ai_config_resolve_secret() {
  local env_name="$1"
  local account="$2"
  local secret=""

  secret="$(ai_config_read_keychain_secret "${account}")"
  if [[ -z "${secret}" ]]; then
    secret="$(ai_config_read_legacy_env_secret "${env_name}")"
  fi
  printf '%s' "${secret}"
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
