@echo off
rem Unified Gateway Watchdog — 统一看门狗
rem 每 5 分钟由 Windows 计划任务调用
D:\zeno\hermes-agent\venv\Scripts\python.exe D:\zeno\openclaw\scripts\unified-watchdog.py >> "%USERPROFILE%\unified-watchdog.log" 2>&1
