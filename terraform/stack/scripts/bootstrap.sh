#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=/dev/null
source /usr/local/sbin/no1-agent-workbench/common.sh

umask 027
exec > >(tee -a "${LOG_FILE}") 2>&1

readonly COMPLETE_MARKER="${STATE_DIR}/bootstrap-complete"

on_error() {
  local exit_code=$?
  log "bootstrap が ${BASH_LINENO[0]} 行目で失敗しました。終了コード: ${exit_code}"
  systemctl status no1-agent-workbench-bootstrap.service --no-pager || true
  exit "${exit_code}"
}
trap on_error ERR

ensure_layout() {
  local home
  local app_root
  local wallet_dir
  local workspace_dir

  log "root/opc の所有境界に従ってディレクトリを作成します。"
  id "$(app_user)" >/dev/null 2>&1 || fail "opc ユーザーが見つかりません。Oracle Linux 9 platform image を使用してください。"

  install -d -m 0700 -o root -g root /etc/no1-agent-workbench
  install -d -m 0700 -o root -g root "${STATE_DIR}"

  home="$(app_home)"
  app_root="$(read_config app_root)"
  wallet_dir="$(read_config wallet_dir)"
  workspace_dir="$(read_config workspace_dir)"

  ensure_opc_owned_dir "${home}/.npm-global" 0755
  ensure_opc_owned_dir "${home}/.npm" 0755
  ensure_opc_owned_dir "${home}/.cache" 0755
  ensure_opc_owned_dir "${home}/.local" 0755
  ensure_opc_owned_dir "${home}/.codex" 0700
  ensure_opc_owned_dir "${home}/.dbtools" 0700
  ensure_opc_owned_dir "${app_root}" 0755
  ensure_opc_owned_dir "${wallet_dir}" 0700
  ensure_opc_owned_dir "${workspace_dir}" 0755
}

install_base_packages() {
  log "Oracle Linux 9 の基本パッケージをインストールします。"
  retry_command 5 20 dnf -y install dnf-plugins-core oracle-epel-release-el9 \
    || fail "Oracle Linux 9 EPEL repository package をインストールできません。"
  dnf config-manager --set-enabled ol9_developer_EPEL \
    || dnf config-manager --set-enable ol9_developer_EPEL \
    || fail "ol9_developer_EPEL repository を有効化できません。"

  retry_command 5 20 dnf -y install \
    bat \
    ca-certificates \
    coreutils \
    curl \
    direnv \
    findutils \
    gcc \
    gcc-c++ \
    git \
    gzip \
    java-21-openjdk-headless \
    jq \
    make \
    oci-utils \
    procps-ng \
    ripgrep \
    shadow-utils \
    tar \
    tmux \
    unzip \
    util-linux \
    which \
    xz \
    zip \
    || fail "基本パッケージをインストールできません。"
}

write_profile() {
  local java_home
  local wallet_dir
  local app_root

  java_home="$(detect_java_home)"
  wallet_dir="$(read_config wallet_dir)"
  app_root="$(read_config app_root)"

  log "/etc/profile.d/no1-agent-workbench.sh を作成します。"
  cat > /etc/profile.d/no1-agent-workbench.sh <<EOF
# no.1-agent-workbench runtime environment
export PATH="/home/opc/.npm-global/bin:/home/opc/.local/bin:/usr/local/bin:\$PATH"
export JAVA_HOME="${java_home}"
export TNS_ADMIN="${wallet_dir}"
export SQLCL_WORKBENCH_CONNECTION="agent_workbench"
export NO1_AGENT_WORKBENCH_ROOT="${app_root}"
EOF
  chmod 0644 /etc/profile.d/no1-agent-workbench.sh
}

main() {
  log "no.1-agent-workbench bootstrap を開始します。"
  ensure_layout

  /usr/local/sbin/no1-agent-workbench/grow_boot_volume.sh
  install_base_packages
  write_profile
  /usr/local/sbin/no1-agent-workbench/install_nodejs.sh
  /usr/local/sbin/no1-agent-workbench/install_uv.sh
  /usr/local/sbin/no1-agent-workbench/install_sqlcl.sh
  /usr/local/sbin/no1-agent-workbench/install_codex.sh
  /usr/local/sbin/no1-agent-workbench/setup_wallet.sh
  /usr/local/sbin/no1-agent-workbench/setup_codex_mcp.sh
  /usr/local/sbin/no1-agent-workbench/verify_workbench.sh

  touch "${COMPLETE_MARKER}"
  chmod 0600 "${COMPLETE_MARKER}"
  log "no.1-agent-workbench bootstrap が完了しました。"
}

main "$@"
