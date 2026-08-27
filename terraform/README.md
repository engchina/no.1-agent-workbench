# Terraform stack

この directory は OCI Resource Manager にアップロードする Terraform stack です。通常は repository root で次を実行して ZIP を作成します。

```bash
python3 scripts/package_terraform_stack.py
```

生成物:

```text
dist/no.1-agent-workbench-terraform-stack.zip
```

## 重要な default

- 対応リージョン: `ap-tokyo-1`, `ap-osaka-1`
- Compute: `VM.Standard.E5.Flex`, `2 OCPU`, `24GB RAM`, `100GB boot volume`
- ADB workload: `LH`
- ADB default DSN: `OLTP` は `_tp`、それ以外は `_medium`
- Codex CLI: `@openai/codex@latest`
- Node.js: `https://nodejs.org/download/release/latest-v24.x`
- SQLcl: `https://download.oracle.com/otn_software/java/sqldeveloper/sqlcl-latest.zip`
- Wallet 注入上限: 縮小 ZIP base64 で 16KB

## bootstrap の流れ

1. `oci-utils` と `/usr/libexec/oci-growfs -y` で root filesystem を拡張します。
2. Java 21、git、curl、jq、unzip、zip、gcc/g++、make、tmux、ripgrep、bat、direnv をインストールします。
3. Node.js 24 を公式 tarball と `SHASUMS256.txt` 検証で `/usr/local/lib/nodejs` に配置します。
4. uv/uvx を `/usr/local/bin` に配置します。
5. SQLcl を `/opt/sqlcl` に展開し、`/usr/local/bin/sql` を作成します。
6. Codex CLI を `opc` の npm prefix `/home/opc/.npm-global` にインストールします。
7. ADB wallet を `/u01/agent-workbench/wallet` に `0700/0600` で展開します。
8. SQLcl saved connection `agent_workbench` を `opc` として作成します。
9. `/home/opc/.codex/config.toml` に SQLcl MCP Server を登録します。

## local validation

```bash
terraform fmt -check -recursive terraform/stack
terraform -chdir=terraform/stack init -backend=false
terraform -chdir=terraform/stack validate
python3 -m unittest discover -s tests
```

この実行環境に Terraform が無い場合でも、`python3 -m unittest discover -s tests` で schema/default/permission/package の静的検証は実行できます。
