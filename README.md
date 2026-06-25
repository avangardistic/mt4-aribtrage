# MT4 ZeroMQ Arbitrage System

![Platform](https://img.shields.io/badge/platform-MetaTrader%204-blue)
![Language](https://img.shields.io/badge/language-MQL4%20%7C%20Python-green)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

A MetaTrader 4 proof-of-concept for monitoring price differences between two brokers and coordinating paired trades through ZeroMQ.

> ⚠️ **Trading risk warning:** This project automates real trading actions. Arbitrage strategies can fail because of latency, requotes, spread widening, slippage, rejected orders, broker restrictions, disconnections, or code defects. Use demo accounts first. You are responsible for all financial risk.

## What It Does

This project runs two MT4 Expert Advisors:

- **Master EA** on the primary broker, which receives remote prices, detects spread differences, opens the local leg, sends commands to the slave, and manages exits.
- **Slave EA** on the secondary broker, which sends its local prices to the master and executes validated order or close commands.

The current default configuration is aimed at `XAUUSD_o` on LiteFinance and `XAUUSD` on OpoFinance, but symbols, lot size, ports, thresholds, and risk settings are configurable in the EA inputs.

## Architecture

```text
Slave MT4 terminal                         Master MT4 terminal
OpoFinance / XAUUSD                        LiteFinance / XAUUSD_o

Price PUSH  ─────────────────────────────▶  PULL :5555
REP orders ◀──────────────────────────────  REQ  :5556

Master responsibilities:
- compare local and remote bid/ask values
- open the master-side trade
- send ORDER, CLOSE, and STATUS commands
- apply take-profit, stop-loss, trailing, risk-free, and time-limit rules

Slave responsibilities:
- publish current bid/ask heartbeat messages
- validate incoming prices and lot sizes
- execute or close the slave-side trade
- return SUCCESS, ERROR, CLOSE_SUCCESS, and STATUS responses
```

### Message Protocol

| Direction | Message | Purpose |
| --- | --- | --- |
| Slave → Master | `SYMBOL|BID|ASK|TIMESTAMP` | Price update and heartbeat |
| Master → Slave | `ORDER|CMD_ID|TYPE|SYMBOL|LOT|PRICE` | Open slave-side order |
| Slave → Master | `SUCCESS|TICKET` / `ERROR|CODE` | Order result |
| Master → Slave | `CLOSE|CMD_ID` | Close slave-side positions |
| Slave → Master | `CLOSE_SUCCESS|ALL` / `ERROR|CLOSE_FAILED` | Close result |
| Master → Slave | `STATUS|CMD_ID` | Reconciliation request |

## Features

- ZeroMQ-based MT4-to-MT4 communication.
- Master/slave Expert Advisor workflow.
- Configurable symbol mapping for broker-specific names.
- On-chart Start/Stop buttons and status dashboard.
- Heartbeat and connection status tracking.
- Duplicate command handling on the slave side.
- Risk controls: take profit, stop loss, trailing profit lock, risk-free threshold, and maximum position time.
- Python installer/uninstaller for copying files into MT4 terminal folders.

## Folder Structure

```text
.
├── config/
│   └── terminals.example.json      # Safe template for local MT4 paths
├── docs/
│   ├── development-log.md          # Historical development notes
│   └── system-report-fa.md         # Persian system report and code notes
├── src/
│   ├── experts/
│   │   ├── ArbitrageMaster.mq4
│   │   └── ArbitrageSlave.mq4
│   └── scripts/
│       └── TestZmqConnection.mq4
├── tools/
│   ├── install_arbitrage.py
│   ├── uninstall_arbitrage.py
│   ├── run_install.bat
│   └── run_uninstall.bat
├── vendor/
│   └── mql4-package/MQL4/          # Required Include and Libraries files for MT4
├── archive/
│   └── upstream-sources/           # Original downloaded helper/upstream material
├── .gitignore
├── LICENSE
└── README.md
```

## Requirements

| Requirement | Notes |
| --- | --- |
| MetaTrader 4 | Two separate terminals are expected. |
| Windows | MT4 and the included DLLs are Windows-oriented. |
| Python 3.8+ | Required only for installer/uninstaller helpers. |
| DLL imports enabled | Enable in MT4 options and EA settings. |
| ZeroMQ runtime DLLs | Included in `vendor/mql4-package/MQL4/Libraries`. |

The included 32-bit DLLs are intended for MT4. Do not replace them with 64-bit DLLs unless you know your terminal/runtime supports them.

## Installation

### 1. Clone or download the project

```powershell
git clone https://github.com/avangardistic/mt4-aribtrage.git
cd mt4-aribtrage
```

### 2. Configure local MT4 terminal paths

Copy the example config:

```powershell
copy config\terminals.example.json config\terminals.json
```

Edit `config/terminals.json` and set each value to the terminal's `MQL4` folder, for example:

```json
{
  "terminals": {
    "LiteFinance": "C:/Users/YourName/AppData/Roaming/MetaQuotes/Terminal/TERMINAL_ID_1/MQL4",
    "OpoFinance": "C:/Users/YourName/AppData/Roaming/MetaQuotes/Terminal/TERMINAL_ID_2/MQL4"
  }
}
```

`config/terminals.json` is ignored by Git because it contains machine-specific paths.

### 3. Install files into MT4

```powershell
python tools\install_arbitrage.py
```

The installer copies:

- `src/experts/ArbitrageMaster.mq4` and `src/experts/ArbitrageSlave.mq4` to each terminal's `MQL4/Experts`.
- `src/scripts/TestZmqConnection.mq4` to each terminal's `MQL4/Scripts`.
- `vendor/mql4-package/MQL4/Include` and `vendor/mql4-package/MQL4/Libraries` to each terminal's `MQL4` folder.

It also creates `MQL4_Backup_Arbitrage` next to each terminal's `MQL4` folder unless `--skip-backup` is used.

### 4. Restart MT4 and compile

Open MetaEditor in each terminal and compile:

- `ArbitrageMaster.mq4`
- `ArbitrageSlave.mq4`
- `TestZmqConnection.mq4`

Resolve any broker- or terminal-specific compile errors before using the EAs.

## Configuration Guide

### Master EA

| Input | Default | Meaning |
| --- | ---: | --- |
| `InpSymbolLocal` | `XAUUSD_o` | Symbol on the master broker |
| `InpSymbolRemote` | `XAUUSD` | Symbol expected from slave broker |
| `InpMinSpread` | `50.0` | Minimum entry difference in points |
| `InpLotSize` | `0.01` | Trade volume |
| `InpMasterPort` | `5555` | PULL port for slave prices |
| `InpSlavePort` | `5556` | REQ port for slave commands |
| `InpSlippage` | `5` | Allowed slippage |
| `InpMagic` | `5402` | Magic number for filtering positions |
| `InpTakeProfit` | `2.0` | Profit target in account currency |
| `InpStopLoss` | `1.5` | Loss limit in account currency |
| `InpTrailingStart` | `1.0` | Profit level where trailing starts |
| `InpTrailingStep` | `0.5` | Trailing lock step |
| `InpMaxTimeMinutes` | `5` | Maximum position duration |
| `InpRiskFreeThreshold` | `0.5` | Profit threshold for risk-free mode |

### Slave EA

| Input | Default | Meaning |
| --- | ---: | --- |
| `InpMasterIP` | `127.0.0.1` | Master terminal host/IP |
| `InpMasterPubPort` | `5555` | Master PULL port |
| `InpMasterRepPort` | `5556` | Master REQ port |
| `InpSymbolLocal` | `XAUUSD` | Symbol on the slave broker |
| `InpLotSize` | `0.01` | Trade volume |
| `InpSlippage` | `5` | Allowed slippage |
| `InpMagic` | `5402` | Magic number for filtering positions |

Use unique ports if multiple copies run on the same machine.

## Usage

1. Start both MT4 terminals.
2. Enable **Allow DLL imports** in MT4.
3. Run `TestZmqConnection` in each terminal.
4. Attach `ArbitrageMaster` to the master broker chart.
5. Attach `ArbitrageSlave` to the slave broker chart.
6. Confirm symbols and inputs match your brokers.
7. Press **START** on both dashboards.
8. Monitor the Experts and Journal tabs for connection, order, and close messages.

Use demo accounts until you have verified compilation, connectivity, order routing, spread logic, and emergency stop behavior.

## Uninstall

```powershell
python tools\uninstall_arbitrage.py
```

To restore from installer backups:

```powershell
python tools\uninstall_arbitrage.py --restore
```

## Troubleshooting

| Symptom | Checks |
| --- | --- |
| EA cannot load DLL | Enable DLL imports and verify `libzmq.dll` and `libsodium.dll` are in `MQL4/Libraries`. |
| No price updates | Check ports `5555`/`5556`, firewall rules, `InpMasterIP`, and that both EAs are started. |
| Compile errors for `Zmq/Zmq.mqh` | Verify `MQL4/Include/Zmq` and `MQL4/Include/Mql` were copied to the terminal. |
| Slave rejects orders | Confirm symbol name, lot size, minimum lot step, market status, and slippage. |
| Positions mismatch | Stop both EAs, manually inspect open trades on both brokers, and close/reconcile if needed. |
| Installer cannot find terminals | Edit `config/terminals.json` with the correct `MQL4` paths from each MT4 data folder. |

## Validation

There is no automated test suite in this repository. Practical validation should include:

- Python syntax checks for tools.
- MT4/MetaEditor compilation of all `.mq4` files.
- Running `TestZmqConnection` on both terminals.
- Demo-account dry runs with very small lots.

## Third-Party Components

This repository includes a prepared MT4 package derived from:

- [`dingmaotu/mql-zmq`](https://github.com/dingmaotu/mql-zmq)
- [`dingmaotu/mql4-lib`](https://github.com/dingmaotu/mql4-lib)

Original downloaded source folders and licenses are kept under `archive/upstream-sources/` for review. Check third-party license terms before redistributing binaries or modified library code.

## Roadmap

- Add a structured configuration file for EA parameters.
- Add a simulation/backtest harness for spread logic.
- Add structured CSV/JSON event logging.
- Add automatic position reconciliation reports.
- Add CI checks for Python tooling and repository hygiene.
- Document broker-specific setup examples without storing private terminal paths.

## License

Project code is released under the MIT License. See `LICENSE`.

Third-party libraries and DLLs retain their original licenses.
