@echo off
chcp 65001 >nul
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-AgentPagerCodexNotify.ps1"
if errorlevel 1 (
  echo.
  echo 操作失败，请把上面的错误信息发给开发者。
) else (
  echo.
  echo 操作成功。
)
pause
