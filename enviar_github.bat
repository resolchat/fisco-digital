@echo off
REM Script para enviar codigo para o GitHub usando o caminho absoluto do Git

set GIT_PATH="C:\Program Files\Git\cmd\git.exe"

echo Configurando repositorio remoto...
%GIT_PATH% remote remove origin 2>nul
%GIT_PATH% remote add origin https://github.com/resolchat/fisco-digital.git

echo Renomeando branch para main...
%GIT_PATH% branch -M main

echo.
echo Enviando arquivos...
echo ATENCAO: Uma janela de login do GitHub pode se abrir. Faca o login nela.
echo.
%GIT_PATH% push -u origin main

echo.
pause
