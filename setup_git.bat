@echo off
REM Script para inicializar o repositório git e commitar arquivos iniciais do Fisco Digital

echo Inicializando repositorio Git...
git init

echo Adicionando arquivos...
git add .

echo Commitando alteracoes...
git commit -m "Commit inicial: Arquivos do projeto Fisco Digital"

echo.
echo Configuracao do repositorio local completa!
echo.
echo Para enviar para o GitHub, siga estes passos:
echo 1. Crie um novo repositorio no GitHub (https://github.com/new)
echo 2. Copie a URL do repositorio (ex: https://github.com/seu-usuario/repo.git)
echo 3. Execute os seguintes comandos no terminal:
echo    git remote add origin <SUA_URL_DO_REPO>
echo    git branch -M main
echo    git push -u origin main
echo.
pause
