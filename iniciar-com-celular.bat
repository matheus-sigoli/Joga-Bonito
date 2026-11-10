@echo off
rem ==========================================================================
rem  JOGA BONITO - ligar a loja PARA O CELULAR (app na mesma rede Wi-Fi)
rem  Abre a API para a rede local, libera o firewall (pede administrador uma
rem  vez) e mostra o endereco para o app. O modo fica lembrado: para voltar a
rem  aceitar so este PC, rode  iniciar-projeto.bat -SemRede
rem  Toda a logica fica em Site\ferramentas\jogabonito.ps1
rem ==========================================================================
chcp 65001 >nul
title Joga Bonito - ligar a loja para o celular
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Site\ferramentas\jogabonito.ps1" -Acao Iniciar -Rede %*
echo.
echo  Deixe esta janela aberta enquanto testa o app (ou feche: a API continua ligada).
pause
