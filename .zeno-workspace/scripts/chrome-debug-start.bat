@echo off
REM Chrome with remote debugging for OpenClaw (Windows)
REM Run this before using browser automation in OpenClaw

set CHROME_DIR=%USERPROFILE%\chrome-openclaw
set CHROME_EXE="C:\Program Files\Google\Chrome\Application\chrome.exe"

REM Kill existing debug instance
taskkill /F /IM chrome.exe /T >nul 2>&1
timeout /t 2 /nobreak >nul

REM Launch Chrome with remote debugging
start "" %CHROME_EXE% --remote-debugging-port=9222 --user-data-dir="%CHROME_DIR%"

timeout /t 4 /nobreak >nul

REM Write DevToolsActivePort (Chrome 146+ doesn't auto-create this)
for /f "tokens=*" %%i in ('curl -s --noproxy localhost,127.0.0.1 http://127.0.0.1:9222/json/version ^| python -c "import sys,json; v=json.load(sys.stdin); print(v[\"webSocketDebuggerUrl\"].split(\"9222\")[1])"') do set WS_PATH=%%i

if "%WS_PATH%"=="" (
    echo ERROR: Chrome failed to start or DevTools not available
    exit /b 1
)

(echo 9222 & echo %WS_PATH%) > "%CHROME_DIR%\DevToolsActivePort"
echo Chrome debug mode ready (port 9222)
echo WS path: %WS_PATH%
