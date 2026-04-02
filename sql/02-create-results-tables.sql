-- =============================================
-- 02_create_results_tables.sql
-- Tablas de resultados — aquí los agentes de IA
-- guardan sus outputs (scoring, recomendaciones,
-- reportes semanales)
-- Ejecutar DESPUÉS de 01_create_tables.sql
-- =============================================

-- ─────────────────────────────────────────────
-- alegra_churn_analysis
-- El Agente 1 (scoring) guarda aquí el resultado
-- del análisis de cada usuario: su score numérico,
-- nivel de riesgo, y las razones desglosadas.
-- Hay una fila por cada usuario analizado (2,000).
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS alegra_churn_analysis (
    user_id      TEXT PRIMARY KEY,               -- FK → alegra_users
    score        INTEGER NOT NULL,               -- Score calculado (0-130+, según criterios de scoring)
    risk_level   TEXT NOT NULL,                   -- bajo (0-25), medio (26-50), alto (51+)
    reasons      TEXT NOT NULL,                   -- Explicación en lenguaje natural generada por GPT
    analyzed_at  TIMESTAMP DEFAULT NOW(),         -- Timestamp del análisis
    CONSTRAINT fk_churn_user FOREIGN KEY (user_id) REFERENCES alegra_users(user_id)
);

-- ─────────────────────────────────────────────
-- alegra_recommendations
-- El Agente 2 (recomendaciones) guarda aquí las
-- recomendaciones personalizadas para cada usuario
-- en riesgo alto o medio. Los de riesgo bajo no
-- reciben recomendación.
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS alegra_recommendations (
    user_id          TEXT PRIMARY KEY,            -- FK → alegra_users
    risk_level       TEXT NOT NULL,               -- alto o medio (los bajo no llegan aquí)
    urgency          TEXT NOT NULL,               -- inmediata, esta_semana, monitoreo
    recommendation   TEXT NOT NULL,               -- Acción específica generada por GPT-4o
    reasoning        TEXT NOT NULL,               -- Razonamiento del por qué esa acción
    created_at       TIMESTAMP DEFAULT NOW(),     -- Timestamp de la recomendación
    CONSTRAINT fk_rec_user FOREIGN KEY (user_id) REFERENCES alegra_users(user_id)
);

-- ─────────────────────────────────────────────
-- alegra_weekly_reports
-- El Agente 3 (reporte semanal) guarda aquí cada
-- reporte generado. Puede haber múltiples reportes
-- (historial). key_metrics y top_risk_clients son
-- JSONB para almacenar datos estructurados.
-- ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS alegra_weekly_reports (
    id                SERIAL PRIMARY KEY,         -- ID auto-incremental
    report_date       DATE NOT NULL DEFAULT CURRENT_DATE,
    title             TEXT NOT NULL,               -- Título generado por GPT basado en el hallazgo principal
    executive_summary TEXT NOT NULL,               -- Resumen ejecutivo de 3-4 párrafos
    key_metrics       JSONB NOT NULL,              -- Métricas clave en formato estructurado
    top_risk_clients  JSONB NOT NULL,              -- Top clientes de mayor riesgo con recomendaciones
    action_items      TEXT NOT NULL,               -- 5 acciones prioritarias numeradas
    generated_by      TEXT NOT NULL DEFAULT 'ai_agent',
    created_at        TIMESTAMP DEFAULT NOW()
);