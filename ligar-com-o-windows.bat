@echo off
rem ==========================================================================
rem  JOGA BONITO - ligar a API junto com o Windows
rem  Toda a logica fica em Site\ferramentas\jogabonito.ps1
rem ==========================================================================
chcp 65001 >nul
title Joga Bonito - ligar a API junto com o Windows
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Site\ferramentas\jogabonito.ps1" -Acao LigarComWindows %*
if errorlevel 1 (echo. & pause) else (timeout /t 8 >nul)
