@echo off
rem 每次起服前备份 .log 现有内容到 .log\backup\时间戳，只保留最新 2 个备份目录
set "LOG_DIR=.log"
set "BACKUP_ROOT_DIR=%LOG_DIR%\backup"

rem 确保日志目录与备份目录存在
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
if not exist "%BACKUP_ROOT_DIR%" mkdir "%BACKUP_ROOT_DIR%"

rem 生成本次启动的备份目录名
for /f %%T in ('powershell -NoProfile -Command "(Get-Date).ToString(\"yyyyMMdd_HHmmss\")"') do set "BACKUP_TIMESTAMP=%%T"

rem 将 .log 下除 backup 外的内容移动到本次备份目录
for /f "delims=" %%I in ('dir /b /a "%LOG_DIR%" ^| findstr /v /i "^backup$"') do (
    if not exist "%BACKUP_ROOT_DIR%\%BACKUP_TIMESTAMP%" mkdir "%BACKUP_ROOT_DIR%\%BACKUP_TIMESTAMP%"
    move "%LOG_DIR%\%%I" "%BACKUP_ROOT_DIR%\%BACKUP_TIMESTAMP%\" >nul
)

rem 仅保留最新两个备份目录
for /f "skip=2 delims=" %%D in ('dir /b /ad /o-n "%BACKUP_ROOT_DIR%" 2^>nul') do rd /s /q "%BACKUP_ROOT_DIR%\%%D"
.\config\startGame.bat
