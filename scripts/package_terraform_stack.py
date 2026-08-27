#!/usr/bin/env python3
"""OCI Resource Manager 用 Terraform stack ZIP を作成します。"""

from __future__ import annotations

import argparse
import stat
import sys
import zipfile
from pathlib import Path


PACKAGE_NAME = "no.1-agent-workbench-terraform-stack.zip"
FIXED_TIMESTAMP = (2026, 1, 1, 0, 0, 0)


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def resolve_path(path: str, *, base: Path) -> Path:
    candidate = Path(path)
    if candidate.is_absolute():
        return candidate
    return base / candidate


def stack_files(stack_dir: Path) -> list[Path]:
    root_files = [
        stack_dir / "schema.yaml",
        *sorted(stack_dir.glob("*.tf")),
        stack_dir / "extract_wallet.sh",
    ]
    nested_files = [
        stack_dir / "cloud_init" / "bootstrap.template.yaml",
        *sorted((stack_dir / "scripts").glob("*.sh")),
    ]
    files = [path for path in [*root_files, *nested_files] if path.is_file()]

    required = {
        stack_dir / "schema.yaml",
        stack_dir / "extract_wallet.sh",
        stack_dir / "cloud_init" / "bootstrap.template.yaml",
        stack_dir / "scripts" / "bootstrap.sh",
        stack_dir / "scripts" / "common.sh",
        stack_dir / "scripts" / "grow_boot_volume.sh",
        stack_dir / "scripts" / "install_nodejs.sh",
        stack_dir / "scripts" / "install_codex.sh",
        stack_dir / "scripts" / "install_sqlcl.sh",
        stack_dir / "scripts" / "install_uv.sh",
        stack_dir / "scripts" / "setup_codex_mcp.sh",
        stack_dir / "scripts" / "setup_wallet.sh",
        stack_dir / "scripts" / "verify_workbench.sh",
    }
    missing = sorted(
        path.relative_to(stack_dir).as_posix() for path in required if not path.is_file()
    )
    if missing:
        raise FileNotFoundError(f"必要な stack ファイルがありません: {', '.join(missing)}")
    if not any(path.suffix == ".tf" for path in files):
        raise FileNotFoundError("stack root に Terraform .tf ファイルがありません。")
    return files


def write_file(zip_file: zipfile.ZipFile, source: Path, arcname: str) -> None:
    mode = stat.S_IMODE(source.stat().st_mode)
    info = zipfile.ZipInfo(arcname)
    info.create_system = 3
    info.external_attr = (mode & 0xFFFF) << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    info.date_time = FIXED_TIMESTAMP
    zip_file.writestr(info, source.read_bytes())


def build_package(stack_dir: Path, output_path: Path) -> list[str]:
    stack_dir = stack_dir.resolve()
    output_path = output_path.resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)

    entries: list[str] = []
    with zipfile.ZipFile(output_path, "w") as zip_file:
        for source in stack_files(stack_dir):
            arcname = source.relative_to(stack_dir).as_posix()
            write_file(zip_file, source, arcname)
            entries.append(arcname)
    return entries


def parse_args(argv: list[str]) -> argparse.Namespace:
    root = repo_root()
    parser = argparse.ArgumentParser(
        description="terraform/stack を OCI Resource Manager release asset として ZIP 化します。",
    )
    parser.add_argument(
        "--stack-dir",
        default="terraform/stack",
        help="repository root から見た Terraform stack directory。",
    )
    parser.add_argument(
        "--output",
        default=f"dist/{PACKAGE_NAME}",
        help="repository root から見た出力 ZIP path。",
    )
    parser.set_defaults(repo_root=root)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    root = args.repo_root
    stack_dir = resolve_path(args.stack_dir, base=root)
    output_path = resolve_path(args.output, base=root)

    entries = build_package(stack_dir, output_path)
    print(f"Created {output_path}")
    for entry in entries:
        print(f"  {entry}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
