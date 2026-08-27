locals {
  supported_regions = ["ap-tokyo-1", "ap-osaka-1"]

  subnet_region         = lower(try(regex("^ocid1\\.subnet\\.oc1\\.([A-Za-z0-9-]+)\\.", var.subnet_id)[0], var.region))
  vcn_region            = lower(try(regex("^ocid1\\.vcn\\.oc1\\.([A-Za-z0-9-]+)\\.", var.vcn_id)[0], local.subnet_region))
  instance_image_region = lower(try(regex("^ocid1\\.image\\.oc1\\.([A-Za-z0-9-]+)\\.", trimspace(var.instance_image_ocid))[0], ""))
  existing_adb_region   = lower(try(regex("^ocid1\\.autonomousdatabase\\.oc1\\.([A-Za-z0-9-]+)\\.", trimspace(var.existing_adb_ocid))[0], local.subnet_region))
  selected_region       = local.subnet_region

  compute_subnet_prohibits_public_ip = coalesce(
    data.oci_core_subnet.selected_subnet.prohibit_public_ip_on_vnic,
    false,
  )

  oracle_linux_9_images = [
    for image in data.oci_core_images.oracle_linux_9.images : image
    if length(regexall("^Oracle-Linux-9\\.[0-9]+-", image.display_name)) > 0
    && length(regexall("-OKE-", image.display_name)) == 0
    && length(regexall("-GPU-", image.display_name)) == 0
    && length(regexall("-Minimal-", image.display_name)) == 0
  ]

  latest_oracle_linux_image_id   = try(local.oracle_linux_9_images[0].id, "")
  latest_oracle_linux_image_name = try(local.oracle_linux_9_images[0].display_name, "unavailable")
  instance_image_id              = trimspace(var.instance_image_ocid) != "" ? trimspace(var.instance_image_ocid) : local.latest_oracle_linux_image_id
  instance_image_name            = trimspace(var.instance_image_ocid) != "" ? "custom Oracle Linux 9 image OCID override" : local.latest_oracle_linux_image_name

  adb_deployment_mode_normalized = trimspace(var.adb_deployment_mode)
  adb_deployment_mode_create_values = [
    "CREATE_NEW",
    "新規 Autonomous Database の作成",
    "新規 Autonomous AI Database の作成"
  ]
  adb_deployment_mode_existing_values = [
    "USE_EXISTING",
    "既存の Autonomous Database を選択",
    "既存の Autonomous AI Database を選択"
  ]
  create_new_adb   = contains(local.adb_deployment_mode_create_values, local.adb_deployment_mode_normalized)
  use_existing_adb = contains(local.adb_deployment_mode_existing_values, local.adb_deployment_mode_normalized)

  adb_display_name = trimspace(var.adb_display_name) != "" ? var.adb_display_name : var.adb_name
  adb_private_endpoint_enabled = (
    local.create_new_adb
    && (var.adb_network_access_type == "PRIVATE_ENDPOINT_ONLY" || var.adb_use_private_subnet)
  )
  adb_secure_acl_enabled = local.create_new_adb && var.adb_network_access_type == "SECURE_ACCESS_FROM_ALLOWED_IPS_AND_VCNS"

  effective_adb_acl_vcn_id = trimspace(var.adb_acl_vcn_id) != "" ? trimspace(var.adb_acl_vcn_id) : trimspace(var.vcn_id)
  effective_adb_acl_subnet_id = (
    trimspace(var.adb_acl_subnet_id) != "" ? trimspace(var.adb_acl_subnet_id) : trimspace(var.subnet_id)
  )

  adb_acl_cidr_entries = local.adb_secure_acl_enabled && var.adb_acl_notation_type == "CIDR_BLOCK" && trimspace(var.adb_acl_cidr_blocks) != "" ? [
    for cidr in split(",", var.adb_acl_cidr_blocks) : trimspace(cidr)
    if trimspace(cidr) != ""
  ] : []

  adb_acl_vcn_entries = local.adb_secure_acl_enabled && var.adb_acl_notation_type == "VCN" && trimspace(local.effective_adb_acl_vcn_id) != "" ? [
    trimspace(local.effective_adb_acl_subnet_id) != "" ? "${local.effective_adb_acl_vcn_id};${data.oci_core_subnet.adb_acl_subnet[0].cidr_block}" : local.effective_adb_acl_vcn_id
  ] : []

  adb_whitelisted_ips = local.adb_secure_acl_enabled ? concat(local.adb_acl_vcn_entries, local.adb_acl_cidr_entries) : null

  existing_adb_db_name  = try(data.oci_database_autonomous_database.selected_existing_adb[0].db_name, "")
  existing_adb_workload = try(data.oci_database_autonomous_database.selected_existing_adb[0].db_workload, "")
  effective_adb_name    = local.create_new_adb ? var.adb_name : local.existing_adb_db_name
  effective_adb_workload = local.create_new_adb ? var.adb_workload : (
    trimspace(local.existing_adb_workload) != "" ? local.existing_adb_workload : var.adb_workload
  )
  effective_adb_ocid        = local.create_new_adb ? oci_database_autonomous_database.workbench[0].id : var.existing_adb_ocid
  effective_oracle_user     = local.create_new_adb ? "ADMIN" : var.existing_oracle_user
  effective_oracle_password = local.create_new_adb ? var.adb_password : var.existing_oracle_password
  effective_oracle_wallet_password = local.create_new_adb ? var.adb_password : (
    trimspace(nonsensitive(var.existing_oracle_wallet_password)) != "" ? var.existing_oracle_wallet_password : var.existing_oracle_password
  )

  service_suffix                = upper(local.effective_adb_workload) == "OLTP" ? "tp" : "medium"
  generated_oracle_dsn          = trimspace(local.effective_adb_name) != "" ? "${lower(local.effective_adb_name)}_${local.service_suffix}" : ""
  effective_existing_oracle_dsn = trimspace(var.existing_oracle_dsn) != "" ? trimspace(var.existing_oracle_dsn) : local.generated_oracle_dsn
  effective_oracle_dsn          = local.create_new_adb ? local.generated_oracle_dsn : local.effective_existing_oracle_dsn

  app_root      = "/u01/agent-workbench"
  wallet_dir    = "${local.app_root}/wallet"
  workspace_dir = "${local.app_root}/workspace"

  bootstrap_config = jsonencode({
    app_root                  = local.app_root
    app_user                  = "opc"
    workspace_dir             = local.workspace_dir
    wallet_dir                = local.wallet_dir
    instance_boot_volume_size = var.instance_boot_volume_size

    oracle_dsn      = local.effective_oracle_dsn
    oracle_password = local.effective_oracle_password
    oracle_user     = local.effective_oracle_user

    codex_cli_version       = var.codex_cli_version
    nodejs_release_base_url = var.nodejs_release_base_url
    openai_api_key          = var.openai_api_key
    sqlcl_download_url      = var.sqlcl_download_url
    uv_version              = var.uv_version
  })

  cloud_init = templatefile("${path.module}/cloud_init/bootstrap.template.yaml", {
    bootstrap_config        = base64encode(local.bootstrap_config)
    bootstrap_script        = base64gzip(file("${path.module}/scripts/bootstrap.sh"))
    common_script           = base64gzip(file("${path.module}/scripts/common.sh"))
    grow_boot_volume_script = base64gzip(file("${path.module}/scripts/grow_boot_volume.sh"))
    install_codex_script    = base64gzip(file("${path.module}/scripts/install_codex.sh"))
    install_nodejs_script   = base64gzip(file("${path.module}/scripts/install_nodejs.sh"))
    install_sqlcl_script    = base64gzip(file("${path.module}/scripts/install_sqlcl.sh"))
    install_uv_script       = base64gzip(file("${path.module}/scripts/install_uv.sh"))
    setup_codex_mcp_script  = base64gzip(file("${path.module}/scripts/setup_codex_mcp.sh"))
    setup_wallet_script     = base64gzip(file("${path.module}/scripts/setup_wallet.sh"))
    verify_workbench_script = base64gzip(file("${path.module}/scripts/verify_workbench.sh"))
    wallet_content          = data.external.wallet_files.result.wallet_content
  })

  cloud_init_user_data = base64gzip(local.cloud_init)
}

resource "terraform_data" "bootstrap_revision" {
  triggers_replace = [
    sha256(nonsensitive(local.bootstrap_config)),
    filesha256("${path.module}/cloud_init/bootstrap.template.yaml"),
    filesha256("${path.module}/scripts/common.sh"),
    filesha256("${path.module}/scripts/bootstrap.sh"),
    filesha256("${path.module}/scripts/grow_boot_volume.sh"),
    filesha256("${path.module}/scripts/install_nodejs.sh"),
    filesha256("${path.module}/scripts/install_uv.sh"),
    filesha256("${path.module}/scripts/install_sqlcl.sh"),
    filesha256("${path.module}/scripts/install_codex.sh"),
    filesha256("${path.module}/scripts/setup_wallet.sh"),
    filesha256("${path.module}/scripts/setup_codex_mcp.sh"),
    filesha256("${path.module}/scripts/verify_workbench.sh"),
  ]
}
