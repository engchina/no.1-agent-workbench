import re
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
STACK = ROOT / "terraform" / "stack"

README = (ROOT / "README.md").read_text(encoding="utf-8")
VARIABLES = (STACK / "variables.tf").read_text(encoding="utf-8")
LOCALS = (STACK / "locals.tf").read_text(encoding="utf-8")
DATASOURCES = (STACK / "datasources.tf").read_text(encoding="utf-8")
COMPUTE = (STACK / "compute.tf").read_text(encoding="utf-8")
OUTPUTS = (STACK / "output.tf").read_text(encoding="utf-8")
PROVIDER = (STACK / "provider.tf").read_text(encoding="utf-8")
SCHEMA = (STACK / "schema.yaml").read_text(encoding="utf-8")
CLOUD_INIT = (STACK / "cloud_init" / "bootstrap.template.yaml").read_text(
    encoding="utf-8"
)
SCRIPTS = {
    path.name: path.read_text(encoding="utf-8")
    for path in sorted((STACK / "scripts").glob("*.sh"))
}
EXTRACT_WALLET = (STACK / "extract_wallet.sh").read_text(encoding="utf-8")
PACKAGE_SCRIPT = ROOT / "scripts" / "package_terraform_stack.py"


class TerraformStackConfigurationTests(unittest.TestCase):
    def test_schema_variables_match_terraform_variables(self) -> None:
        terraform_variables = set(
            re.findall(r'^variable "([a-z0-9_]+)"', VARIABLES, re.MULTILINE)
        )
        schema_variables_block = SCHEMA.split("\nvariables:\n", 1)[1].split(
            "\noutputs:\n", 1
        )[0]
        schema_variables = set(
            re.findall(r"^  ([a-z0-9_]+):$", schema_variables_block, re.MULTILINE)
        )
        self.assertEqual(terraform_variables, schema_variables)

    def test_schema_outputs_match_terraform_outputs(self) -> None:
        terraform_outputs = set(
            re.findall(r'^output "([a-z0-9_]+)"', OUTPUTS, re.MULTILINE)
        )
        schema_outputs_block = SCHEMA.split("\noutputs:\n", 1)[1]
        schema_outputs = set(
            re.findall(r"^  ([a-z0-9_]+):$", schema_outputs_block, re.MULTILINE)
        )
        self.assertEqual(terraform_outputs, schema_outputs)

    def test_only_tokyo_and_osaka_are_supported(self) -> None:
        self.assertIn('["ap-tokyo-1", "ap-osaka-1"]', VARIABLES)
        self.assertIn('supported_regions = ["ap-tokyo-1", "ap-osaka-1"]', LOCALS)
        self.assertIn('- "ap-tokyo-1"', SCHEMA)
        self.assertIn('- "ap-osaka-1"', SCHEMA)
        self.assertNotIn("ap-seoul-1", SCHEMA)
        self.assertIn("contains(local.supported_regions, local.selected_region)", COMPUTE)
        self.assertIn("region = local.selected_region", PROVIDER)

    def test_defaults_follow_plan(self) -> None:
        defaults = {
            "instance_shape": '"VM.Standard.E5.Flex"',
            "instance_flex_shape_ocpus": "2",
            "instance_flex_shape_memory": "24",
            "instance_boot_volume_size": "100",
            "adb_workload": '"LH"',
            "codex_cli_version": '"latest"',
            "nodejs_release_base_url": '"https://nodejs.org/download/release/latest-v24.x"',
        }
        for variable, value in defaults.items():
            self.assertRegex(
                VARIABLES,
                rf'(?s)variable "{variable}" \{{.*?default\s+=\s+{re.escape(value)}',
            )
            self.assertRegex(
                SCHEMA,
                rf"(?s)  {variable}:.*?default:\s+{re.escape(value)}",
            )
        self.assertIn('upper(local.effective_adb_workload) == "OLTP" ? "tp" : "medium"', LOCALS)

    def test_oracle_linux_9_image_is_auto_selected_with_override(self) -> None:
        self.assertIn('operating_system         = "Oracle Linux"', DATASOURCES)
        self.assertIn('operating_system_version = "9"', DATASOURCES)
        self.assertIn('shape                    = var.instance_shape', DATASOURCES)
        self.assertIn('sort_by                  = "TIMECREATED"', DATASOURCES)
        self.assertIn('sort_order               = "DESC"', DATASOURCES)
        self.assertIn(r'^Oracle-Linux-9\\.[0-9]+-', LOCALS)
        self.assertIn('trimspace(var.instance_image_ocid) != ""', LOCALS)
        self.assertIn("local.instance_image_id != \"\"", COMPUTE)
        self.assertIn("selected_oracle_linux_image_ocid", OUTPUTS)

    def test_boot_volume_growth_precedes_downloads(self) -> None:
        bootstrap = SCRIPTS["bootstrap.sh"]
        main = bootstrap.split("main() {", 1)[1]
        grow = main.index("/usr/local/sbin/no1-agent-workbench/grow_boot_volume.sh")
        packages = main.index("install_base_packages")
        node = main.index("install_nodejs.sh")
        self.assertLess(grow, packages)
        self.assertLess(grow, node)
        self.assertIn("dnf -y install oci-utils", SCRIPTS["grow_boot_volume.sh"])
        self.assertIn("/usr/libexec/oci-growfs -y", SCRIPTS["grow_boot_volume.sh"])
        self.assertIn("xfs|ext4", SCRIPTS["grow_boot_volume.sh"])
        self.assertIn("* 90 / 100", SCRIPTS["grow_boot_volume.sh"])

    def test_opc_ownership_and_codex_npm_prefix_are_enforced(self) -> None:
        self.assertIn("run_as_opc()", SCRIPTS["common.sh"])
        self.assertIn("HOME=${home}", SCRIPTS["common.sh"])
        self.assertIn("USER=${user}", SCRIPTS["common.sh"])
        self.assertIn("LOGNAME=${user}", SCRIPTS["common.sh"])
        self.assertIn('npm config set prefix "${home}/.npm-global"', SCRIPTS["install_codex.sh"])
        self.assertIn("npm config delete omit", SCRIPTS["install_codex.sh"])
        self.assertIn("npm config set include optional", SCRIPTS["install_codex.sh"])
        self.assertIn("npm view @openai/codex versions --json", SCRIPTS["install_codex.sh"])
        self.assertIn('npm view "@openai/codex@${version}-${suffix}" dist.tarball', SCRIPTS["install_codex.sh"])
        self.assertIn('tail -15', SCRIPTS["install_codex.sh"])
        self.assertIn('npm install -g "@openai/codex@${resolved_version}"', SCRIPTS["install_codex.sh"])
        self.assertIn("--include=optional", SCRIPTS["install_codex.sh"])
        self.assertIn("--no-audit", SCRIPTS["install_codex.sh"])
        self.assertIn('codex/node_modules/@openai/%s/vendor', SCRIPTS["install_codex.sh"])
        self.assertIn('codex login --with-api-key', SCRIPTS["install_codex.sh"])
        self.assertIn('ensure_opc_owned_dir "${home}/.dbtools" 0700', SCRIPTS["bootstrap.sh"])
        self.assertIn('ensure_opc_owned_dir "${wallet_dir}" 0700', SCRIPTS["bootstrap.sh"])
        self.assertIn("assert_owner", SCRIPTS["verify_workbench.sh"])
        self.assertIn('assert_mode "${wallet_dir}" "700"', SCRIPTS["verify_workbench.sh"])

    def test_sqlcl_wallet_and_mcp_configuration_follow_plan(self) -> None:
        self.assertIn("java-21-openjdk-headless", SCRIPTS["bootstrap.sh"])
        self.assertIn("/opt/sqlcl", SCRIPTS["install_sqlcl.sh"])
        self.assertIn("/usr/local/bin/sql", SCRIPTS["install_sqlcl.sh"])
        self.assertIn("conn -save agent_workbench -savepwd -cloudconfig", SCRIPTS["setup_wallet.sh"])
        self.assertIn("conn -name agent_workbench", SCRIPTS["verify_workbench.sh"])
        self.assertIn('[mcp_servers.sqlcl]', SCRIPTS["setup_codex_mcp.sh"])
        self.assertIn('args = ["-mcp"]', SCRIPTS["setup_codex_mcp.sh"])
        self.assertIn("TNS_ADMIN", SCRIPTS["setup_codex_mcp.sh"])
        self.assertIn("JAVA_HOME", SCRIPTS["setup_codex_mcp.sh"])

    def test_wallet_extract_keeps_only_required_wallet_files(self) -> None:
        for file_name in (
            "cwallet.sso",
            "ewallet.pem",
            "tnsnames.ora",
            "sqlnet.ora",
            "ojdbc.properties",
        ):
            self.assertIn(file_name, EXTRACT_WALLET)
        for file_name in ("keystore.jks", "truststore.jks", "ewallet.p12", "README"):
            self.assertNotIn(file_name, EXTRACT_WALLET)
        self.assertIn("wallet_content_max_base64_length", COMPUTE)

    def test_password_rules_for_sqlcl_saved_connection(self) -> None:
        self.assertIn('!can(regex("[/\\r\\n@\\"]", var.adb_password))', VARIABLES)
        self.assertIn('!can(regex("[/\\r\\n@\\"]", var.existing_oracle_password))', VARIABLES)
        self.assertIn('!can(regex("[/\\r\\n@\\"]", var.existing_oracle_wallet_password))', VARIABLES)

    def test_bootstrap_config_keys_match_script_reads(self) -> None:
        script_reads: set[str] = set()
        for script in SCRIPTS.values():
            script_reads.update(re.findall(r"read_config ([a-z0-9_]+)", script))

        bootstrap_block = re.search(
            r"(?s)bootstrap_config = jsonencode\(\{(.*?)\n  \}\)",
            LOCALS,
        )
        self.assertIsNotNone(bootstrap_block)
        terraform_keys = set(
            re.findall(r"^    ([a-z0-9_]+)\s+=", bootstrap_block.group(1), re.MULTILINE)
        )
        self.assertTrue(script_reads.issubset(terraform_keys), script_reads - terraform_keys)

    def test_cloud_init_contains_all_bootstrap_scripts(self) -> None:
        for script_name in SCRIPTS:
            self.assertIn(f"/usr/local/sbin/no1-agent-workbench/{script_name}", CLOUD_INIT)
        self.assertIn("/etc/no1-agent-workbench/wallet.zip", CLOUD_INIT)
        self.assertIn("no1-agent-workbench-bootstrap.service", CLOUD_INIT)

    def test_package_zip_contains_only_resource_manager_stack_files(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            package_path = Path(tmp) / "stack.zip"
            subprocess.run(
                ["python3", str(PACKAGE_SCRIPT), "--output", str(package_path)],
                cwd=ROOT,
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            with zipfile.ZipFile(package_path) as archive:
                names = set(archive.namelist())

        self.assertIn("schema.yaml", names)
        self.assertIn("cloud_init/bootstrap.template.yaml", names)
        self.assertIn("scripts/bootstrap.sh", names)
        self.assertIn("scripts/grow_boot_volume.sh", names)
        self.assertIn("extract_wallet.sh", names)
        self.assertFalse(any(name.endswith(".tfvars") for name in names))
        self.assertNotIn("wallet_full.zip", names)
        self.assertNotIn("wallet_small.zip", names)


if __name__ == "__main__":
    unittest.main()
