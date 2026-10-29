@echo off
rem ==========================================================================
rem  JOGA BONITO - ligar a loja (API + banco + site)
rem  Toda a logica fica em Site\ferramentas\jogabonito.ps1
rem ==========================================================================
chcp 65001 >nul
title Joga Bonito - ligar a loja (API + banco + site)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Site\ferramentas\jogabonito.ps1" -Acao Iniciar %*
if errorlevel 1 (echo. & pause) else (timeout /t 8 >nul)
