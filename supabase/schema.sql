-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Enums
DO $$ BEGIN
    CREATE TYPE user_role AS ENUM ('admin', 'fiscal', 'driver', 'viewer');
    CREATE TYPE document_type AS ENUM ('nfe', 'nfce', 'cte', 'mdfe', 'outros');
    CREATE TYPE document_status AS ENUM ('pendente', 'processado', 'entregue', 'cancelado', 'erro');
    CREATE TYPE document_origin AS ENUM ('manual', 'import_xml', 'upload_massa', 'api');
    CREATE TYPE delivery_status AS ENUM ('aguardando', 'coletado', 'em_rota', 'entregue', 'atrasado', 'cancelado');
    CREATE TYPE automation_trigger_type AS ENUM ('documento_criado', 'status_alterado', 'entrega_status', 'cliente_criado');
    CREATE TYPE automation_action_type AS ENUM ('criar_entrega', 'criar_link', 'notificar_email', 'webhook');
    CREATE TYPE report_periodicity AS ENUM ('daily', 'weekly', 'monthly');
    CREATE TYPE report_format AS ENUM ('csv', 'pdf');
    CREATE TYPE webhook_status AS ENUM ('pending', 'sent', 'error');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Companies
CREATE TABLE IF NOT EXISTS companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    nome TEXT NOT NULL,
    cnpj TEXT UNIQUE NOT NULL,
    email TEXT,
    telefone TEXT,
    endereco TEXT,
    cidade TEXT,
    estado TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS company_settings (
    company_id UUID PRIMARY KEY REFERENCES companies(id) ON DELETE CASCADE,
    preferencias JSONB DEFAULT '{}'::JSONB,
    integracoes JSONB DEFAULT '{}'::JSONB,
    logo_url TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Profiles (Users)
CREATE TABLE IF NOT EXISTS profiles (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    company_id UUID REFERENCES companies(id) ON DELETE CASCADE,
    nome TEXT NOT NULL,
    email TEXT NOT NULL,
    role user_role NOT NULL DEFAULT 'viewer',
    ativo BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Clients
CREATE TABLE IF NOT EXISTS clients (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    nome_razao TEXT NOT NULL,
    cpf_cnpj TEXT,
    email TEXT,
    telefone TEXT,
    cep TEXT,
    endereco TEXT,
    cidade TEXT,
    estado TEXT,
    observacoes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_clients_company_id ON clients(company_id);
CREATE INDEX IF NOT EXISTS idx_clients_cpf_cnpj ON clients(company_id, cpf_cnpj);

-- Documents
CREATE TABLE IF NOT EXISTS documents (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    client_id UUID REFERENCES clients(id) ON DELETE SET NULL,
    tipo document_type NOT NULL,
    numero TEXT,
    serie TEXT,
    chave_acesso TEXT,
    emissao_data DATE,
    valor_total NUMERIC(15, 2),
    status document_status DEFAULT 'pendente',
    origem document_origin DEFAULT 'manual',
    xml_url TEXT,
    pdf_url TEXT,
    metadata_json JSONB DEFAULT '{}'::JSONB,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(company_id, chave_acesso)
);

CREATE INDEX IF NOT EXISTS idx_documents_company_id ON documents(company_id);
CREATE INDEX IF NOT EXISTS idx_documents_status ON documents(company_id, status);

-- Shared Links
CREATE TABLE IF NOT EXISTS shared_links (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    token TEXT UNIQUE NOT NULL DEFAULT encode(gen_random_bytes(16), 'hex'),
    expires_at TIMESTAMPTZ,
    permissions JSONB DEFAULT '{"view": true, "download": false}'::JSONB,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    revoked_at TIMESTAMPTZ
);

-- Deliveries
CREATE TABLE IF NOT EXISTS deliveries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    driver_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    codigo_rastreio TEXT,
    status delivery_status DEFAULT 'aguardando',
    agendado_para TIMESTAMPTZ,
    observacoes TEXT,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_deliveries_company_id ON deliveries(company_id);
CREATE INDEX IF NOT EXISTS idx_deliveries_driver_id ON deliveries(driver_id);

CREATE TABLE IF NOT EXISTS delivery_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    delivery_id UUID NOT NULL REFERENCES deliveries(id) ON DELETE CASCADE,
    status delivery_status NOT NULL,
    latitude NUMERIC(10, 8),
    longitude NUMERIC(11, 8),
    prova_url TEXT,
    note TEXT,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Automation
CREATE TABLE IF NOT EXISTS automation_rules (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    nome TEXT NOT NULL,
    ativo BOOLEAN DEFAULT TRUE,
    trigger_type automation_trigger_type NOT NULL,
    trigger_filters JSONB DEFAULT '{}'::JSONB,
    action_type automation_action_type NOT NULL,
    action_config JSONB DEFAULT '{}'::JSONB,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS webhooks_outbox (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    rule_id UUID REFERENCES automation_rules(id) ON DELETE SET NULL,
    payload_json JSONB NOT NULL,
    status webhook_status DEFAULT 'pending',
    attempts INT DEFAULT 0,
    last_error TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    sent_at TIMESTAMPTZ
);

-- Reports
CREATE TABLE IF NOT EXISTS scheduled_reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    nome TEXT NOT NULL,
    ativo BOOLEAN DEFAULT TRUE,
    periodicidade report_periodicity NOT NULL,
    destinatarios TEXT[],
    filtros JSONB DEFAULT '{}'::JSONB,
    formato report_format DEFAULT 'csv',
    next_run_at TIMESTAMPTZ,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS report_runs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    report_id UUID REFERENCES scheduled_reports(id) ON DELETE CASCADE,
    status TEXT,
    file_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Audit Logs
CREATE TABLE IF NOT EXISTS audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    actor_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    entity_type TEXT NOT NULL,
    entity_id UUID NOT NULL,
    action TEXT NOT NULL,
    metadata_json JSONB DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS & Security -------------------------------------------------------------

-- Enable RLS
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE company_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE clients ENABLE ROW LEVEL SECURITY;
ALTER TABLE documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE shared_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE delivery_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE automation_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE webhooks_outbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE scheduled_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE report_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

-- Functions
CREATE OR REPLACE FUNCTION get_my_company_id()
RETURNS UUID AS $$
    SELECT company_id FROM profiles WHERE user_id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1 FROM profiles 
        WHERE user_id = auth.uid() AND role = 'admin'
    );
$$ LANGUAGE sql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION is_fiscal_or_admin()
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1 FROM profiles 
        WHERE user_id = auth.uid() AND role IN ('admin', 'fiscal')
    );
$$ LANGUAGE sql SECURITY DEFINER;

-- Policies

-- Companies: Users can view their own company
CREATE POLICY "Users view own company" ON companies
    FOR SELECT USING (id = get_my_company_id());

-- Company Settings: Admin only write, users read
CREATE POLICY "Users view company settings" ON company_settings
    FOR SELECT USING (company_id = get_my_company_id());
CREATE POLICY "Admins edit company settings" ON company_settings
    FOR UPDATE USING (company_id = get_my_company_id() AND is_admin());

-- Profiles: View colleagues, Admin edits
CREATE POLICY "View colleagues" ON profiles
    FOR SELECT USING (company_id = get_my_company_id());
CREATE POLICY "Admins manage profiles" ON profiles
    FOR ALL USING (company_id = get_my_company_id() AND is_admin());

-- Clients: Viewer/Driver Read-only, Fiscal/Admin All
CREATE POLICY "View clients" ON clients
    FOR SELECT USING (company_id = get_my_company_id());
CREATE POLICY "Manage clients" ON clients
    FOR ALL USING (company_id = get_my_company_id() AND is_fiscal_or_admin());

-- Documents: 
CREATE POLICY "Access documents" ON documents
    FOR ALL USING (
        company_id = get_my_company_id() 
        AND is_fiscal_or_admin()
    );

CREATE POLICY "Drivers view assigned documents" ON documents
    FOR SELECT USING (
        company_id = get_my_company_id()
        AND EXISTS (
            SELECT 1 FROM profiles p 
            WHERE p.user_id = auth.uid() AND p.role = 'driver'
        )
        AND EXISTS (
            SELECT 1 FROM deliveries d 
            WHERE d.document_id = documents.id AND d.driver_id = auth.uid()
        )
    );

CREATE POLICY "Viewers view all documents" ON documents
    FOR SELECT USING (
        company_id = get_my_company_id()
        AND EXISTS (
            SELECT 1 FROM profiles p 
            WHERE p.user_id = auth.uid() AND p.role = 'viewer'
        )
    );

-- Deliveries
CREATE POLICY "Manage deliveries" ON deliveries
    FOR ALL USING (
        company_id = get_my_company_id() AND is_fiscal_or_admin()
    );

CREATE POLICY "Drivers view assigned deliveries" ON deliveries
    FOR SELECT USING (
        company_id = get_my_company_id() AND driver_id = auth.uid()
    );
    
CREATE POLICY "Drivers update own delivery status" ON deliveries
    FOR UPDATE USING (
        company_id = get_my_company_id() AND driver_id = auth.uid()
    );

-- Delivery Events
CREATE POLICY "Manage delivery events" ON delivery_events
    FOR ALL USING (company_id = get_my_company_id());

-- Shared Links, Automation, Reports, Audit Logs -> Admin/Fiscal usually
CREATE POLICY "Manage shared links" ON shared_links
    FOR ALL USING (company_id = get_my_company_id() AND is_fiscal_or_admin());

CREATE POLICY "Manage automation" ON automation_rules
    FOR ALL USING (company_id = get_my_company_id() AND is_fiscal_or_admin());

CREATE POLICY "Manage reports" ON scheduled_reports
    FOR ALL USING (company_id = get_my_company_id() AND is_fiscal_or_admin());
    
CREATE POLICY "View audit logs" ON audit_logs
    FOR SELECT USING (company_id = get_my_company_id() AND is_admin());

-- Storage Buckets Setup (Supabase specific)
INSERT INTO storage.buckets (id, name, public) VALUES 
('documents', 'documents', false),
('reports', 'reports', false),
('proofs', 'proofs', false)
ON CONFLICT DO NOTHING;

-- Storage Policies
CREATE POLICY "Company Access Documents" ON storage.objects
FOR ALL USING (
    bucket_id = 'documents' 
    AND (storage.foldername(name))[1] = get_my_company_id()::text
);

CREATE POLICY "Company Access Proofs" ON storage.objects
FOR ALL USING (
    bucket_id = 'proofs'
    AND (storage.foldername(name))[1] = get_my_company_id()::text
);

-- Triggers -------------------------------------------------------------------

-- Updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

DO $$ 
DECLARE
    t text;
BEGIN
    FOR t IN 
        SELECT table_name FROM information_schema.columns WHERE column_name = 'updated_at' AND table_schema = 'public'
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS update_%I_modtime ON %I', t, t);
        EXECUTE format('CREATE TRIGGER update_%I_modtime BEFORE UPDATE ON %I FOR EACH ROW EXECUTE PROCEDURE update_updated_at_column()', t, t);
    END LOOP;
END $$;

-- Audit Log Trigger
CREATE OR REPLACE FUNCTION log_audit_event()
RETURNS TRIGGER AS $$
DECLARE
    cid UUID;
    act_user UUID;
BEGIN
    IF (TG_OP = 'DELETE') THEN
        cid := OLD.company_id;
    ELSE
        cid := NEW.company_id;
    END IF;
    
    act_user := auth.uid();
    
    INSERT INTO audit_logs (company_id, actor_user_id, entity_type, entity_id, action, metadata_json)
    VALUES (
        cid,
        act_user,
        TG_TABLE_NAME,
        COALESCE(NEW.id, OLD.id),
        TG_OP,
        jsonb_build_object('old', row_to_json(OLD), 'new', row_to_json(NEW))
    );
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER audit_documents_trigger AFTER INSERT OR UPDATE OR DELETE ON documents
FOR EACH ROW EXECUTE PROCEDURE log_audit_event();

CREATE TRIGGER audit_deliveries_trigger AFTER INSERT OR UPDATE OR DELETE ON deliveries
FOR EACH ROW EXECUTE PROCEDURE log_audit_event();

CREATE TRIGGER audit_rules_trigger AFTER INSERT OR UPDATE OR DELETE ON automation_rules
FOR EACH ROW EXECUTE PROCEDURE log_audit_event();

-- Automation Queue (NEW SECTION)
CREATE TABLE IF NOT EXISTS automation_queue (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    event_type automation_trigger_type NOT NULL,
    entity_id UUID NOT NULL,
    payload JSONB DEFAULT '{}'::JSONB,
    status TEXT DEFAULT 'pending', -- pending, processing, completed, error
    processed_at TIMESTAMPTZ,
    error_log TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_automation_queue_status ON automation_queue(status);

-- Trigger Function to Enqueue Events
CREATE OR REPLACE FUNCTION enqueue_automation_event()
RETURNS TRIGGER AS $$
DECLARE
    etype automation_trigger_type;
    cid UUID;
BEGIN
    IF (TG_OP = 'DELETE') THEN
        RETURN OLD;
    END IF;
    
    cid := NEW.company_id;
    
    IF (TG_TABLE_NAME = 'documents' AND TG_OP = 'INSERT') THEN
        etype := 'documento_criado';
    ELSIF (TG_TABLE_NAME = 'documents' AND TG_OP = 'UPDATE' AND OLD.status != NEW.status) THEN
        etype := 'status_alterado';
    ELSIF (TG_TABLE_NAME = 'delivery_events' AND TG_OP = 'INSERT') THEN
        etype := 'entrega_status';
    ELSIF (TG_TABLE_NAME = 'clients' AND TG_OP = 'INSERT') THEN
        etype := 'cliente_criado';
    ELSE
        RETURN NEW;
    END IF;

    -- Only insert if there is at least one active rule for this trigger in this company
    PERFORM 1 FROM automation_rules 
    WHERE company_id = cid AND trigger_type = etype AND ativo = true;
    
    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    INSERT INTO automation_queue (company_id, event_type, entity_id, payload)
    VALUES (cid, etype, NEW.id, row_to_json(NEW));
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Apply Triggers
DROP TRIGGER IF EXISTS trg_enqueue_document_insert ON documents;
CREATE TRIGGER trg_enqueue_document_insert AFTER INSERT ON documents
FOR EACH ROW EXECUTE PROCEDURE enqueue_automation_event();

DROP TRIGGER IF EXISTS trg_enqueue_document_update ON documents;
CREATE TRIGGER trg_enqueue_document_update AFTER UPDATE ON documents
FOR EACH ROW EXECUTE PROCEDURE enqueue_automation_event();

DROP TRIGGER IF EXISTS trg_enqueue_delivery_event ON delivery_events;
CREATE TRIGGER trg_enqueue_delivery_event AFTER INSERT ON delivery_events
FOR EACH ROW EXECUTE PROCEDURE enqueue_automation_event();

DROP TRIGGER IF EXISTS trg_enqueue_client_insert ON clients;
CREATE TRIGGER trg_enqueue_client_insert AFTER INSERT ON clients
FOR EACH ROW EXECUTE PROCEDURE enqueue_automation_event();
