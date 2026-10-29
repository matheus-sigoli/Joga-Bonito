@echo off
rem ==========================================================================
rem  JOGA BONITO - roda todos os testes (unitarios, integracao, E2E,
rem  aceitacao contra a API real e app Flutter) e mostra um resumo.
rem  Opcoes: -PularFlutter   -UrlApk https://<loja>.azurewebsites.net
rem ==========================================================================
chcp 65001 >nul
title Joga Bonito - testes
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Site\ferramentas\testar-tudo.ps1" %*
echo.
pause
