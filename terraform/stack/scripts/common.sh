#!/usr/bin/env bash
set -Eeuo pipefail

readonly CONFIG_FILE="${NO1_AGENT_WORKBENCH_CONFIG:-/etc/no1-agent-workbench/config.json}"
readonly STATE_DIR="${NO1_AGENT_WORKBENCH_STATE_DIR:-/var/lib/no1-agent-workbench}"
readonly LOG_FILE="${NO1_AGENT_WORKBENCH_LOG:-/var/log/no1-agent-workbench-bootstrap.log}"

log() {
  printf '[%s] %s\n' "$(date -Is)" "$*"
}

fail() {
  log "エラー: $*"
  exit 1
}

retry_command() {
  local max_attempts=$1
  local delay_seconds=$2
  local attempt=1
  local exit_code=0
  shift 2

  while ((attempt <= max_attempts)); do
    log "試行 ${attempt}/${max_attempts}: $*"
    if "$@"; then
      return 0
    fi
    exit_code=$?

    if ((attempt == max_attempts)); then
      return "${exit_code}"
    fi

    sleep "${delay_seconds}"
    ((attempt += 1))
  done
}

read_config() {
  local key=$1

  [[ -s "${CONFIG_FILE}" ]] || fail "設定ファイルがありません: ${CONFIG_FILE}"
  python3 - "${key}" "${CONFIG_FILE}" <<'PY'
import json
import sys

key = sys.argv[1]
path = sys.argv[2]
with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)
value = data.get(key, "")
if value is None:
    value = ""
if isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
PY
}

app_user() {
  read_config app_user
}

app_group() {
  local user
  user="$(app_user)"
  id -gn "${user}"
}

app_home() {
  local user
  user="$(app_user)"
  getent passwd "${user}" | cut -d ':' -f 6
}

opc_path() {
  local home
  home="$(app_home)"
  printf '%s/.npm-global/bin:%s/.local/bin:/usr/local/bin:/usr/bin:/bin' "${home}" "${home}"
}

run_as_opc() {
  local user home path
  user="$(app_user)"
  home="$(app_home)"
  path="$(opc_path)"

  runuser -u "${user}" -- env \
    "HOME=${home}" \
    "USER=${user}" \
    "LOGNAME=${user}" \
    "PATH=${path}" \
    "$@"
}

run_as_opc_shell() {
  local command=$1
  run_as_opc bash -lc "${command}"
}

ensure_opc_owned_dir() {
  local path=$1
  local mode=$2
  local user group
  user="$(app_user)"
  group="$(app_group)"
  install -d -m "${mode}" -o "${user}" -g "${group}" "${path}"
}

detect_java_home() {
  local java_bin
  java_bin="$(command -v java)" || fail "java コマンドが見つかりません。"
  dirname "$(dirname "$(readlink -f "${java_bin}")")"
}
