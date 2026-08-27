#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=/dev/null
source /usr/local/sbin/no1-agent-workbench/common.sh

codex_platform_suffix() {
  case "$(uname -m)" in
    x86_64)
      printf '%s\n' "linux-x64"
      ;;
    aarch64|arm64)
      printf '%s\n' "linux-arm64"
      ;;
    *)
      fail "Codex CLI の npm optional dependency に未対応の CPU architecture です: $(uname -m)"
      ;;
  esac
}

codex_platform_package_name() {
  printf 'codex-%s\n' "$(codex_platform_suffix)"
}

codex_vendor_dir() {
  local home=$1
  printf '%s/.npm-global/lib/node_modules/@openai/codex/node_modules/@openai/%s/vendor\n' \
    "${home}" "$(codex_platform_package_name)"
}

codex_tarball_available() {
  local version=$1
  local suffix=$2
  local url
  local code

  url="$(run_as_opc npm view "@openai/codex@${version}-${suffix}" dist.tarball 2>/dev/null || true)"
  if [[ -z "${url}" ]]; then
    log "  ${version} -> no metadata"
    return 1
  fi

  code="$(curl -sL -o /dev/null -w "%{http_code}" "${url}" || true)"
  log "  ${version} -> ${code}"
  [[ "${code}" == "200" ]]
}

resolve_codex_version() {
  local requested=$1
  local suffix=$2
  local versions
  local version

  if [[ -n "${requested}" && "${requested}" != "latest" ]]; then
    printf '%s\n' "${requested}"
    return 0
  fi

  log "Codex CLI の latest usable stable version を npm metadata から探索します。"
  versions="$(run_as_opc npm view @openai/codex versions --json \
    | jq -r '.[]' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
    | tail -15 \
    | tac)"
  [[ -n "${versions}" ]] \
    || fail "@openai/codex の stable version list を取得できません。"

  while IFS= read -r version; do
    [[ -n "${version}" ]] || continue
    if codex_tarball_available "${version}" "${suffix}"; then
      printf '%s\n' "${version}"
      return 0
    fi
  done <<< "${versions}"

  fail "直近 15 件の @openai/codex stable release に linux platform tarball が見つかりません。"
}

install_codex_package() {
  local resolved_version=$1

  run_as_opc npm install -g "@openai/codex@${resolved_version}" \
    --include=optional \
    --no-audit \
    --no-fund \
    || fail "Codex CLI の npm install に失敗しました。"
}

main() {
  local version
  local resolved_version
  local suffix
  local vendor_dir
  local home
  local openai_api_key
  local user group path

  version="$(read_config codex_cli_version)"
  home="$(app_home)"
  user="$(app_user)"
  group="$(app_group)"
  path="$(opc_path)"
  suffix="$(codex_platform_suffix)"
  vendor_dir="$(codex_vendor_dir "${home}")"

  ensure_opc_owned_dir "${home}/.npm-global" 0755
  ensure_opc_owned_dir "${home}/.npm" 0755
  ensure_opc_owned_dir "${home}/.cache" 0755
  ensure_opc_owned_dir "${home}/.codex" 0700

  run_as_opc npm config set prefix "${home}/.npm-global"
  run_as_opc npm config set cache "${home}/.npm"
  run_as_opc npm config delete omit >/dev/null 2>&1 || true
  run_as_opc npm config set include optional

  resolved_version="$(resolve_codex_version "${version}" "${suffix}")"
  log "Codex CLI を opc の npm prefix にインストールします: @openai/codex@${resolved_version}"
  rm -rf "${home}/.npm-global/lib/node_modules/@openai/codex" "${home}/.npm-global/bin/codex"
  install_codex_package "${resolved_version}"

  [[ -d "${vendor_dir}" ]] \
    || fail "Codex CLI platform vendor directory がありません: ${vendor_dir}"
  run_as_opc codex --version >/dev/null \
    || fail "opc ユーザーで codex を実行できません。npm optional dependency の設定を確認してください。"
  printf '%s\n' "${resolved_version}" > "${STATE_DIR}/codex-version.txt"
  chmod 0600 "${STATE_DIR}/codex-version.txt"
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
