#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=/dev/null
source /usr/local/sbin/no1-agent-workbench/common.sh

codex_platform_package() {
  case "$(uname -m)" in
    x86_64)
      printf '%s\n' "@openai/codex-linux-x64"
      ;;
    aarch64|arm64)
      printf '%s\n' "@openai/codex-linux-arm64"
      ;;
    *)
      fail "Codex CLI の npm optional dependency に未対応の CPU architecture です: $(uname -m)"
      ;;
  esac
}

install_codex_packages() {
  local package=$1
  local platform_package=$2

  run_as_opc npm install -g --include=optional "${package}" "${platform_package}" \
    || fail "Codex CLI の npm install に失敗しました。"
}

main() {
  local version
  local package
  local platform_package
  local home
  local openai_api_key
  local user group path

  version="$(read_config codex_cli_version)"
  if [[ -z "${version}" || "${version}" == "latest" ]]; then
    package="@openai/codex@latest"
    platform_package="$(codex_platform_package)@latest"
  else
    package="@openai/codex@${version}"
    platform_package="$(codex_platform_package)@${version}"
  fi

  home="$(app_home)"
  user="$(app_user)"
  group="$(app_group)"
  path="$(opc_path)"
  ensure_opc_owned_dir "${home}/.npm-global" 0755
  ensure_opc_owned_dir "${home}/.npm" 0755
  ensure_opc_owned_dir "${home}/.cache" 0755
  ensure_opc_owned_dir "${home}/.codex" 0700

  log "Codex CLI を opc の npm prefix にインストールします: ${package}"
  run_as_opc npm config set prefix "${home}/.npm-global"
  run_as_opc npm config set cache "${home}/.npm"
  run_as_opc npm config delete omit >/dev/null 2>&1 || true
  run_as_opc npm config set include optional
  install_codex_packages "${package}" "${platform_package}"

  if ! run_as_opc codex --version >/dev/null 2>&1; then
    log "Codex CLI の platform optional dependency を明示的に再インストールします: ${platform_package}"
    install_codex_packages "${package}" "${platform_package}"
  fi
  run_as_opc codex --version >/dev/null \
    || fail "opc ユーザーで codex を実行できません。npm optional dependency の設定を確認してください。"
  chown -R "${user}:${group}" "${home}/.npm-global" "${home}/.npm" "${home}/.cache" "${home}/.codex"

  openai_api_key="$(read_config openai_api_key)"
  if [[ -n "${openai_api_key}" ]]; then
    log "openai_api_key が指定されたため、opc として Codex API key login を実行します。"
    printf '%s\n' "${openai_api_key}" | runuser -u "${user}" -- env \
      "HOME=${home}" \
      "USER=${user}" \
      "LOGNAME=${user}" \
      "PATH=${path}" \
      codex login --with-api-key \
      || fail "Codex API key login に失敗しました。"
    chown -R "${user}:${group}" "${home}/.codex"
  else
    log "openai_api_key は未指定です。SSH 後に opc で codex login --device-auth を実行してください。"
  fi
}

main "$@"
