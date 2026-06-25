import argparse
import json
import shutil
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = PROJECT_ROOT / "config" / "terminals.json"

EXPERT_FILES = ["ArbitrageMaster.mq4", "ArbitrageSlave.mq4"]
SCRIPT_FILES = ["TestZmqConnection.mq4"]
COMPILED_FILES = ["ArbitrageMaster.ex4", "ArbitrageSlave.ex4", "TestZmqConnection.ex4"]
PACKAGE_PATHS = [
    Path("Include") / "Mql",
    Path("Include") / "Zmq",
    Path("Libraries") / "libzmq.dll",
    Path("Libraries") / "libsodium.dll",
]


def print_header(text):
    print("\n" + "=" * 70)
    print(f" {text}")
    print("=" * 70)


def print_success(text):
    print(f"✅ {text}")


def print_info(text):
    print(f"ℹ️  {text}")


def print_warning(text):
    print(f"⚠️  {text}")


def load_terminals(config_path):
    if not config_path.exists():
        raise FileNotFoundError(
            f"Config file not found: {config_path}\n"
            "Copy config/terminals.example.json to config/terminals.json and edit your MT4 MQL4 paths."
        )

    with config_path.open("r", encoding="utf-8") as config_file:
        config = json.load(config_file)

    return {name: Path(path).expanduser() for name, path in config.get("terminals", {}).items()}


def remove_path(path):
    if not path.exists():
        print_info(f"Not found: {path}")
        return

    if path.is_dir():
        shutil.rmtree(path)
    else:
        path.unlink()
    print_success(f"Removed: {path}")


def restore_backup(mql4_path):
    backup_path = mql4_path.parent / "MQL4_Backup_Arbitrage"
    if not backup_path.exists():
        print_warning(f"No backup found: {backup_path}")
        return

    if mql4_path.exists():
        shutil.rmtree(mql4_path)
    shutil.copytree(backup_path, mql4_path)
    print_success(f"Restored backup: {backup_path} -> {mql4_path}")


def uninstall(config_path, restore=False, yes=False):
    print_header("Uninstalling MT4 Arbitrage System")

    if not yes:
        answer = input("Remove arbitrage files from configured MT4 terminals? (y/n): ").strip().lower()
        if answer != "y":
            print_info("Cancelled.")
            return 0

    terminals = load_terminals(config_path)
    for terminal_name, mql4_path in terminals.items():
        print_header(f"Uninstalling from {terminal_name}")
        print_info(f"Target MQL4 path: {mql4_path}")

        if not mql4_path.exists():
            print_warning(f"MT4 MQL4 folder not found: {mql4_path}")
            continue

        if restore:
            restore_backup(mql4_path)
            continue

        for file_name in EXPERT_FILES:
            remove_path(mql4_path / "Experts" / file_name)

        for file_name in SCRIPT_FILES:
            remove_path(mql4_path / "Scripts" / file_name)

        for file_name in COMPILED_FILES:
            remove_path(mql4_path / "Experts" / file_name)
            remove_path(mql4_path / "Scripts" / file_name)

        for relative_path in PACKAGE_PATHS:
            remove_path(mql4_path / relative_path)

    print_header("Uninstall complete")
    return 0


def parse_args():
    parser = argparse.ArgumentParser(description="Remove arbitrage files from configured MT4 terminals.")
    parser.add_argument("--config", type=Path, default=CONFIG_PATH, help="Path to terminals.json")
    parser.add_argument("--restore", action="store_true", help="Restore MQL4_Backup_Arbitrage instead of selective removal")
    parser.add_argument("--yes", action="store_true", help="Do not prompt for confirmation")
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    raise SystemExit(uninstall(args.config, args.restore, args.yes))
