@echo off
rem ==========================================================================
rem  JOGA BONITO - desligar a API
rem  Toda a logica fica em Site\ferramentas\jogabonito.ps1
rem ==========================================================================
chcp 65001 >nul
title Joga Bonito - desligar a API
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Site\ferramentas\jogabonito.ps1" -Acao Parar %*
timeout /t 4 >nul
