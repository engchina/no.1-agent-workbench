resource "oci_core_instance" "workbench" {
  depends_on = [
    data.external.wallet_files,
  ]

  availability_config {
    is_live_migration_preferred = false
    recovery_action             = "RESTORE_INSTANCE"
  }

  availability_domain = var.availability_domain
  compartment_id      = var.compartment_ocid
  display_name        = var.instance_display_name
  shape               = var.instance_shape

  create_vnic_details {
    assign_ipv6ip             = false
    assign_private_dns_record = true
    assign_public_ip          = var.assign_public_ip
    subnet_id                 = var.subnet_id
  }

  instance_options {
    are_legacy_imds_endpoints_disabled = true
  }

  metadata = {
    ssh_authorized_keys = var.ssh_authorized_keys
    user_data           = local.cloud_init_user_data
  }

  platform_config {
    is_symmetric_multi_threading_enabled = true
    type                                 = "AMD_VM"
  }

  shape_config {
    baseline_ocpu_utilization = "BASELINE_1_1"
    memory_in_gbs             = var.instance_flex_shape_memory
    ocpus                     = var.instance_flex_shape_ocpus
  }

  source_details {
    boot_volume_size_in_gbs = var.instance_boot_volume_size
    boot_volume_vpus_per_gb = var.instance_boot_volume_vpus
    source_id               = local.instance_image_id
    source_type             = "image"
  }

  freeform_tags = {
    project = "no.1-agent-workbench"
    role    = "agent-workbench"
  }

  lifecycle {
    replace_triggered_by = [
      terraform_data.bootstrap_revision,
    ]

    precondition {
      condition     = contains(local.supported_regions, local.selected_region)
      error_message = "この stack は東京(ap-tokyo-1)と大阪(ap-osaka-1)のみ対応します。subnet_id のリージョンを確認してください。"
    }
    precondition {
      condition     = trimspace(var.compartment_ocid) != ""
      error_message = "compartment_ocid を指定してください。"
    }
    precondition {
      condition     = trimspace(var.vcn_id) != "" && trimspace(var.subnet_id) != ""
      error_message = "vcn_id と subnet_id を指定してください。"
    }
    precondition {
      condition     = trimspace(var.ssh_authorized_keys) != ""
      error_message = "SSH 接続に使う公開鍵を ssh_authorized_keys に指定してください。"
    }
    precondition {
      condition     = local.vcn_region == local.selected_region
      error_message = "vcn_id と subnet_id は同じ OCI リージョンにしてください。"
    }
    precondition {
      condition     = length(regexall(upper(local.selected_region), upper(var.availability_domain))) > 0
      error_message = "availability_domain は選択した subnet のリージョンに属する値を指定してください。"
    }
    precondition {
      condition     = local.instance_image_id != ""
      error_message = "対象 shape/region の Oracle Linux 9 platform image を取得できません。instance_image_ocid で Oracle Linux 9 image を指定してください。"
    }
    precondition {
      condition     = trimspace(var.instance_image_ocid) == "" || local.instance_image_region == local.selected_region
      error_message = "instance_image_ocid は空欄、または選択した subnet のリージョンに属する Oracle Linux 9 image OCID を指定してください。"
    }
    precondition {
      condition     = !var.assign_public_ip || !local.compute_subnet_prohibits_public_ip
      error_message = "選択した subnet は public IP を禁止しています。assign_public_ip を false にしてください。"
    }
    precondition {
      condition     = local.create_new_adb ? trimspace(nonsensitive(var.adb_password)) != "" : true
      error_message = "新規 ADB を作成する場合は adb_password を指定してください。"
    }
    precondition {
      condition = (
        local.create_new_adb && local.adb_private_endpoint_enabled
      ) ? trimspace(var.adb_subnet_id) != "" : true
      error_message = "PRIVATE_ENDPOINT_ONLY を使う場合は adb_subnet_id を指定してください。"
    }
    precondition {
      condition = (
        local.create_new_adb
        && local.adb_secure_acl_enabled
        && var.adb_acl_notation_type == "VCN"
      ) ? trimspace(local.effective_adb_acl_vcn_id) != "" : true
      error_message = "ADB の VCN ACL を使う場合は adb_acl_vcn_id または vcn_id を指定してください。"
    }
    precondition {
      condition = (
        local.create_new_adb
        && local.adb_secure_acl_enabled
        && var.adb_acl_notation_type == "CIDR_BLOCK"
      ) ? length(local.adb_acl_cidr_entries) > 0 : true
      error_message = "ADB の CIDR ACL を使う場合は adb_acl_cidr_blocks を指定してください。"
    }
    precondition {
      condition = local.create_new_adb || (
        trimspace(var.existing_adb_ocid) != ""
        && trimspace(var.existing_oracle_user) != ""
        && trimspace(nonsensitive(var.existing_oracle_password)) != ""
      )
      error_message = "既存 ADB を使う場合は existing_adb_ocid, existing_oracle_user, existing_oracle_password を指定してください。"
    }
    precondition {
      condition     = local.create_new_adb || local.existing_adb_region == local.selected_region
      error_message = "existing_adb_ocid は選択した subnet と同じリージョンの ADB を指定してください。"
    }
    precondition {
      condition     = length(data.external.wallet_files.result.wallet_content) <= var.wallet_content_max_base64_length
      error_message = "縮小 wallet ZIP が metadata 注入の安全上限を超えています。wallet_content_max_base64_length を確認し、必要であれば wallet 注入方式を見直してください。"
    }
    precondition {
      condition     = length(nonsensitive(local.cloud_init_user_data)) <= 32000
      error_message = "cloud-init user_data が OCI metadata の安全上限を超えています。wallet をさらに縮小するか、secret 配布方式を見直してください。"
    }
  }
}
