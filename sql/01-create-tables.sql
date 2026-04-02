-- =============================================
-- 01_create_tables.sql
-- Tablas base — almacenan los datos de los CSVs
-- Ejecutar PRIMERO porque las demás tablas
-- dependen de alegra_users (foreign keys)
-- =============================================

-- ─────────────────────────────────────────────
-- alegra_users
-- Cada fila es un cliente de Alegra.
-- Es la tabla principal. Todas las demás
-- referencian a esta por user_id.
-- Fuente: alegra_users.csv (2,000 registros)
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS alegra_users (
    user_id          TEXT PRIMARY KEY,           -- Formato: 'USR-10000'
    country          TEXT NOT NULL,              -- Colombia, México, Costa Rica, Panamá, República Dominicana
    plan             TEXT NOT NULL,              -- Free, Pyme, Plus, Pro
    signup_date      DATE NOT NULL,              -- Fecha de registro del cliente
    source           TEXT NOT NULL,              -- Canal de adquisición: Organic, Paid, Referral, Social, Partner_Accountant
    mrr_usd          NUMERIC(10,2) NOT NULL,    -- Ingreso mensual recurrente en USD (0 para Free, hasta 150)
    churn_risk_score NUMERIC(4,2) NOT NULL,     -- Score de riesgo precalculado por Alegra (0.05 a 0.95)
    features_count   INTEGER NOT NULL            -- Cantidad de features que el usuario ha tocado (1 a 10)
);

-- ─────────────────────────────────────────────
-- alegra_feature_usage
-- Cada fila es una feature que un usuario ha
-- tocado. Un usuario puede tener múltiples filas
-- (una por cada feature que usa).
-- Fuente: alegra_feature_usage.csv (7,022 registros)
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS alegra_feature_usage (
    id              SERIAL PRIMARY KEY,          -- ID auto-incremental (no viene en el CSV)
    user_id         TEXT NOT NULL,               -- FK → alegra_users
    feature         TEXT NOT NULL,               -- Nombre: Facturación electrónica, Inventario, Nómina, etc. (9 posibles)
    adoption_level  TEXT NOT NULL,               -- Nivel de adopción: activated → used_1x → used_5x → used_10x → power_user
    last_used_date  DATE NOT NULL,               -- Última vez que el usuario usó esta feature
    CONSTRAINT fk_feature_user FOREIGN KEY (user_id) REFERENCES alegra_users(user_id)
);

-- ─────────────────────────────────────────────
-- alegra_support_tickets
-- Cada fila es un ticket de soporte.
-- Un usuario puede tener 0 o múltiples tickets.
-- Los campos resolved_date, resolution_hours y
-- csat_score son NULL para tickets sin resolver.
-- Fuente: alegra_support_tickets.csv (3,500 registros)
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS alegra_support_tickets (
    ticket_id        TEXT PRIMARY KEY,            -- Formato: 'TKT-20000'
    user_id          TEXT NOT NULL,               -- FK → alegra_users
    category         TEXT NOT NULL,               -- Bug, Feature_Request, Integration, Onboarding, Performance
    priority         TEXT NOT NULL,               -- Low, Medium, High, Critical
    channel          TEXT NOT NULL,               -- Chat, Email, Phone, WhatsApp
    created_date     DATE NOT NULL,               -- Fecha de creación del ticket
    resolved_date    DATE,                        -- Fecha de resolución (NULL si no resuelto)
    status           TEXT NOT NULL,               -- Open, In_Progress, Resolved, Closed
    resolution_hours INTEGER,                     -- Horas que tomó resolver (NULL si no resuelto)
    csat_score       INTEGER,                     -- Satisfacción del cliente 1-5 (NULL si no resuelto)
    CONSTRAINT fk_ticket_user FOREIGN KEY (user_id) REFERENCES alegra_users(user_id)
);