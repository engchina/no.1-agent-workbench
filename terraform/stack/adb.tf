resource "oci_database_autonomous_database" "workbench" {
  count = local.create_new_adb ? 1 : 0

  admin_password                                 = var.adb_password
  autonomous_maintenance_schedule_type           = "REGULAR"
  backup_retention_period_in_days                = var.adb_backup_retention_period_in_days
  character_set                                  = "AL32UTF8"
  compartment_id                                 = var.compartment_ocid
  compute_count                                  = var.adb_compute_count
  compute_model                                  = var.adb_compute_model
  data_storage_size_in_tbs                       = var.adb_data_storage_size_in_tbs
  db_name                                        = var.adb_name
  db_version                                     = var.adb_db_version
  db_workload                                    = var.adb_workload
  display_name                                   = local.adb_display_name
  is_auto_scaling_enabled                        = var.adb_is_auto_scaling_enabled
  is_auto_scaling_for_storage_enabled            = var.adb_is_auto_scaling_for_storage_enabled
  is_dedicated                                   = false
  is_mtls_connection_required                    = var.adb_is_mtls_connection_required
  is_preview_version_with_service_terms_accepted = false
  license_model                                  = var.license_model
  ncharacter_set                                 = "AL16UTF16"
  subnet_id                                      = local.adb_private_endpoint_enabled ? var.adb_subnet_id : null
  whitelisted_ips                                = local.adb_secure_acl_enabled ? local.adb_whitelisted_ips : null

  dynamic "resource_pool_summary" {
    for_each = var.adb_is_elastic_pool_enabled ? [1] : []

    content {
      pool_size                = var.adb_resource_pool_size
      pool_storage_size_in_tbs = var.adb_resource_pool_storage_size_in_tbs
    }
  }
}

resource "oci_database_autonomous_database_wallet" "workbench" {
  autonomous_database_id = local.effective_adb_ocid
  base64_encode_content  = true
  generate_type          = "SINGLE"
  password               = local.effective_oracle_wallet_password

  lifecycle {
    precondition {
      condition     = trimspace(local.effective_adb_ocid) != ""
      error_message = "ADB wallet を生成するために Autonomous Database OCID が必要です。"
    }
    precondition {
      condition     = trimspace(nonsensitive(local.effective_oracle_wallet_password)) != ""
      error_message = "ADB wallet を生成するために wallet password が必要です。"
    }
  }
}

resource "local_sensitive_file" "wallet_zip" {
  content_base64    = oci_database_autonomous_database_wallet.workbench.content
  file_permission   = "0600"
  filename          = "${path.module}/wallet_full.zip"
}

data "external" "wallet_files" {
  depends_on = [local_sensitive_file.wallet_zip]
  program    = ["bash", "${path.module}/extract_wallet.sh"]
}
