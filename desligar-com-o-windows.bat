@echo off
rem ==========================================================================
rem  JOGA BONITO - parar de ligar com o Windows
rem  Toda a logica fica em Site\ferramentas\jogabonito.ps1
rem ==========================================================================
chcp 65001 >nul
title Joga Bonito - parar de ligar com o Windows
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Site\ferramentas\jogabonito.ps1" -Acao DesligarComWindows %*
timeout /t 4 >nul
