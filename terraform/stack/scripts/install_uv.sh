#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=/dev/null
source /usr/local/sbin/no1-agent-workbench/common.sh

main() {
  local uv_version
  local installer="${STATE_DIR}/uv-install.sh"

  uv_version="$(read_config uv_version)"
  log "uv を /usr/local/bin にインストールします。"

  retry_command 5 20 curl -fsSL https://astral.sh/uv/install.sh -o "${installer}" \
    || fail "uv installer をダウンロードできません。"
  chmod 0700 "${installer}"

  if [[ -n "${uv_version}" ]]; then
    env UV_INSTALL_DIR=/usr/local/bin UV_VERSION="${uv_version}" sh "${installer}" \
      || fail "uv ${uv_version} のインストールに失敗しました。"
  else
    env UV_INSTALL_DIR=/usr/local/bin sh "${installer}" \
      || fail "uv のインストールに失敗しました。"
  fi

  chmod 0755 /usr/local/bin/uv /usr/local/bin/uvx
  uv --version >/dev/null || fail "uv の実行検証に失敗しました。"
  uvx --version >/dev/null || fail "uvx の実行検証に失敗しました。"
  log "$(uv --version) をインストールしました。"
}

main "$@"
