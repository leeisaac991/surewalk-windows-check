@echo off
rem Starts a small test server on this laptop (127.0.0.1:8788 only) to check whether the Excel texts panel can talk
rem to the texting server directly, without GroupMe. Changes nothing. Close this window to stop it.
rem Then in Excel: Script Lab > Import > paste the link test snippet's link, open it, click "Run all tests".
setlocal EnableExtensions
title SURE Walk - Excel link probe
set "HERE=%~dp0"
set "WORK=%LOCALAPPDATA%\surewalk-check"
if not exist "%WORK%" mkdir "%WORK%"
powershell.exe -NoProfile -NonInteractive -Command "Get-ChildItem -LiteralPath '%HERE%.' -Recurse -File | Unblock-File" >nul 2>&1
set "NODE="
for %%z in ("%HERE%node-v*-win-x64.zip") do (
  if not exist "%WORK%\%%~nz\node.exe" (echo Unpacking Node.js ... & tar -xf "%%z" -C "%WORK%")
  if exist "%WORK%\%%~nz\node.exe" set "NODE=%WORK%\%%~nz\node.exe"
)
if not defined NODE (echo Could not find or unpack Node.js. & pause & exit /b 1)
set "LOG=%HERE%excel-link-log.txt"
(echo x)>"%LOG%" 2>nul || set "LOG=%WORK%\excel-link-log.txt"
echo Results go to: %LOG%
"%NODE%" "%HERE%excel-link\probe-server.mjs" "%LOG%"
pause
