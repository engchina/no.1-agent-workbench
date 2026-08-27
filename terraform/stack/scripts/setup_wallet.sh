#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=/dev/null
source /usr/local/sbin/no1-agent-workbench/common.sh

main() {
  local wallet_dir
  local wallet_zip
  local user group
  local oracle_user
  local oracle_password
  local oracle_dsn
  local sql_script
  local sql_log
  local java_home

  wallet_dir="$(read_config wallet_dir)"
  wallet_zip="${wallet_dir}/wallet.zip"
  user="$(app_user)"
  group="$(app_group)"
  oracle_user="$(read_config oracle_user)"
  oracle_password="$(read_config oracle_password)"
  oracle_dsn="$(read_config oracle_dsn)"
  java_home="$(detect_java_home)"
  sql_script="${STATE_DIR}/save-agent-workbench-connection.sql"
  sql_log="/var/log/no1-agent-workbench-sqlcl-setup.log"
  trap 'rm -f "${sql_script}"' EXIT

  [[ -s /etc/no1-agent-workbench/wallet.zip ]] \
    || fail "cloud-init から配置された wallet ZIP がありません。"
  [[ -n "${oracle_user}" && -n "${oracle_password}" && -n "${oracle_dsn}" ]] \
    || fail "Oracle 接続情報が不足しています。"

  log "ADB wallet を ${wallet_dir} に配置します。"
  ensure_opc_owned_dir "${wallet_dir}" 0700
  install -m 0600 -o "${user}" -g "${group}" /etc/no1-agent-workbench/wallet.zip "${wallet_zip}"
  run_as_opc unzip -oq "${wallet_zip}" -d "${wallet_dir}" \
    || fail "ADB wallet ZIP の展開に失敗しました。"

  cat > "${wallet_dir}/sqlnet.ora" <<EOF
WALLET_LOCATION=(SOURCE=(METHOD=file)(METHOD_DATA=(DIRECTORY=${wallet_dir})))
SSL_SERVER_DN_MATCH=yes
EOF
  cat > "${wallet_dir}/ojdbc.properties" <<EOF
oracle.net.wallet_location=(SOURCE=(METHOD=FILE)(METHOD_DATA=(DIRECTORY=${wallet_dir})))
EOF

  chown -R "${user}:${group}" "${wallet_dir}"
  find "${wallet_dir}" -type d -exec chmod 0700 {} \;
  find "${wallet_dir}" -type f -exec chmod 0600 {} \;

  log "SQLcl saved connection agent_workbench を opc として作成します。"
  umask 077
  {
    printf '%s\n' 'set echo off'
    printf '%s\n' 'set feedback off'
    printf '%s\n' 'whenever sqlerror exit failure rollback'
    printf 'conn -save agent_workbench -savepwd -cloudconfig %s %s/%s@%s\n' \
      "${wallet_zip}" "${oracle_user}" "${oracle_password}" "${oracle_dsn}"
    printf "%s\n" "select 'AGENT_WORKBENCH_READY' as status from dual;"
    printf '%s\n' 'exit success'
  } > "${sql_script}"
  chown "${user}:${group}" "${sql_script}"
  chmod 0600 "${sql_script}"
  : > "${sql_log}"
  chmod 0600 "${sql_log}"

  retry_command 8 30 run_as_opc env \
    "JAVA_HOME=${java_home}" \
    "TNS_ADMIN=${wallet_dir}" \
    sql -s /nolog "@${sql_script}" \
    > "${sql_log}" 2>&1 \
    || {
      tail -n 80 "${sql_log}" || true
      fail "SQLcl saved connection の作成に失敗しました。"
    }
  rm -f "${sql_script}"

  ensure_opc_owned_dir "$(app_home)/.dbtools" 0700
  chown -R "${user}:${group}" "$(app_home)/.dbtools"
  log "SQLcl saved connection agent_workbench を作成しました。"
}

main "$@"
