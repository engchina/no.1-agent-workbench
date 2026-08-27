variable "region" {
  description = "Resource Manager 互換用のリージョン値です。実際の provider region は subnet_id から推定します。東京(ap-tokyo-1)と大阪(ap-osaka-1)のみ対応します。"
  type        = string
  default     = "ap-tokyo-1"

  validation {
    condition     = contains(["ap-tokyo-1", "ap-osaka-1"], var.region)
    error_message = "region は ap-tokyo-1 または ap-osaka-1 のみ指定できます。"
  }
}

variable "compartment_ocid" {
  description = "Compute と Autonomous Database を作成する compartment OCID です。"
  type        = string
  default     = ""

  validation {
    condition = (
      var.compartment_ocid == ""
      || can(regex("^ocid1\\.(compartment|tenancy)\\.", var.compartment_ocid))
    )
    error_message = "compartment_ocid には compartment または tenancy の OCID を指定してください。"
  }
}

variable "availability_domain" {
  description = "Compute instance を配置する availability domain です。"
  type        = string
  default     = ""

  validation {
    condition     = !can(regex("[\r\n]", var.availability_domain))
    error_message = "availability_domain に改行は使用できません。"
  }
}

variable "vcn_id" {
  description = "Compute と ADB ACL で使用する既存 VCN の OCID です。"
  type        = string
  default     = ""

  validation {
    condition     = var.vcn_id == "" || can(regex("^ocid1\\.vcn\\.", var.vcn_id))
    error_message = "vcn_id には VCN OCID を指定してください。"
  }
}

variable "subnet_id" {
  description = "Compute instance を配置する既存 subnet の OCID です。provider region はこの OCID から推定されます。"
  type        = string
  default     = ""

  validation {
    condition     = var.subnet_id == "" || can(regex("^ocid1\\.subnet\\.", var.subnet_id))
    error_message = "subnet_id には subnet OCID を指定してください。"
  }
}

variable "ssh_authorized_keys" {
  description = "opc ユーザーへ登録する SSH 公開鍵です。複数行を指定できます。"
  type        = string
  default     = ""
}

variable "assign_public_ip" {
  description = "Compute instance に public IP を割り当てる場合は true にします。既定は private IP のみです。"
  type        = bool
  default     = false
}

variable "instance_display_name" {
  description = "Compute instance の表示名です。"
  type        = string
  default     = "agent-workbench"

  validation {
    condition     = trimspace(var.instance_display_name) != "" && !can(regex("[\r\n]", var.instance_display_name))
    error_message = "instance_display_name は空文字や改行を含められません。"
  }
}

variable "instance_shape" {
  description = "Compute instance shape です。Oracle Linux 9 の platform image が取得できる Flex shape を想定します。"
  type        = string
  default     = "VM.Standard.E5.Flex"

  validation {
    condition     = contains(["VM.Standard.E4.Flex", "VM.Standard.E5.Flex"], var.instance_shape)
    error_message = "instance_shape は VM.Standard.E4.Flex または VM.Standard.E5.Flex を指定してください。"
  }
}

variable "instance_flex_shape_ocpus" {
  description = "Compute instance の OCPU 数です。"
  type        = number
  default     = 2

  validation {
    condition     = var.instance_flex_shape_ocpus > 0
    error_message = "instance_flex_shape_ocpus は 0 より大きい値にしてください。"
  }
}

variable "instance_flex_shape_memory" {
  description = "Compute instance のメモリ容量(GB)です。既定は 24GB です。"
  type        = number
  default     = 24

  validation {
    condition     = var.instance_flex_shape_memory >= 24
    error_message = "instance_flex_shape_memory は 24GB 以上にしてください。"
  }
}

variable "instance_boot_volume_size" {
  description = "Compute boot volume のサイズ(GB)です。初回起動時に root filesystem をこの容量まで拡張します。"
  type        = number
  default     = 100

  validation {
    condition     = var.instance_boot_volume_size >= 50 && var.instance_boot_volume_size <= 32768
    error_message = "instance_boot_volume_size は 50 から 32768 までの GB 値にしてください。"
  }
}

variable "instance_boot_volume_vpus" {
  description = "Compute boot volume の VPUs/GB です。"
  type        = number
  default     = 10

  validation {
    condition     = contains(concat([10, 20], range(30, 121)), var.instance_boot_volume_vpus)
    error_message = "instance_boot_volume_vpus は 10、20、または 30 から 120 の値にしてください。"
  }
}

