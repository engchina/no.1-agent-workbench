#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=/dev/null
source /usr/local/sbin/no1-agent-workbench/common.sh

assert_owner() {
  local path=$1
  local expected_owner=$2
  local actual_owner

  actual_owner="$(stat -c '%U:%G' "${path}")"
  [[ "${actual_owner}" == "${expected_owner}" ]] \
    || fail "${path} の owner は ${expected_owner} である必要があります。実際: ${actual_owner}"
}

assert_mode() {
  local path=$1
  local expected_mode=$2
  local actual_mode

  actual_mode="$(stat -c '%a' "${path}")"
  [[ "${actual_mode}" == "${expected_mode}" ]] \
    || fail "${path} の mode は ${expected_mode} である必要があります。実際: ${actual_mode}"
}

verify_sqlcl_connection() {
  local wallet_dir
  local java_home
  local sql_script

  wallet_dir="$(read_config wallet_dir)"
  java_home="$(detect_java_home)"
  sql_script="${STATE_DIR}/verify-agent-workbench.sql"

  umask 077
  {
    printf '%s\n' 'set echo off'
    printf '%s\n' 'set heading off'
    printf '%s\n' 'set feedback off'
    printf '%s\n' 'set pagesize 0'
    printf '%s\n' 'whenever sqlerror exit failure rollback'
    printf '%s\n' 'conn -name agent_workbench'
    printf "%s\n" "select 'AGENT_WORKBENCH_SQLCL_OK' from dual;"
    printf '%s\n' 'exit success'
  } > "${sql_script}"
  chown "$(app_user):$(app_group)" "${sql_script}"
  chmod 0600 "${sql_script}"

  retry_command 5 20 run_as_opc env \
    "JAVA_HOME=${java_home}" \
    "TNS_ADMIN=${wallet_dir}" \
    sql -s /nolog "@${sql_script}" \
    || fail "SQLcl saved connection agent_workbench の接続検証に失敗しました。"
  rm -f "${sql_script}"
}

main() {
  local home
  local user group owner
  local wallet_dir workspace_dir app_root
  local npm_prefix
  local bad_wallet_file
  local bad_wallet_dir

  home="$(app_home)"
  user="$(app_user)"
  group="$(app_group)"
  owner="${user}:${group}"
  app_root="$(read_config app_root)"
  wallet_dir="$(read_config wallet_dir)"
  workspace_dir="$(read_config workspace_dir)"

  log "no.1-agent-workbench の検証を開始します。"
  node -v | grep -Eq '^v24\.' || fail "Node.js 24 を確認できません。"
  npm -v >/dev/null || fail "npm を確認できません。"
  uv --version >/dev/null || fail "uv を確認できません。"
  uvx --version >/dev/null || fail "uvx を確認できません。"
  sql -version >/dev/null || fail "SQLcl を確認できません。"
  run_as_opc codex --version >/dev/null || fail "opc ユーザーで Codex CLI を実行できません。"

  npm_prefix="$(run_as_opc npm config get prefix)"
  [[ "${npm_prefix}" == "${home}/.npm-global" ]] \
    || fail "opc の npm prefix が ${home}/.npm-global ではありません。実際: ${npm_prefix}"

  assert_owner "${home}/.npm-global" "${owner}"
  assert_owner "${home}/.npm" "${owner}"
  assert_owner "${home}/.cache" "${owner}"
  assert_owner "${home}/.local" "${owner}"
  assert_owner "${home}/.codex" "${owner}"
  assert_owner "${home}/.dbtools" "${owner}"
  assert_owner "${app_root}" "${owner}"
  assert_owner "${wallet_dir}" "${owner}"
  assert_owner "${workspace_dir}" "${owner}"
  assert_owner "${home}/.codex/config.toml" "${owner}"
  assert_mode "${wallet_dir}" "700"
  assert_mode "${home}/.codex/config.toml" "600"

  bad_wallet_file="$(find "${wallet_dir}" -type f ! -perm 0600 -print -quit)"
  [[ -z "${bad_wallet_file}" ]] \
    || fail "wallet directory に 0600 ではないファイルがあります: ${bad_wallet_file}"
  bad_wallet_dir="$(find "${wallet_dir}" -type d ! -perm 0700 -print -quit)"
  [[ -z "${bad_wallet_dir}" ]] \
    || fail "wallet directory に 0700 ではない directory があります: ${bad_wallet_dir}"

  grep -q 'command = "/usr/local/bin/sql"' "${home}/.codex/config.toml" \
    || fail "Codex MCP config に SQLcl command がありません。"
  grep -q 'TNS_ADMIN' "${home}/.codex/config.toml" \
    || fail "Codex MCP config に TNS_ADMIN がありません。"
  grep -q 'JAVA_HOME' "${home}/.codex/config.toml" \
    || fail "Codex MCP config に JAVA_HOME がありません。"

  verify_sqlcl_connection
  log "no.1-agent-workbench の検証が完了しました。"
}

main "$@"
