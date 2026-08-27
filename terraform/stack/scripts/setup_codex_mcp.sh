#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=/dev/null
source /usr/local/sbin/no1-agent-workbench/common.sh

main() {
  local home
  local user group
  local wallet_dir
  local java_home
  local config_file
  local tmp_file

  home="$(app_home)"
  user="$(app_user)"
  group="$(app_group)"
  wallet_dir="$(read_config wallet_dir)"
  java_home="$(detect_java_home)"
  config_file="${home}/.codex/config.toml"
  tmp_file="$(mktemp)"
  trap 'rm -f "${tmp_file}"' EXIT

  log "Codex SQLcl MCP server 設定を ${config_file} に作成します。"
  ensure_opc_owned_dir "${home}/.codex" 0700

  if [[ -f "${config_file}" ]]; then
    awk '
      /^# BEGIN no1-agent-workbench sqlcl mcp$/ {skip=1; next}
      /^# END no1-agent-workbench sqlcl mcp$/ {skip=0; next}
      skip != 1 {print}
    ' "${config_file}" > "${tmp_file}"
  else
    : > "${tmp_file}"
  fi

  cat >> "${tmp_file}" <<EOF

# BEGIN no1-agent-workbench sqlcl mcp
[mcp_servers.sqlcl]
command = "/usr/local/bin/sql"
args = ["-mcp"]
startup_timeout_sec = 30
tool_timeout_sec = 120
enabled = true
required = false

[mcp_servers.sqlcl.env]
JAVA_HOME = "${java_home}"
TNS_ADMIN = "${wallet_dir}"
# END no1-agent-workbench sqlcl mcp
EOF

  install -m 0600 -o "${user}" -g "${group}" "${tmp_file}" "${config_file}"
  chown -R "${user}:${group}" "${home}/.codex"
}

main "$@"
