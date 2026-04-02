-- =============================================
-- 03_create_views.sql

-- vista_user_summary
--
-- LA VISTA MÁS IMPORTANTE. Cruza las 3 tablas
-- base y produce UNA fila por usuario con todas
-- sus métricas agregadas. Es lo que alimenta
-- al Agente 1.
--
-- ¿Qué calcula?
-- - Días desde la última actividad en cualquier feature
-- - Peor y mejor nivel de adopción (escala 1-5)
-- - Lista de features que usa
-- - Total de tickets, abiertos, críticos sin resolver
-- - Peor CSAT, promedio CSAT
-- - Categorías de tickets
--
-- Usa LEFT JOIN para tickets porque 361 usuarios
-- no tienen tickets. Sin LEFT JOIN perderíamos
-- esos usuarios.
-- ─────────────────────────────────────────────
CREATE OR REPLACE VIEW vista_user_summary AS
SELECT 
    u.user_id,
    u.country,
    u.plan,
    u.signup_date,
    u.source,
    u.mrr_usd,
    u.churn_risk_score AS original_churn_score,
    u.features_count,

    -- Días sin actividad: fecha actual menos la fecha más reciente de uso de cualquier feature
    CURRENT_DATE - MAX(f.last_used_date) AS days_since_last_activity,
    
    -- Peor nivel de adopción entre todas las features del usuario
    -- 1=activated (peor), 2=used_1x, 3=used_5x, 4=used_10x, 5=power_user (mejor)
    MIN(
        CASE f.adoption_level
            WHEN 'activated' THEN 1
            WHEN 'used_1x' THEN 2
            WHEN 'used_5x' THEN 3
            WHEN 'used_10x' THEN 4
            WHEN 'power_user' THEN 5
        END
    ) AS worst_adoption_level,
    
    -- Mejor nivel de adopción (para ver si al menos una feature está bien adoptada)
    MAX(
        CASE f.adoption_level
            WHEN 'activated' THEN 1
            WHEN 'used_1x' THEN 2
            WHEN 'used_5x' THEN 3
            WHEN 'used_10x' THEN 4
            WHEN 'power_user' THEN 5
        END
    ) AS best_adoption_level,
    
    -- Lista de features separadas por coma (para contexto del agente)
    STRING_AGG(DISTINCT f.feature, ', ' ORDER BY f.feature) AS features_list,

    -- Total de tickets del usuario (0 si no tiene)
    COUNT(DISTINCT t.ticket_id) AS total_tickets,
    
    -- Tickets que siguen sin resolver
    COUNT(DISTINCT CASE WHEN t.status IN ('Open', 'In_Progress') THEN t.ticket_id END) AS open_tickets,
    
    -- Tickets críticos o altos que siguen sin resolver (los más urgentes)
    COUNT(DISTINCT CASE WHEN t.status IN ('Open', 'In_Progress') AND t.priority IN ('Critical', 'High') THEN t.ticket_id END) AS critical_open_tickets,
    
    -- Peor calificación de satisfacción (1 es terrible, 5 es excelente)
    MIN(t.csat_score) AS worst_csat,
    
    -- Promedio de CSAT (para ver tendencia general)
    ROUND(AVG(t.csat_score), 1) AS avg_csat,
    
    -- Categorías de tickets separadas por coma
    STRING_AGG(DISTINCT t.category, ', ' ORDER BY t.category) AS ticket_categories

FROM alegra_users u
-- INNER JOIN con features: todos los usuarios tienen al menos 1 feature
LEFT JOIN alegra_feature_usage f ON u.user_id = f.user_id
-- LEFT JOIN con tickets: 361 usuarios no tienen tickets, no los queremos perder
LEFT JOIN alegra_support_tickets t ON u.user_id = t.user_id
GROUP BY u.user_id, u.country, u.plan, u.signup_date, u.source, u.mrr_usd, u.churn_risk_score, u.features_count;


-- ─────────────────────────────────────────────
-- vista_churn_detail
--
-- Combina el análisis de churn (resultado del
-- Agente 1) con el resumen de usuario. Filtra
-- solo los de riesgo alto y medio.
--
-- Es lo que alimenta al Agente 2 — solo recibe
-- usuarios que necesitan recomendación, no los
-- 2,000 completos.
-- ─────────────────────────────────────────────
CREATE OR REPLACE VIEW vista_churn_detail AS
SELECT 
    ca.user_id,
    ca.score,
    ca.risk_level,
    ca.reasons,
    ca.analyzed_at,
    vs.country,
    vs.plan,
    vs.signup_date,
    vs.source,
    vs.mrr_usd,
    vs.features_count,
    vs.days_since_last_activity,
    vs.worst_adoption_level,
    vs.best_adoption_level,
    vs.features_list,
    vs.total_tickets,
    vs.open_tickets,
    vs.critical_open_tickets,
    vs.worst_csat,
    vs.avg_csat,
    vs.ticket_categories
