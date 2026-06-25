import argparse
import json
import shutil
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
PACKAGE_DIR = PROJECT_ROOT / "vendor" / "mql4-package" / "MQL4"
EXPERTS_DIR = PROJECT_ROOT / "src" / "experts"
SCRIPTS_DIR = PROJECT_ROOT / "src" / "scripts"
CONFIG_PATH = PROJECT_ROOT / "config" / "terminals.json"

EXPERT_FILES = ["ArbitrageMaster.mq4", "ArbitrageSlave.mq4"]
SCRIPT_FILES = ["TestZmqConnection.mq4"]
PACKAGE_FOLDERS = ["Include", "Libraries"]


def print_header(text):
    print("\n" + "=" * 70)
    print(f" {text}")
    print("=" * 70)


def print_success(text):
    print(f"✅ {text}")


def print_error(text):
    print(f"❌ {text}")


def print_info(text):
    print(f"ℹ️  {text}")


def load_terminals(config_path):
    if not config_path.exists():
        raise FileNotFoundError(
            f"Config file not found: {config_path}\n"
            "Copy config/terminals.example.json to config/terminals.json and edit your MT4 MQL4 paths."
        )

    with config_path.open("r", encoding="utf-8") as config_file:
        config = json.load(config_file)

    terminals = config.get("terminals", {})
    if not terminals:
        raise ValueError("No terminals configured. Add entries under the 'terminals' object.")

    return {name: Path(path).expanduser() for name, path in terminals.items()}


def copy_folder(source_root, target_root, folder_name):
    source_path = source_root / folder_name
    target_path = target_root / folder_name

    if not source_path.exists():
        print_error(f"Missing source folder: {source_path}")
        return False

    if target_path.exists():
        shutil.rmtree(target_path)
        print_info(f"Removed old folder: {target_path}")

    shutil.copytree(source_path, target_path)
    print_success(f"Copied {folder_name} -> {target_path}")
    return True


def copy_file(source_file, target_dir):
    if not source_file.exists():
        print_error(f"Missing source file: {source_file}")
        return False

    target_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source_file, target_dir / source_file.name)
    print_success(f"Copied {source_file.name} -> {target_dir}")
    return True


def create_backup(mql4_path):
    backup_path = mql4_path.parent / "MQL4_Backup_Arbitrage"
    if backup_path.exists():
        print_info(f"Backup already exists: {backup_path}")
        return

    shutil.copytree(mql4_path, backup_path)
    print_success(f"Created backup: {backup_path}")


def validate_sources():
    required_paths = [PACKAGE_DIR, EXPERTS_DIR, SCRIPTS_DIR]
    required_paths += [PACKAGE_DIR / folder for folder in PACKAGE_FOLDERS]
    required_paths += [EXPERTS_DIR / file_name for file_name in EXPERT_FILES]
    required_paths += [SCRIPTS_DIR / file_name for file_name in SCRIPT_FILES]

    missing = [path for path in required_paths if not path.exists()]
    if missing:
        for path in missing:
            print_error(f"Missing required path: {path}")
        return False

    return True


def install(config_path, skip_backup=False):
    print_header("Installing MT4 Arbitrage System")

    if not validate_sources():
        return 1

    terminals = load_terminals(config_path)
    for terminal_name, mql4_path in terminals.items():
        print_header(f"Installing to {terminal_name}")
        print_info(f"Target MQL4 path: {mql4_path}")

        if not mql4_path.exists():
            print_error(f"MT4 MQL4 folder not found: {mql4_path}")
            continue

        if not skip_backup:
            create_backup(mql4_path)

        for folder_name in PACKAGE_FOLDERS:
            copy_folder(PACKAGE_DIR, mql4_path, folder_name)

        for file_name in EXPERT_FILES:
            copy_file(EXPERTS_DIR / file_name, mql4_path / "Experts")

        for file_name in SCRIPT_FILES:
            copy_file(SCRIPTS_DIR / file_name, mql4_path / "Scripts")

    print_header("Install complete")
    print("Restart MT4, enable DLL imports, then run TestZmqConnection before attaching the EAs.")
    print("Use demo accounts first.")
    return 0


def parse_args():
    parser = argparse.ArgumentParser(description="Install the arbitrage EAs into configured MT4 terminals.")
    parser.add_argument("--config", type=Path, default=CONFIG_PATH, help="Path to terminals.json")
    parser.add_argument("--skip-backup", action="store_true", help="Do not create MQL4_Backup_Arbitrage folders")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    raise SystemExit(install(args.config, args.skip_backup))
