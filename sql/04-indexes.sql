-- =============================================
-- 04_indexes.sql
-- Índices de optimización
--
-- Sin índices, cada consulta recorre la tabla
-- completa (sequential scan). Con índices, 
-- PostgreSQL salta directo a los registros
-- que necesita.
--
-- Estos índices optimizan las consultas que
-- los agentes y el dashboard hacen con más
-- frecuencia.
--
-- Ejecutar DESPUÉS de 01 y 02.
-- =============================================

-- ─────────────────────────────────────────────
-- Índices en alegra_feature_usage
-- ─────────────────────────────────────────────

-- El JOIN de vista_user_summary busca features por user_id constantemente
CREATE INDEX IF NOT EXISTS idx_feature_user 
    ON alegra_feature_usage(user_id);

-- ─────────────────────────────────────────────
-- Índices en alegra_support_tickets
-- ─────────────────────────────────────────────

-- El JOIN de vista_user_summary busca tickets por user_id
CREATE INDEX IF NOT EXISTS idx_ticket_user 
    ON alegra_support_tickets(user_id);

-- El dashboard filtra tickets por status (Open, In_Progress, etc.)
CREATE INDEX IF NOT EXISTS idx_ticket_status 
    ON alegra_support_tickets(status);

-- ─────────────────────────────────────────────
-- Índices en alegra_churn_analysis
-- ─────────────────────────────────────────────

-- El dashboard y vista_churn_detail filtran por risk_level
CREATE INDEX IF NOT EXISTS idx_churn_risk 
    ON alegra_churn_analysis(risk_level);

-- ─────────────────────────────────────────────
-- Índices en alegra_recommendations
-- ─────────────────────────────────────────────

-- El dashboard filtra alertas por urgencia
CREATE INDEX IF NOT EXISTS idx_rec_urgency 
    ON alegra_recommendations(urgency);

-- El dashboard filtra alertas por risk_level
CREATE INDEX IF NOT EXISTS idx_rec_risk 
    ON alegra_recommendations(risk_level);