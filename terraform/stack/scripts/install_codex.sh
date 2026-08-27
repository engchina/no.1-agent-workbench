#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=/dev/null
source /usr/local/sbin/no1-agent-workbench/common.sh

main() {
  local version
  local package
  local home
  local openai_api_key
  local user group path

  version="$(read_config codex_cli_version)"
  if [[ -z "${version}" || "${version}" == "latest" ]]; then
    package="@openai/codex@latest"
  else
    package="@openai/codex@${version}"
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
  run_as_opc npm install -g "${package}" \
    || fail "Codex CLI の npm install に失敗しました。"

  run_as_opc codex --version >/dev/null \
    || fail "opc ユーザーで codex を実行できません。"
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
