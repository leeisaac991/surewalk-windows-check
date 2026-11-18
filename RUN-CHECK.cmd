@echo off
rem SURE Walk - Windows laptop check.
rem Double-click this file. It installs nothing and changes no settings.
rem It tests whether the texting server and the iPhone Bluetooth bridge could run here,
rem trying several ways (cmd, PowerShell, Windows Script Host, the built-in C# compiler, portable Node),
rem and writes everything to surewalk-check-log.txt.
rem   RUN-CHECK.cmd nophone      skip connecting to the iPhone
setlocal EnableExtensions EnableDelayedExpansion
title SURE Walk Windows check
set "HERE=%~dp0"
set "MODE=%~1"
if not defined MODE set "MODE=phone"
set "WORK=%LOCALAPPDATA%\surewalk-check"
if not exist "%WORK%" mkdir "%WORK%" >nul 2>&1
set "LOG=%HERE%surewalk-check-log.txt"
(echo SURE Walk Windows check)>"%LOG%" 2>nul || set "LOG=%WORK%\surewalk-check-log.txt"
(echo SURE Walk Windows check)>"%LOG%" 2>nul || (echo Cannot write a log file anywhere. & pause & exit /b 1)

echo.
echo SURE Walk Windows check - log: %LOG%
echo This takes about a minute. Keep the iPhone unlocked and near the laptop.
echo.
>>"%LOG%" echo Started: %DATE% %TIME%
for /f "delims=" %%v in ('ver') do >>"%LOG%" echo Windows: %%v
>>"%LOG%" echo CPU: %PROCESSOR_ARCHITECTURE%
>>"%LOG%" echo Check folder: %HERE%
>>"%LOG%" echo Work folder: %WORK%
>>"%LOG%" echo Lines starting with RESULT are the outcomes. No text messages or phone numbers are logged.
>>"%LOG%" echo.

rem ---------------------------------------------------------------- 1. plain cmd checks
call :section "1. Basic checks (cmd)"
call :res cmd-runs PASS "batch files run"

net session >nul 2>&1
if !errorlevel! == 0 (call :res admin-now INFO "this window HAS admin rights - not needed, just noting") else (call :res admin-now INFO "no admin rights - expected, nothing below needs them")
whoami /groups 2>nul | find "S-1-5-32-544" >nul && (call :res admin-group INFO "your account is in the Administrators group") || (call :res admin-group INFO "your account is a standard user")

(echo x)>"%WORK%\w.tmp" 2>nul && (del "%WORK%\w.tmp" & call :res user-folder-write PASS "can write %WORK%") || call :res user-folder-write FAIL "cannot write %WORK%"

set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
(echo x)>"%STARTUP%\surewalk-check.tmp" 2>nul && (del "%STARTUP%\surewalk-check.tmp" & call :res startup-folder PASS "can add a start-at-login shortcut without admin") || call :res startup-folder FAIL "cannot write the Startup folder - would have to start by hand"

rem A Windows program copied into your own folder: AppLocker / Software Restriction Policies usually block this.
copy /y "%SystemRoot%\System32\whoami.exe" "%WORK%\sw-test.exe" >nul 2>&1
"%WORK%\sw-test.exe" >"%WORK%\sw-test.txt" 2>&1
if !errorlevel! == 0 (call :res exe-in-user-folder PASS "programs can run from your own folders") else (
  call :res exe-in-user-folder FAIL "a program in your own folder was blocked - portable apps likely blocked too"
  for /f "usebackq delims=" %%l in ("%WORK%\sw-test.txt") do >>"%LOG%" echo     %%l
)
del "%WORK%\sw-test.exe" "%WORK%\sw-test.txt" >nul 2>&1

(echo @echo ok)>"%WORK%\sw-test.cmd"
call "%WORK%\sw-test.cmd" >nul 2>&1 && (call :res cmd-in-user-folder PASS "batch files run from your own folders") || call :res cmd-in-user-folder FAIL "batch files blocked in your own folders"
del "%WORK%\sw-test.cmd" >nul 2>&1

rem Files from a downloaded zip carry a "came from the internet" mark; with this laptop's PowerShell policy
rem that makes Windows stop and ask before each script, which a non-interactive check cannot answer.
rem Clear the mark on this folder's own files (yours to do, no admin).
dir /r "%~f0" 2>nul | find "Zone.Identifier" >nul && (
  powershell.exe -NoProfile -NonInteractive -Command "Get-ChildItem -LiteralPath '%HERE%.' -Recurse -File | Unblock-File" >nul 2>&1
  dir /r "%~f0" 2>nul | find "Zone.Identifier" >nul && call :res downloaded-mark WARN "files still marked as downloaded - right-click the zip, Properties, Unblock, then re-extract" || call :res downloaded-mark INFO "cleared the downloaded-file mark on this folder"
)

rem ---------------------------------------------------------------- 2. what runtimes exist
call :section "2. Ways to run things"
set "PS="
if exist "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" set "PS=powershell.exe"
if defined PS (call :res tool-powershell PASS "Windows PowerShell present") else (call :res tool-powershell FAIL "Windows PowerShell missing")
where pwsh >nul 2>&1 && call :res tool-pwsh INFO "PowerShell 7 present (not needed)"
set "CSC=%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "!CSC!" set "CSC=%SystemRoot%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if exist "!CSC!" (call :res tool-csc PASS "built-in C# compiler present") else (call :res tool-csc WARN "no built-in C# compiler" & set "CSC=")
where cscript >nul 2>&1 && (call :res tool-cscript PASS "Windows Script Host present") || call :res tool-cscript WARN "Windows Script Host missing"
where curl >nul 2>&1 && (call :res tool-curl PASS "curl present") || call :res tool-curl WARN "curl missing"
where python >nul 2>&1 && call :res tool-python INFO "Python on PATH (another option for the bridge)"
where py >nul 2>&1 && call :res tool-py INFO "Python launcher present (another option for the bridge)"

rem Portable Node ships in this repo as the official zip; unpack it once into the work folder (built-in tar, no admin).
for %%z in ("%HERE%node-v*-win-x64.zip") do if not exist "%WORK%\%%~nz\node.exe" (
  echo   unpacking %%~nxz ...
  tar -xf "%%z" -C "%WORK%" >nul 2>&1 && (call :res node-unzip PASS "unpacked %%~nxz") || call :res node-unzip FAIL "could not unpack %%~nxz - extract it by hand into a folder named node here"
)
set "NODE="
if exist "%HERE%node\node.exe" set "NODE=%HERE%node\node.exe"
if not defined NODE for /d %%d in ("%WORK%\node-v*") do if exist "%%d\node.exe" set "NODE=%%d\node.exe"
if not defined NODE for /d %%d in ("%HERE%node-v*") do if exist "%%d\node.exe" set "NODE=%%d\node.exe"
if not defined NODE if exist "%HERE%..\node\node.exe" set "NODE=%HERE%..\node\node.exe"
if not defined NODE for /f "delims=" %%n in ('where node 2^>nul') do if not defined NODE set "NODE=%%n"
if defined NODE (call :res node-found PASS "!NODE!") else (call :res node-found WARN "no node.exe found - unzip the Windows Node.js zip into a folder named node next to this file, then run again")

rem ---------------------------------------------------------------- 3. network
call :section "3. Internet (curl)"
for /f "tokens=2,* delims=:" %%p in ('netsh winhttp show proxy 2^>nul ^| find /i "proxy server"') do >>"%LOG%" echo   system proxy:%%p
if defined HTTPS_PROXY >>"%LOG%" echo   HTTPS_PROXY is set
for %%h in (api.groupme.com cdn.jsdelivr.net github.com) do (
  set "CODE=000"
  for /f "delims=" %%c in ('curl -s -o nul -w "%%{http_code}" --max-time 12 https://%%h/ 2^>nul') do set "CODE=%%c"
  if "!CODE!" == "000" (call :res curl-%%h WARN "no answer - blocked, offline, or needs a proxy") else (call :res curl-%%h PASS "reachable, HTTP !CODE!")
)

rem ---------------------------------------------------------------- 4. portable Node (the texting server)
call :section "4. Portable Node (texting server)"
if defined NODE (
  dir /r "!NODE!" 2>nul | find "Zone.Identifier" >nul && call :res node-download-mark WARN "node.exe is marked as downloaded - Unblock the zip before extracting"
  "!NODE!" "%HERE%node-check.js" "%WORK%" >"%WORK%\node-out.txt" 2>&1
  set "NERR=!errorlevel!"
  findstr /b "RESULT" "%WORK%\node-out.txt" >nul
  if errorlevel 1 (
    call :res node-run FAIL "node.exe would not run (exit !NERR!) - see the lines below"
    for /f "usebackq delims=" %%l in ("%WORK%\node-out.txt") do >>"%LOG%" echo     %%l
  ) else (
    type "%WORK%\node-out.txt" >>"%LOG%"
    for /f "usebackq tokens=2,3,*" %%a in (`findstr /b "RESULT" "%WORK%\node-out.txt"`) do echo   [%%b] %%a %%c
  )
  del "%WORK%\node-out.txt" >nul 2>&1
) else (
  >>"%LOG%" echo   skipped - no node.exe
)

rem ---------------------------------------------------------------- 5. PowerShell (main bridge option)
call :section "5. PowerShell (bridge option A)"
if defined PS (
  set "LM=unknown"
  for /f "delims=" %%m in ('powershell.exe -NoProfile -NonInteractive -Command "$ExecutionContext.SessionState.LanguageMode" 2^>nul') do set "LM=%%m"
  if /i "!LM!" == "FullLanguage" (call :res ps-language PASS "FullLanguage") else (call :res ps-language FAIL "!LM! - PowerShell is restricted, Bluetooth calls will not work from it")
  powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%HERE%check-windows.ps1" -Log "%LOG%" -Work "%WORK%" -Mode "%MODE%"
  call :has "RESULT ps-script PASS" || call :res ps-script FAIL "check-windows.ps1 did not run - probably blocked by policy"
) else (
  >>"%LOG%" echo   skipped - no PowerShell
)

rem ---------------------------------------------------------------- 6. Windows Script Host (fallback checks)
call :section "6. Windows Script Host (fallback checks)"
where cscript >nul 2>&1 && (
  cscript //nologo //E:JScript "%HERE%check-fallback.js" "%LOG%"
  if errorlevel 1 call :res js-script WARN "Windows Script Host is disabled or failed"
) || >>"%LOG%" echo   skipped - no cscript

rem ---------------------------------------------------------------- 7. C# built with the Windows compiler (bridge option B)
call :section "7. Small compiled program (bridge option B)"
if defined CSC (
  set "REFS="
  for %%f in ("%SystemRoot%\System32\WinMetadata\*.winmd") do set REFS=!REFS! /r:"%%f"
  for %%d in ("!CSC!") do set "NETDIR=%%~dpd"
  for %%a in (System.Runtime.dll System.Runtime.InteropServices.WindowsRuntime.dll) do if exist "!NETDIR!%%a" set REFS=!REFS! /r:"!NETDIR!%%a"
  "!CSC!" /nologo /optimize /out:"%WORK%\btcheck.exe" !REFS! "%HERE%btcheck.cs" >"%WORK%\csc-out.txt" 2>&1
  if exist "%WORK%\btcheck.exe" (
    call :res cs-compile PASS "the built-in C# compiler works"
    set "CSMODE=!MODE!"
    findstr /b /c:"RESULT ps-phone-map PASS" "%LOG%" >nul && set "CSMODE=nophone"
    "%WORK%\btcheck.exe" "%LOG%" "!CSMODE!"
    call :has "RESULT cs-exe-runs PASS" || call :res cs-exe-runs FAIL "the compiled program was blocked from running"
    del "%WORK%\btcheck.exe" >nul 2>&1
  ) else (
    call :res cs-compile FAIL "compile failed - see the lines below"
    for /f "usebackq delims=" %%l in ("%WORK%\csc-out.txt") do >>"%LOG%" echo     %%l
  )
  del "%WORK%\csc-out.txt" >nul 2>&1
) else (
  >>"%LOG%" echo   skipped - no C# compiler
)

rem ---------------------------------------------------------------- summary
call :section "SUMMARY"
call :verdict
>>"%LOG%" echo.
>>"%LOG%" echo Finished: %DATE% %TIME%
echo.
echo Done. Log saved to: %LOG%
start "" notepad "%LOG%" >nul 2>&1
pause
exit /b 0

rem ================================================================ helpers
:section
>>"%LOG%" echo.
>>"%LOG%" echo ===== %~1 =====
echo.
echo == %~1
exit /b

:res
>>"%LOG%" echo RESULT %~1 %~2 %~3
echo   [%~2] %~1 %~3
exit /b

:has
rem :has "text" -> errorlevel 0 if the log contains a line starting with it
findstr /b /c:"%~1" "%LOG%" >nul
exit /b

:say
>>"%LOG%" echo %~1
echo %~1
exit /b

:verdict
set "V=BLOCKED - see the FAIL lines above"
call :has "RESULT node-found WARN" && set "V=NOT TESTED YET - put the Node.js zip in a folder named node here and run again"
call :has "RESULT node-run PASS" && set "V=CAN RUN - portable Node works"
call :say "Texting server ........ !V!"

set "V=BLOCKED or not tested - see the FAIL/WARN lines above"
call :has "RESULT ps-phone-found FAIL" && set "V=NOT TESTED - pair the iPhone in Settings, Bluetooth and devices, then run again"
call :has "RESULT cs-phone-found FAIL" && set "V=NOT TESTED - pair the iPhone in Settings, Bluetooth and devices, then run again"
if /i "%MODE%" == "nophone" set "V=NOT TESTED - you ran with nophone"
call :has "RESULT cs-phone-map PASS" && set "V=CAN RUN - as a small compiled program (option B)"
call :has "RESULT ps-phone-map PASS" && set "V=CAN RUN - as a PowerShell script (option A)"
call :say "iPhone bridge ......... !V!"

set "V=NO - would need starting by hand"
call :has "RESULT startup-folder PASS" && set "V=YES - per-user Startup folder"
call :say "Start at login ........ !V!"

set "V=NOT REACHABLE - check proxy / network"
call :has "RESULT curl-api.groupme.com PASS" && set "V=REACHABLE (curl)"
call :has "RESULT ps-net-api.groupme.com PASS" && set "V=REACHABLE"
call :has "RESULT node-groupme PASS" && set "V=REACHABLE (also from Node)"
call :say "GroupMe from laptop ... !V!"
call :has "RESULT node-groupme FAIL" && call :say "  note: Node could not reach GroupMe even though Windows can - a proxy setting would be needed for the server"
exit /b