variable "instance_image_ocid" {
  description = "Oracle Linux 9 image OCID を手動指定する場合に使用します。空欄の場合は対象 shape/region の最新 platform image を自動選択します。"
  type        = string
  default     = ""

  validation {
    condition     = var.instance_image_ocid == "" || can(regex("^ocid1\\.image\\.", var.instance_image_ocid))
    error_message = "instance_image_ocid には image OCID を指定してください。"
  }
}

variable "adb_deployment_mode" {
  description = "新規 Autonomous Database を作成するか、既存 Autonomous Database を使用するかを選択します。"
  type        = string
  default     = "新規 Autonomous AI Database の作成"

  validation {
    condition = contains([
      "CREATE_NEW",
      "USE_EXISTING",
      "新規 Autonomous Database の作成",
      "既存の Autonomous Database を選択",
      "新規 Autonomous AI Database の作成",
      "既存の Autonomous AI Database を選択"
    ], var.adb_deployment_mode)
    error_message = "adb_deployment_mode は新規作成または既存選択を指定してください。"
  }
}

variable "existing_adb_ocid" {
  description = "既存 Autonomous Database を使用する場合の ADB OCID です。"
  type        = string
  default     = ""

  validation {
    condition     = var.existing_adb_ocid == "" || can(regex("^ocid1\\.autonomousdatabase\\.", var.existing_adb_ocid))
    error_message = "existing_adb_ocid には Autonomous Database OCID を指定してください。"
  }
}

variable "existing_oracle_user" {
  description = "既存 ADB に接続する database user です。"
  type        = string
  default     = "ADMIN"

  validation {
    condition     = trimspace(var.existing_oracle_user) != "" && !can(regex("[/\r\n@\"]", var.existing_oracle_user))
    error_message = "existing_oracle_user は空欄不可です。/, @, ダブルクォート、改行は使用できません。"
  }
}

variable "existing_oracle_password" {
  description = "既存 ADB に接続する database password です。SQLcl saved connection のため /, @, ダブルクォート、改行は使用できません。"
  type        = string
  sensitive   = true
  default     = ""

  validation {
    condition = (
      var.existing_oracle_password == ""
      || (
        length(var.existing_oracle_password) <= 256
        && !can(regex("[/\r\n@\"]", var.existing_oracle_password))
      )
    )
    error_message = "existing_oracle_password は 256 文字以内で、/, @, ダブルクォート、改行を含められません。"
  }
}

variable "existing_oracle_dsn" {
  description = "既存 ADB の DSN です。空欄の場合は db_name と workload から lower(db_name)_medium または lower(db_name)_tp を自動生成します。"
  type        = string
  default     = ""

  validation {
    condition     = !can(regex("[\r\n]", var.existing_oracle_dsn))
    error_message = "existing_oracle_dsn に改行は使用できません。"
  }
}

variable "existing_oracle_wallet_password" {
  description = "既存 ADB の wallet 生成 password です。空欄の場合は existing_oracle_password を使用します。"
  type        = string
  sensitive   = true
  default     = ""

  validation {
    condition = (
      var.existing_oracle_wallet_password == ""
      || (
        length(var.existing_oracle_wallet_password) <= 256
        && !can(regex("[/\r\n@\"]", var.existing_oracle_wallet_password))
      )
    )
    error_message = "existing_oracle_wallet_password は 256 文字以内で、/, @, ダブルクォート、改行を含められません。"
  }
}

variable "adb_display_name" {
  description = "新規 ADB の表示名です。空欄の場合は adb_name を使用します。"
  type        = string
  default     = ""

  validation {
    condition     = !can(regex("[\r\n]", var.adb_display_name))
    error_message = "adb_display_name に改行は使用できません。"
  }
}

variable "adb_name" {
  description = "新規 ADB の database name です。DSN は既定で lower(adb_name)_medium になります。"
  type        = string
  default     = "AGENTADB"

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9]{0,13}$", var.adb_name))
    error_message = "adb_name は英字で始まる 14 文字以内の英数字にしてください。"
  }
}

variable "adb_password" {
  description = "新規 ADB の ADMIN password です。SQLcl saved connection のため /, @, ダブルクォート、改行は使用できません。"
  type        = string
  sensitive   = true
  default     = ""

  validation {
    condition = (
      var.adb_password == ""
      || (
        length(var.adb_password) >= 12
        && length(var.adb_password) <= 30
        && can(regex("[0-9]", var.adb_password))
        && can(regex("[a-z]", var.adb_password))
        && can(regex("[A-Z]", var.adb_password))
        && !can(regex("[/\r\n@\"]", var.adb_password))
      )
    )
    error_message = "adb_password は 12-30 文字で大文字・小文字・数字を含め、/, @, ダブルクォート、改行を含められません。"
  }
}

