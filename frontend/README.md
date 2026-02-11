# Guia de Integração Frontend

Para usar o frontend que você criou no Stitch junto com o backend Supabase que criamos:

1. **Obtenha as credenciais do Supabase**:
   - Vá no painel do seu projeto Supabase.
   - Em **Settings > API**, copie a **Project URL** e a **anon public key**.

2. **Configure os arquivos**:
   - Abra `frontend/login.html` e `frontend/dashboard.html`.
   - Substitua `'SUA_SUPABASE_URL_AQUI'` pela sua Project URL.
   - Substitua `'SUA_SUPABASE_ANON_KEY_AQUI'` pela sua Anon Key.

3. **Como Rodar**:
   - Para arquivos HTML simples com módulos JS e Auth, é recomendável rodar um pequeno servidor local (para evitar bloqueios de cookies/CORS do navegador).
   - Se tiver Node.js instalado, abra o terminal na pasta `frontend` e rode:
     ```bash
     npx http-server .
     ```
   - Acesse `http://127.0.0.1:8080/login.html` no navegador.

4. **Expandindo o App**:
   - Use o padrão mostrado no `dashboard.html` para criar novas páginas.
   - Sempre verifique a sessão no topo do arquivo (`checkSession`).
   - Use `supabase.from('tabela').select/insert/update` para manipular dados.
