#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=/dev/null
source /usr/local/sbin/no1-agent-workbench/common.sh

log_disk_status() {
  local phase=$1
  log "ディスク状態（${phase}）:"
  lsblk
  findmnt /
  df -hT /
}

main() {
  local filesystem_type
  local instance_boot_volume_size
  local root_size_bytes
  local minimum_size_bytes

  instance_boot_volume_size="$(read_config instance_boot_volume_size)"
  [[ "${instance_boot_volume_size}" =~ ^[0-9]+$ ]] \
    || fail "instance_boot_volume_size が整数ではありません: ${instance_boot_volume_size}"

  log "ソフトウェアをダウンロードする前に boot volume の root filesystem を拡張します。"
  log_disk_status "oci-growfs 実行前"

  filesystem_type="$(findmnt -n -o FSTYPE /)"
  case "${filesystem_type}" in
    xfs|ext4)
      ;;
    *)
      fail "oci-growfs はこの stack では XFS または ext4 のみ許可します。検出値: ${filesystem_type}"
      ;;
  esac

  if [[ ! -x /usr/libexec/oci-growfs ]]; then
    log "oci-growfs が見つからないため oci-utils をインストールします。"
    retry_command 5 20 dnf -y install oci-utils \
      || fail "oci-utils をインストールできません。"
  fi

  [[ -x /usr/libexec/oci-growfs ]] \
    || fail "/usr/libexec/oci-growfs を実行できません。"
  /usr/libexec/oci-growfs -y \
    || fail "oci-growfs による root filesystem 拡張に失敗しました。"

  log_disk_status "oci-growfs 実行後"
  root_size_bytes="$(df -B1 --output=size / | tail -n 1 | tr -d '[:space:]')"
  [[ "${root_size_bytes}" =~ ^[0-9]+$ ]] \
    || fail "root filesystem の容量を取得できません。"

  minimum_size_bytes=$((instance_boot_volume_size * 1024 * 1024 * 1024 * 90 / 100))
  ((root_size_bytes >= minimum_size_bytes)) \
    || fail "root filesystem ${root_size_bytes} bytes が ${instance_boot_volume_size}GB の 90% を下回っています。"

  log "root filesystem の拡張を確認しました: ${root_size_bytes} bytes"
}

main "$@"
