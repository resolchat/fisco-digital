@echo off
REM Script otimizado para enviar alteracoes para o GitHub
echo.
echo === SINCRONIZANDO COM GITHUB ===
echo.

echo Adicionando alteracoes...
git add .

echo Criando commit...
set /p msg="Digite a mensagem do commit (ou pressione Enter para 'Update'): "
if "%msg%"=="" set msg=Update

git commit -m "%msg%"

echo Enviando para o branch main...
git push origin main

echo.
echo === CONCLUIDO! SITE ATUALIZADO NO GITHUB PAGES ===
echo.
pause