FROM alegra_churn_analysis ca
JOIN vista_user_summary vs ON ca.user_id = vs.user_id
WHERE ca.risk_level IN ('alto', 'medio')
ORDER BY ca.score DESC;


-- ─────────────────────────────────────────────
-- vista_report_metrics
--
-- Agrega TODOS los datos en un solo JSON para
-- el Agente 3 (reporte semanal). En vez de
-- mandarle filas y filas, le mandamos un resumen
-- estructurado con:
-- - Distribución de riesgo
-- - Riesgo por plan y por país
-- - Score promedio por plan
-- - Top 10 clientes de mayor riesgo
-- - MRR total en riesgo
-- - Resumen de tickets abiertos
--
-- Produce UNA sola fila con UN solo campo JSON.
-- ─────────────────────────────────────────────
CREATE OR REPLACE VIEW vista_report_metrics AS
SELECT json_build_object(
    'total_users', (SELECT COUNT(*) FROM alegra_churn_analysis),
    
    'risk_distribution', (
        SELECT json_object_agg(risk_level, cnt)
        FROM (SELECT risk_level, COUNT(*) as cnt FROM alegra_churn_analysis GROUP BY risk_level) t
    ),
    
    'urgency_distribution', (
        SELECT json_object_agg(urgency, cnt)
        FROM (SELECT urgency, COUNT(*) as cnt FROM alegra_recommendations GROUP BY urgency) t
    ),
    
    'risk_by_plan', (
        SELECT json_agg(row_to_json(t))
        FROM (
            SELECT u.plan, ca.risk_level, COUNT(*) as cnt 
            FROM alegra_churn_analysis ca 
            JOIN alegra_users u ON ca.user_id = u.user_id 
            GROUP BY u.plan, ca.risk_level 
            ORDER BY u.plan
        ) t
    ),
    
    'risk_by_country', (
        SELECT json_agg(row_to_json(t))
        FROM (
            SELECT u.country, ca.risk_level, COUNT(*) as cnt 
            FROM alegra_churn_analysis ca 
            JOIN alegra_users u ON ca.user_id = u.user_id 
            GROUP BY u.country, ca.risk_level 
            ORDER BY u.country
        ) t
    ),
    
    'avg_score_by_plan', (
        SELECT json_agg(row_to_json(t))
        FROM (
            SELECT u.plan, ROUND(AVG(ca.score), 1) as avg_score, COUNT(*) as total
            FROM alegra_churn_analysis ca 
            JOIN alegra_users u ON ca.user_id = u.user_id 
            GROUP BY u.plan ORDER BY avg_score DESC
        ) t
    ),
    
    'top_10_risk_clients', (
        SELECT json_agg(row_to_json(t))
        FROM (
            SELECT ca.user_id, ca.score, ca.risk_level, ca.reasons,
                   u.plan, u.country, u.mrr_usd,
                   r.urgency, r.recommendation
            FROM alegra_churn_analysis ca
            JOIN alegra_users u ON ca.user_id = u.user_id
            LEFT JOIN alegra_recommendations r ON ca.user_id = r.user_id
            ORDER BY ca.score DESC
            LIMIT 10
        ) t
    ),
    
    'total_mrr_at_risk', (
        SELECT COALESCE(SUM(u.mrr_usd), 0)
        FROM alegra_churn_analysis ca
        JOIN alegra_users u ON ca.user_id = u.user_id
        WHERE ca.risk_level IN ('alto', 'medio')
    ),
    
    'open_tickets_summary', (
        SELECT json_build_object(
            'total_open', COUNT(*) FILTER (WHERE status IN ('Open', 'In_Progress')),
            'critical_open', COUNT(*) FILTER (WHERE status IN ('Open', 'In_Progress') AND priority = 'Critical'),
            'high_open', COUNT(*) FILTER (WHERE status IN ('Open', 'In_Progress') AND priority = 'High')
        )
        FROM alegra_support_tickets
    )
) AS metrics;