# no.1-agent-workbench

Oracle Cloud Infrastructure 上に、AI coding agent 用の workbench を 1 クリックで作成する Terraform stack です。Oracle Linux 9 の Compute と Autonomous Database を構築し、初回起動で Node.js 24、Codex CLI、uv、SQLcl、SQLcl MCP Server、ADB wallet を `opc` ユーザーで使える状態にします。

## Deploy to OCI

下のボタンをクリックすると、東京リージョン (`ap-tokyo-1`) を既定値として OCI Resource Manager が開きます。大阪リージョンを既定値にしたい場合は [大阪で開く](https://cloud.oracle.com/resourcemanager/stacks/create?region=ap-osaka-1&zipUrl=https://github.com/engchina/no.1-agent-workbench/releases/latest/download/no.1-agent-workbench-terraform-stack.zip) を使用してください。

[![Deploy to Oracle Cloud](https://oci-resourcemanager-plugin.plugins.oci.oraclecloud.com/latest/deploy-to-oracle-cloud.svg)](https://cloud.oracle.com/resourcemanager/stacks/create?region=ap-tokyo-1&zipUrl=https://github.com/engchina/no.1-agent-workbench/releases/latest/download/no.1-agent-workbench-terraform-stack.zip)

このボタンは GitHub Release の最新 asset を使用します。

```text
no.1-agent-workbench-terraform-stack.zip
```

## 主な仕様

- 対応リージョン: 東京 `ap-tokyo-1`、大阪 `ap-osaka-1`
- OS: Oracle Linux 9 platform image を shape/region から自動選択
- Compute default: `VM.Standard.E5.Flex`, `2 OCPU`, `24GB RAM`, `100GB boot volume`
- ADB default: workload `LH`, database version `26ai`, default DSN `agentadb_medium`
- Node.js: 公式 `latest-v24.x` tarball + `SHASUMS256.txt` 検証
- Codex CLI: `opc` の npm prefix `/home/opc/.npm-global` に、Linux binary tarball が存在する最新安定版の `@openai/codex` をインストール
- SQLcl: `/opt/sqlcl` に配置し、`/usr/local/bin/sql` から実行
- MCP: `/home/opc/.codex/config.toml` に SQLcl MCP Server (`sql -mcp`) を登録
- boot volume: 初回起動の最初に `/usr/libexec/oci-growfs -y` で root filesystem を拡張

## 権限モデル

bootstrap は root で動きますが、agent が実際に使う状態は `opc:opc` で作成します。

- root 管理: `/usr/local/lib/nodejs`, `/usr/local/bin/node`, `/usr/local/bin/npm`, `/opt/sqlcl`, `/usr/local/bin/sql`, `/usr/local/bin/uv`, `/usr/local/bin/uvx`, systemd unit, `/etc/profile.d/no1-agent-workbench.sh`
- `opc` 管理: `/home/opc/.npm-global`, `/home/opc/.npm`, `/home/opc/.cache`, `/home/opc/.local`, `/home/opc/.codex`, `/home/opc/.dbtools`, `/u01/agent-workbench`
- wallet: `/u01/agent-workbench/wallet` は `0700 opc:opc`、wallet files は `0600`

SQLcl saved connection `agent_workbench` は必ず `opc` として作成します。root の `~/.dbtools` に保存されると Codex MCP から見えないためです。

## デプロイ後

Resource Manager output の `ssh_command` で接続します。public IP を付けない場合は Bastion や VPN など private IP に到達できる経路を使ってください。

```bash
tmux new -s codex
codex
```

`openai_api_key` を指定しなかった場合は、SSH 後に `opc` として認証してください。

```bash
codex login --device-auth
```

API key で認証する場合:

```bash
printenv OPENAI_API_KEY | codex login --with-api-key
```

bootstrap の状態確認:

```bash
sudo tail -f /var/log/no1-agent-workbench-bootstrap.log
sudo /usr/local/sbin/no1-agent-workbench/verify_workbench.sh
```

## Troubleshooting

`codex --version` で `Missing optional dependency @openai/codex-linux-x64` が出る場合は、npm が optional dependency を省略しているか、latest tag と Linux binary tarball の公開タイミングがずれています。`opc` として利用可能な直近の安定版を探して再インストールしてください。

```bash
sudo -u opc bash -lc '
set -euo pipefail
CODEX_VERSION=""
for v in $(npm view @openai/codex versions --json \
  | jq -r ".[]" \
  | grep -E "^[0-9]+\.[0-9]+\.[0-9]+$" \
  | tail -15 \
  | tac); do
  url=$(npm view "@openai/codex@${v}-linux-x64" dist.tarball 2>/dev/null) || continue
  [ -z "$url" ] && { echo "  $v -> no metadata"; continue; }
  code=$(curl -sL -o /dev/null -w "%{http_code}" "$url")
  echo "  $v -> $code"
  if [ "$code" = "200" ]; then CODEX_VERSION="$v"; break; fi
done
[ -n "$CODEX_VERSION" ] || { echo "no usable version found in last 15 releases"; exit 1; }

npm config set prefix "$HOME/.npm-global"
npm config delete omit >/dev/null 2>&1 || true
npm config set include optional
rm -rf "$HOME/.npm-global/lib/node_modules/@openai/codex" "$HOME/.npm-global/bin/codex"
npm install -g "@openai/codex@${CODEX_VERSION}" --include=optional --no-audit --no-fund
VENDOR="$HOME/.npm-global/lib/node_modules/@openai/codex/node_modules/@openai/codex-linux-x64/vendor"
[ -d "$VENDOR" ] || { echo "FAILED: vendor dir missing at $VENDOR"; exit 1; }
"$HOME/.npm-global/bin/codex" --version
echo ">>> pinned version: ${CODEX_VERSION}"
'
```

## セキュリティ注意

この stack は instance principal を使わず、Terraform が ADB wallet を生成して縮小 ZIP を cloud-init に注入します。そのため Resource Manager の state/job history には wallet や一部 secret が残ります。検証・PoC 用途を想定し、production で長期運用する場合は Object Storage PAR や別の secret 配布方式を検討してください。

wallet は `cwallet.sso`, `ewallet.pem`, `tnsnames.ora`, `sqlnet.ora`, `ojdbc.properties` だけを注入し、JKS と `ewallet.p12` は除外します。metadata サイズ保護のため、縮小 ZIP の base64 長が既定 16KB を超える場合は Terraform が停止します。

package 作成:

```bash
python3 scripts/package_terraform_stack.py
```
