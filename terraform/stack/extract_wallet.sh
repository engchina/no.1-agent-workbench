#!/usr/bin/env bash
# Terraform external data source 用の ADB wallet 縮小スクリプトです。
# stdout には JSON だけを出力します。

set -Eeuo pipefail

WORK_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${WORK_DIR}"

cleanup() {
  rm -rf wallet_extracted wallet_selected wallet_small.zip wallet_full.zip >/dev/null 2>&1 || true
}
trap cleanup EXIT

fail() {
  printf 'extract_wallet.sh: %s\n' "$*" >&2
  exit 1
}

[[ -s wallet_full.zip ]] || fail "wallet_full.zip がありません。"

rm -rf wallet_extracted wallet_selected wallet_small.zip >/dev/null 2>&1 || true
mkdir -p wallet_extracted wallet_selected
unzip -q -o wallet_full.zip -d wallet_extracted >/dev/null 2>&1 \
  || fail "wallet_full.zip を展開できません。"

KEEP_FILES=(
  cwallet.sso
  ewallet.pem
  tnsnames.ora
  sqlnet.ora
  ojdbc.properties
)

for file in "${KEEP_FILES[@]}"; do
  if [[ -f "wallet_extracted/${file}" ]]; then
    cp "wallet_extracted/${file}" "wallet_selected/${file}"
  fi
done

[[ -f wallet_selected/cwallet.sso ]] || fail "cwallet.sso が wallet にありません。"
[[ -f wallet_selected/tnsnames.ora ]] || fail "tnsnames.ora が wallet にありません。"

(
  cd wallet_selected
  zip -q ../wallet_small.zip *
) >/dev/null 2>&1 || fail "縮小 wallet ZIP を作成できません。"

WALLET_CONTENT="$(base64 -w 0 wallet_small.zip 2>/dev/null | tr -d '\r\n')"
[[ -n "${WALLET_CONTENT}" ]] || fail "縮小 wallet ZIP を base64 encode できません。"

printf '{"wallet_content":"%s"}\n' "${WALLET_CONTENT}"
