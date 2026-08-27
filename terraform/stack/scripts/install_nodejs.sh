#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=/dev/null
source /usr/local/sbin/no1-agent-workbench/common.sh

main() {
  local base_url
  local platform
  local tarball_name
  local work_dir
  local install_dir="/usr/local/lib/nodejs/node-v24"

  base_url="$(read_config nodejs_release_base_url)"
  base_url="${base_url%/}"

  case "$(uname -m)" in
    x86_64)
      platform="x64"
      ;;
    aarch64|arm64)
      platform="arm64"
      ;;
    *)
      fail "未対応の CPU architecture です: $(uname -m)"
      ;;
  esac

  if command -v node >/dev/null 2>&1 && node -v | grep -Eq '^v24\.'; then
    log "Node.js 24 は既に利用できます: $(node -v)"
    return 0
  fi

  log "Node.js 24 を公式 tarball と SHASUMS256.txt 検証でインストールします。"
  work_dir="$(mktemp -d)"
  trap 'rm -rf "${work_dir}"' EXIT

  retry_command 5 20 curl -fsSL "${base_url}/SHASUMS256.txt" -o "${work_dir}/SHASUMS256.txt" \
    || fail "Node.js SHASUMS256.txt をダウンロードできません。"

  tarball_name="$(awk -v platform="${platform}" '$2 ~ "^node-v24\\..*-linux-" platform "\\.tar\\.gz$" {print $2; exit}' "${work_dir}/SHASUMS256.txt")"
  [[ -n "${tarball_name}" ]] \
    || fail "Node.js 24 linux-${platform} tar.gz を SHASUMS256.txt から見つけられません。"

  retry_command 5 20 curl -fL "${base_url}/${tarball_name}" -o "${work_dir}/${tarball_name}" \
    || fail "Node.js tarball をダウンロードできません: ${tarball_name}"

  (cd "${work_dir}" && grep " ${tarball_name}$" SHASUMS256.txt | sha256sum -c -) \
    || fail "Node.js tarball の SHA256 検証に失敗しました。"

  rm -rf "${install_dir}"
  install -d -m 0755 /usr/local/lib/nodejs "${install_dir}"
  tar -xzf "${work_dir}/${tarball_name}" -C "${install_dir}" --strip-components=1
  ln -sfn "${install_dir}/bin/node" /usr/local/bin/node
  ln -sfn "${install_dir}/bin/npm" /usr/local/bin/npm
  ln -sfn "${install_dir}/bin/npx" /usr/local/bin/npx

  node -v | grep -Eq '^v24\.' || fail "Node.js 24 のインストール検証に失敗しました。"
  npm -v >/dev/null || fail "npm のインストール検証に失敗しました。"
  log "Node.js $(node -v) と npm $(npm -v) をインストールしました。"
}

main "$@"
