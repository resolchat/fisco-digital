@echo off
echo =========================================
echo   Fisco Digital - Deploy Automatizado
echo =========================================

echo 1. Verificando instalacao do Supabase CLI...
call npm list -g supabase >nul 2>&1
if %errorlevel% neq 0 (
    echo Instalando Supabase CLI...
    call npm install -g supabase
)

echo.
echo 2. Fazendo login no Supabase...
echo (Se pedir token, copie de https://supabase.com/dashboard/account/tokens)
call npx supabase login

echo.
echo 3. Vinculando ao projeto Fisco Digital...
call npx supabase link --project-ref rswkvekfmrmgkdmqoygb --password "SENHA_DO_DB_AQUI" 
REM Nota: A senha do DB geralmente eh pedida interativamente.

echo.
echo 4. Fazendo Deploy das Edge Functions...
echo ---------------------------------------
echo Deploying parse_xml...
call npx supabase functions deploy parse_xml --no-verify-jwt
echo.
echo Deploying run_automations...
call npx supabase functions deploy run_automations --no-verify-jwt
echo.
echo Deploying run_reports...
call npx supabase functions deploy run_reports --no-verify-jwt
echo.
echo Deploying public_shared_link_handler...
call npx supabase functions deploy public_shared_link_handler --no-verify-jwt

echo.
echo =========================================
echo   Deploy Concluido!
echo =========================================
pause
