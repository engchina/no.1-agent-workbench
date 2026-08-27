output "selected_region" {
  description = "subnet_id から推定した OCI リージョンです。"
  value       = local.selected_region
}

output "selected_oracle_linux_image" {
  description = "選択された Oracle Linux 9 image の表示名です。"
  value       = local.instance_image_name
}

output "selected_oracle_linux_image_ocid" {
  description = "選択された Oracle Linux 9 image OCID です。"
  value       = local.instance_image_id
}

output "instance_ocid" {
  description = "作成された Compute instance OCID です。"
  value       = oci_core_instance.workbench.id
}

output "private_ip" {
  description = "Compute instance の private IP address です。"
  value       = data.oci_core_vnic.workbench_primary.private_ip_address
}

output "public_ip" {
  description = "assign_public_ip=true の場合だけ Compute instance の public IP address を返します。"
  value       = var.assign_public_ip ? data.oci_core_vnic.workbench_primary.public_ip_address : null
}

output "ssh_command" {
  description = "opc ユーザーで SSH 接続するコマンドです。"
  value       = "ssh opc@${var.assign_public_ip ? data.oci_core_vnic.workbench_primary.public_ip_address : data.oci_core_vnic.workbench_primary.private_ip_address}"
}

output "autonomous_database_ocid" {
  description = "Workbench が使用する Autonomous Database OCID です。"
  value       = local.effective_adb_ocid
}

output "default_oracle_dsn" {
  description = "SQLcl saved connection と MCP が使う既定 DSN です。OLTP は _tp、それ以外は _medium です。"
  value       = local.effective_oracle_dsn
}

output "workspace_path" {
  description = "opc が所有する作業ディレクトリです。"
  value       = local.workspace_dir
}

output "wallet_dir" {
  description = "opc が読める ADB wallet directory です。"
  value       = local.wallet_dir
}

output "codex_mcp_config_path" {
  description = "SQLcl MCP server を登録する Codex config path です。"
  value       = "/home/opc/.codex/config.toml"
}

output "bootstrap_log_command" {
  description = "bootstrap log を確認する SSH コマンドです。"
  value       = "ssh opc@${var.assign_public_ip ? data.oci_core_vnic.workbench_primary.public_ip_address : data.oci_core_vnic.workbench_primary.private_ip_address} 'sudo tail -f /var/log/no1-agent-workbench-bootstrap.log'"
}

output "verification_command" {
  description = "インスタンス内で workbench の検証を再実行する SSH コマンドです。"
  value       = "ssh opc@${var.assign_public_ip ? data.oci_core_vnic.workbench_primary.public_ip_address : data.oci_core_vnic.workbench_primary.private_ip_address} 'sudo /usr/local/sbin/no1-agent-workbench/verify_workbench.sh'"
}
