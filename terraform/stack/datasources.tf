data "oci_core_subnet" "selected_subnet" {
  subnet_id = var.subnet_id
}

data "oci_core_images" "oracle_linux_9" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Oracle Linux"
  operating_system_version = "9"
  shape                    = var.instance_shape
  state                    = "AVAILABLE"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

data "oci_core_subnet" "adb_acl_subnet" {
  count = (
    local.create_new_adb
    && var.adb_network_access_type == "SECURE_ACCESS_FROM_ALLOWED_IPS_AND_VCNS"
    && var.adb_acl_notation_type == "VCN"
    && trimspace(local.effective_adb_acl_subnet_id) != ""
  ) ? 1 : 0

  subnet_id = local.effective_adb_acl_subnet_id
}

data "oci_database_autonomous_database" "selected_existing_adb" {
  count = local.use_existing_adb && trimspace(var.existing_adb_ocid) != "" ? 1 : 0

  autonomous_database_id = var.existing_adb_ocid
}

data "oci_core_vnic_attachments" "workbench" {
  compartment_id = var.compartment_ocid
  instance_id    = oci_core_instance.workbench.id
}

data "oci_core_vnic" "workbench_primary" {
  vnic_id = data.oci_core_vnic_attachments.workbench.vnic_attachments[0].vnic_id
}