variable "adb_workload" {
  description = "新規 Autonomous Database の workload です。既定は Lakehouse(LH) です。"
  type        = string
  default     = "LH"

  validation {
    condition     = contains(["OLTP", "DW", "AJD", "APEX", "LH"], var.adb_workload)
    error_message = "adb_workload は OLTP, DW, AJD, APEX, LH のいずれかを指定してください。"
  }
}

variable "adb_db_version" {
  description = "新規 ADB の database version です。"
  type        = string
  default     = "26ai"

  validation {
    condition     = contains(["19c", "23ai", "26ai"], var.adb_db_version)
    error_message = "adb_db_version は 19c, 23ai, 26ai のいずれかを指定してください。"
  }
}

variable "adb_compute_model" {
  description = "新規 ADB の compute model です。"
  type        = string
  default     = "ECPU"

  validation {
    condition     = contains(["ECPU", "OCPU"], var.adb_compute_model)
    error_message = "adb_compute_model は ECPU または OCPU を指定してください。"
  }
}

variable "adb_compute_count" {
  description = "新規 ADB の compute count です。"
  type        = number
  default     = 2

  validation {
    condition     = var.adb_compute_count > 0
    error_message = "adb_compute_count は 0 より大きい値にしてください。"
  }
}

variable "adb_is_auto_scaling_enabled" {
  description = "新規 ADB の compute auto scaling を有効にします。"
  type        = bool
  default     = false
}

variable "adb_data_storage_size_in_tbs" {
  description = "新規 ADB の data storage サイズ(TB)です。"
  type        = number
  default     = 1

  validation {
    condition     = var.adb_data_storage_size_in_tbs > 0
    error_message = "adb_data_storage_size_in_tbs は 0 より大きい値にしてください。"
  }
}

variable "adb_is_auto_scaling_for_storage_enabled" {
  description = "新規 ADB の storage auto scaling を有効にします。"
  type        = bool
  default     = false
}

variable "adb_is_elastic_pool_enabled" {
  description = "新規 ADB の elastic pool を有効にします。"
  type        = bool
  default     = false
}

variable "adb_resource_pool_size" {
  description = "Elastic pool 有効時の pool size です。"
  type        = number
  default     = 0

  validation {
    condition     = var.adb_resource_pool_size >= 0
    error_message = "adb_resource_pool_size は 0 以上にしてください。"
  }
}

variable "adb_resource_pool_storage_size_in_tbs" {
  description = "Elastic pool 有効時の pool storage size(TB)です。"
  type        = number
  default     = 0

  validation {
    condition     = var.adb_resource_pool_storage_size_in_tbs >= 0
    error_message = "adb_resource_pool_storage_size_in_tbs は 0 以上にしてください。"
  }
}

variable "license_model" {
  description = "新規 ADB の license model です。"
  type        = string
  default     = "LICENSE_INCLUDED"

  validation {
    condition     = contains(["BRING_YOUR_OWN_LICENSE", "LICENSE_INCLUDED"], var.license_model)
    error_message = "license_model は BRING_YOUR_OWN_LICENSE または LICENSE_INCLUDED を指定してください。"
  }
}

variable "adb_backup_retention_period_in_days" {
  description = "新規 ADB の automatic backup retention days です。"
  type        = number
  default     = 1

  validation {
    condition     = var.adb_backup_retention_period_in_days >= 1
    error_message = "adb_backup_retention_period_in_days は 1 以上にしてください。"
  }
}

variable "adb_network_access_type" {
  description = "新規 ADB の network access mode です。"
  type        = string
  default     = "SECURE_ACCESS_FROM_ALLOWED_IPS_AND_VCNS"

  validation {
    condition = contains([
      "PUBLIC_ENDPOINT",
      "SECURE_ACCESS_FROM_ALLOWED_IPS_AND_VCNS",
      "PRIVATE_ENDPOINT_ONLY"
    ], var.adb_network_access_type)
    error_message = "adb_network_access_type は PUBLIC_ENDPOINT, SECURE_ACCESS_FROM_ALLOWED_IPS_AND_VCNS, PRIVATE_ENDPOINT_ONLY のいずれかを指定してください。"
  }
}

variable "adb_use_private_subnet" {
  description = "旧 tfvars 互換用です。新規 ADB を private endpoint にする場合は adb_network_access_type を優先してください。"
  type        = bool
  default     = false
}

