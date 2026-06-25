@echo off
echo ========================================
echo   حذف سیستم آربیتراژ
echo ========================================
echo.
cd /d "%~dp0"
python uninstall_arbitrage.py
pause
