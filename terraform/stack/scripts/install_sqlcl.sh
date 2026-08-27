#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=/dev/null
source /usr/local/sbin/no1-agent-workbench/common.sh

main() {
  local download_url
  local work_dir

  download_url="$(read_config sqlcl_download_url)"

  if command -v sql >/dev/null 2>&1 && sql -version >/dev/null 2>&1; then
    log "SQLcl は既に利用できます。"
    sql -version || true
    return 0
  fi

  log "SQLcl を /opt/sqlcl にインストールします。"
  work_dir="$(mktemp -d)"
  trap 'rm -rf "${work_dir}"' EXIT

  retry_command 5 20 curl -fL "${download_url}" -o "${work_dir}/sqlcl.zip" \
    || fail "SQLcl ZIP をダウンロードできません。"

  rm -rf /opt/sqlcl
  install -d -m 0755 /opt
  unzip -q "${work_dir}/sqlcl.zip" -d /opt
  [[ -x /opt/sqlcl/bin/sql ]] || fail "/opt/sqlcl/bin/sql が見つかりません。"
  ln -sfn /opt/sqlcl/bin/sql /usr/local/bin/sql
  chmod -R a+rX /opt/sqlcl

  JAVA_HOME="$(detect_java_home)" TNS_ADMIN="$(read_config wallet_dir)" sql -version >/dev/null \
    || fail "SQLcl の実行検証に失敗しました。"
  log "SQLcl をインストールしました。"
}

main "$@"