variable "adb_subnet_id" {
  description = "新規 ADB を private endpoint で作成する場合の subnet OCID です。"
  type        = string
  default     = ""

  validation {
    condition     = var.adb_subnet_id == "" || can(regex("^ocid1\\.subnet\\.", var.adb_subnet_id))
    error_message = "adb_subnet_id には subnet OCID を指定してください。"
  }
}

variable "adb_acl_notation_type" {
  description = "SECURE_ACCESS_FROM_ALLOWED_IPS_AND_VCNS 使用時の ACL 表記です。"
  type        = string
  default     = "VCN"

  validation {
    condition     = contains(["VCN", "CIDR_BLOCK"], var.adb_acl_notation_type)
    error_message = "adb_acl_notation_type は VCN または CIDR_BLOCK を指定してください。"
  }
}

variable "adb_acl_vcn_id" {
  description = "ADB ACL に許可する VCN OCID です。空欄の場合は vcn_id を使用します。"
  type        = string
  default     = ""

  validation {
    condition     = var.adb_acl_vcn_id == "" || can(regex("^ocid1\\.vcn\\.", var.adb_acl_vcn_id))
    error_message = "adb_acl_vcn_id には VCN OCID を指定してください。"
  }
}

variable "adb_acl_subnet_id" {
  description = "ADB ACL の VCN 表記で CIDR を絞り込む subnet OCID です。空欄の場合は subnet_id を使用します。"
  type        = string
  default     = ""

  validation {
    condition     = var.adb_acl_subnet_id == "" || can(regex("^ocid1\\.subnet\\.", var.adb_acl_subnet_id))
    error_message = "adb_acl_subnet_id には subnet OCID を指定してください。"
  }
}

variable "adb_acl_cidr_blocks" {
  description = "ADB ACL に許可する CIDR ブロックのカンマ区切りリストです。"
  type        = string
  default     = ""

  validation {
    condition     = !can(regex("[\r\n]", var.adb_acl_cidr_blocks))
    error_message = "adb_acl_cidr_blocks に改行は使用できません。"
  }
}

variable "adb_is_mtls_connection_required" {
  description = "ADB 接続で mTLS を必須にします。既定は true です。"
  type        = bool
  default     = true
}

variable "nodejs_release_base_url" {
  description = "Node.js 24 の公式 release directory URL です。SHASUMS256.txt を使って tarball を検証します。"
  type        = string
  default     = "https://nodejs.org/download/release/latest-v24.x"

  validation {
    condition     = can(regex("^https://nodejs\\.org/download/release/[^\\s]+$", var.nodejs_release_base_url))
    error_message = "nodejs_release_base_url には nodejs.org の release URL を指定してください。"
  }
}

variable "codex_cli_version" {
  description = "npm でインストールする @openai/codex の version です。既定は latest です。"
  type        = string
  default     = "latest"

  validation {
    condition     = can(regex("^[A-Za-z0-9._:+-]+$", var.codex_cli_version))
    error_message = "codex_cli_version は latest または npm version/tag として使える値にしてください。"
  }
}

variable "sqlcl_download_url" {
  description = "SQLcl ZIP の download URL です。既定は Oracle の latest ZIP です。"
  type        = string
  default     = "https://download.oracle.com/otn_software/java/sqldeveloper/sqlcl-latest.zip"

  validation {
    condition     = can(regex("^https://[^\\s]+$", var.sqlcl_download_url))
    error_message = "sqlcl_download_url には https URL を指定してください。"
  }
}

variable "uv_version" {
  description = "uv の version です。空欄の場合は公式 installer の既定値を使用します。"
  type        = string
  default     = ""

  validation {
    condition     = var.uv_version == "" || can(regex("^[0-9A-Za-z._+-]+$", var.uv_version))
    error_message = "uv_version は空欄または version/tag として使える値にしてください。"
  }
}

variable "openai_api_key" {
  description = "任意です。指定した場合だけ opc として codex login --with-api-key を実行します。未指定の場合は SSH 後に手動 login してください。"
  type        = string
  sensitive   = true
  default     = ""

  validation {
    condition     = !can(regex("[\r\n]", var.openai_api_key))
    error_message = "openai_api_key に改行は使用できません。"
  }
}

variable "wallet_content_max_base64_length" {
  description = "cloud-init に注入する縮小 wallet ZIP の base64 長上限です。OCI metadata 上限に当たる前に Terraform で停止するための安全弁です。"
  type        = number
  default     = 16000

  validation {
    condition     = var.wallet_content_max_base64_length > 0 && var.wallet_content_max_base64_length <= 32000
    error_message = "wallet_content_max_base64_length は 1 から 32000 の範囲で指定してください。"
  }
}
