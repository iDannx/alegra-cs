# Alegra CS Reto

## Arquitectura general

```
┌─────────────────────────────────────────────────┐
│                  Dashboard React                │
│         (alegra.somoscolombiatech.shop)         │
│                                                 │
│  Panel  │  Alertas  │  Detalle  │  Reporte  │   │
│  ───────┼───────────┼───────────┼───────────┼   │
│         │           │           │           │   │
└────┬────┴─────┬─────┴─────┬─────┴─────┬─────┘   
     │          │           │           │
     │    Supabase (datos)  │    n8n (webhooks)
     │          │           │           │
     ▼          ▼           ▼           ▼
┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐
│ Supabase │ │ Agente 1 │ │ Agente 2 │ │ Agente 3 │
│PostgreSQL│ │ Scoring  │ │ Recomend.│ │ Reporte  │
│          │ │(n8n+GPT) │ │(n8n+GPT) │ │(n8n+GPT) │
└──────────┘ └──────────┘ └──────────┘ └──────────┘
                  │              │           │
                  └──────┬───────┘           │
                         ▼                   │
                   ┌──────────┐              │
                   │  Gmail   │              │
                   │ (alertas)│              │
                   └──────────┘              │
                                             ▼
                                       ┌──────────┐
                                       │ Supabase │
                                       │(reportes)│
                                       └──────────┘
```

## Stack tecnológico

Para este proyecto elegí un stack enfocado en rapidez de desarrollo, escalabilidad y facilidad de integración entre componentes.

### Orquestación — n8n
Opté por n8n porque me permite construir y ajustar flujos de trabajo de forma visual y rápida. Esto fue clave para iterar sin perder tiempo en código innecesario, además de facilitar la integración con APIs externas.

### Agentes de IA — OpenAI (GPT-4o / GPT-4o-mini)
Utilicé dos modelos con roles distintos:
- **GPT-4o-mini** para tareas de alto volumen como scoring, donde el costo y la velocidad son importantes.  
- **GPT-4o** para generar recomendaciones, ya que en este punto necesito mejor razonamiento y mayor calidad en las respuestas.  

Esta separación me permitió optimizar tanto rendimiento como costos.

### Base de datos — Supabase
Elegí Supabase porque ofrece una API REST lista para usar y WebSockets. Esto reduce bastante la complejidad del backend y acelera el desarrollo.

### Dashboard — React + Vite + TypeScript + Tailwind
Este stack me permitió construir una interfaz rápida, mantenible y con buena experiencia de usuario.

### Alertas — Gmail
Implementé el envío de alertas usando Gmail directamente desde n8n, aprovechando su integración nativa. Esto simplifica la arquitectura y permite enviar correos en HTML sin necesidad de añadir servicios adicionales.

### Claude Code
Claude Code me permitió desarrollar en tiempo record la plataforma para plazmar los datos de los resultados generados por los Agentes IA. 

---

## Los datos

El equipo de Alegra proporcionó 3 archivos CSV:

- **alegra_users.csv** — 2,000 clientes con país, plan, MRR, fuente de adquisición y un churn_risk_score precalculado
- **alegra_feature_usage.csv** — 7,022 registros de features que cada usuario ha tocado, con nivel de adopción y última fecha de uso
- **alegra_support_tickets.csv** — 3,500 tickets de soporte con categoría, prioridad, estado, CSAT y tiempos de resolución

### Modelo de datos en Supabase

Los 3 CSVs se cargaron como tablas en Supabase manteniendo los nombres originales: `alegra_users`, `alegra_feature_usage`, `alegra_support_tickets`. Las relaciones son simples — todo se conecta por `user_id`.

Además creé estas tablas para los resultados:

- **alegra_churn_analysis** — Donde el Agente 1 guarda el score, nivel de riesgo y razones por usuario
- **alegra_recommendations** — Donde el Agente 2 guarda las recomendaciones personalizadas con nivel de urgencia
- **alegra_weekly_reports** — Donde el Agente 3 guarda los reportes semanales generados por IA

### Las vistas SQL — por qué y para qué

Esta fue una de las decisiones técnicas más importantes. En vez de mandarle a GPT los datos crudos de 3 tablas y esperar que los cruce, creé vistas SQL que hacen el trabajo pesado:

**vista_user_summary** — Cruza las 3 tablas base con JOINs y agrega métricas por usuario en una sola fila. Para cada usuario calcula: días desde la última actividad, peor y mejor nivel de adopción, lista de features, total de tickets, tickets abiertos, tickets críticos sin resolver, peor CSAT, promedio CSAT, y categorías de tickets. El cruce de datos es trabajo de base de datos, no de IA.

**vista_churn_detail** — Combina el análisis de churn con el resumen de usuario. Filtra solo los de riesgo alto y medio. Es lo que alimenta al Agente 2.

**vista_report_metrics** — Agrega todos los datos en un solo JSON con las métricas que el Agente 3 necesita para generar el reporte semanal: distribución de riesgo, riesgo por plan, riesgo por país, top 10 clientes, MRR en riesgo, tickets abiertos.

La razón de usar vistas y no hacerlo con IA: un JOIN en Supabase toma milisegundos. Mandarle 12,500 filas crudas a GPT para que "cruce" los datos tomaría minutos, costaría mucho, y el resultado sería menos confiable. Por eso, se le dio uso a la IA en tareas como, clasificación, Scoring, recomendaciones y generación de reportes semanales.

---

## Los agentes

### Agente 1 — Scoring y clasificación de churn

**Qué hace:** Recibe los datos cruzados de cada usuario (desde `vista_user_summary`) y evalúa su riesgo de churn aplicando criterios de scoring definidos.

**Criterios de scoring:**

| Señal | Condición | Puntos |
|-------|-----------|--------|
| Inactividad | 31-60 días | +15 |
| Inactividad | 61-90 días | +30 |
| Inactividad | 90+ días | +40 |
| Adopción | Solo "activated" | +10 |
| Adopción | Solo "used_1x" | +5 |
| Ticket crítico abierto | Por cada uno | +25 |
| Ticket alto abierto | Por cada uno | +15 |
| Ticket medio/bajo abierto | Por cada uno | +5 |
| CSAT | Peor = 1 | +25 |
| CSAT | Peor = 2 | +15 |
| Plan | Free | +10 |
| Volumen tickets | 4+ tickets | +10 |

**Clasificación:**
- 0-25 puntos → Riesgo **bajo** (verde)
- 26-50 puntos → Riesgo **medio** (amarillo)
- 51+ puntos → Riesgo **alto** (rojo)

**Por qué estos criterior de clasificación:** Me basé principalmente en los datos entregados y como se comporta cada cliente con el producto. Se identifican las señales que indican riesgo de abandono, tales como inactividad, insatisfacción, problemas sin resolver y tambien el bajo uso del producto. Y con base en esto, se le asigna una cantidad de puntos segun la gravedad **relativa** de cada señal, esto quiere decir, que no todas las señales tienen el mismo peso. 

---

**Modelo:** GPT-4o-mini

**System prompt:** Define el rol de analista de CS, los criterios de evaluación exactos, y exige respuesta en JSON estricto con user_id, score, risk_level y reasons.

### Agente 2 — Recomendaciones personalizadas

**Qué hace:** Toma cada usuario de riesgo alto y medio con su contexto completo (features, tickets, CSAT, plan, país) y genera una recomendación de retención personalizada y accionable.

**Por qué este agente es diferente:** Se le pasa el contexto completo al agente y el decide algo tipo: "este cliente dejó de usar facturación electrónica hace 45 días y tiene un bug crítico abierto en esa feature, la acción más efectiva es resolver ese bug antes que ofrecerle un descuento."

**Modelo:** GPT-4o

**Outputs:**
- **Urgencia:** inmediata / esta_semana / monitoreo
- **Recomendación:** Acción específica, accionable, que menciona features y tickets concretos
- **Razonamiento:** Por qué esa acción y no otra

### Agente 3 — Reporte semanal

**Qué hace:** Recibe las métricas agregadas de la semana (desde `vista_report_metrics`) y genera un reporte ejecutivo como lo haría un director de CS presentando al CEO.

**Modelo:** GPT-4o

**Outputs:**
- Título descriptivo basado en el hallazgo más importante
- Resumen ejecutivo de 3-4 párrafos con datos concretos
- Métricas clave en formato estructurado (JSON)
- Top clientes de mayor riesgo con recomendaciones
- 5 action items priorizados y específicos

---

## Integraciones activas

1. **Supabase** — Base de datos central. Lectura y escritura desde n8n y el dashboard. Realtime con WebSockets para actualizar la interfaz en vivo.
2. **OpenAI** — Motor de IA para los 3 agentes. GPT-4o-mini para scoring masivo, GPT-4o para análisis profundo.
3. **Gmail** — Alertas automáticas por email cuando se detectan clientes con urgencia inmediata. Email HTML profesional con tabla resumen y botón que lleva directo al dashboard.

---

## El dashboard

Construido con React + Vite + TypeScript + Tailwind CSS.

### Páginas

**Panel principal (/)** — KPIs con contadores animados (usuarios analizados, riesgo alto, medio, acción inmediata), gráficos de distribución de riesgo, riesgo por plan, riesgo por país, factores más comunes. Botones "Ejecutar análisis" y "Generar reporte" en el header.

**Alertas (/alerts-cs)** — Tabla filtrable con todos los usuarios en riesgo. Filtros por nivel de riesgo, urgencia, país y plan. Búsqueda por user_id. Cada fila muestra score, plan, MRR, urgencia y recomendación truncada. Es la página donde llega el botón del email de alerta.

**Detalle de usuario (/user/:id)** — Perfil completo del cliente: score con gauge visual, desglose de razones con puntos, recomendación del agente IA, grid de features con nivel de adopción y días desde último uso, tabla de tickets con badges de prioridad y estado, CSAT. Muestra visualmente el cruce de las 3 fuentes de datos.

**Reporte semanal (/report)** — Muestra los reportes generados por IA. Botón para generar uno nuevo que llama al webhook de n8n. Historial de reportes anteriores con fecha.

**Carga de datos (/upload)** — Wizard paso a paso para subir los 3 CSVs. Paso 1: usuarios, Paso 2: features, Paso 3: tickets. Cada paso muestra preview del archivo y progreso de carga. Respeta el orden por las foreign keys.

---

## Qué falló y cómo lo resolví

### El import de CSVs a Supabase
Los tickets tenían campos vacíos (resolved_date, resolution_hours, csat_score) para tickets abiertos. El importador de Supabase no convertía strings vacíos a NULL y tiraba error `invalid input syntax for type date: ""`. La solución fue crear la tabla con esas columnas como TEXT, importar, convertir los vacíos a NULL con UPDATE, y después ALTER COLUMN al tipo correcto.

### Duplicados al re-ejecutar workflows
Cuando el Workflow 2 se ejecutaba desde el Workflow 1 vía "Execute Workflow", fallaba con `duplicate key value violates unique constraint` porque los datos de la ejecución anterior seguían en la tabla. La solución fue agregar lógica de limpieza (DELETE) al inicio de cada workflow, o usar upsert con `Prefer: resolution=merge-duplicates`.

### GPT procesando 2,000 usuarios
Mandar 2,000 usuarios uno por uno a GPT tomaba horas. Lotes de 50 tardaban demasiado en responder. El sweet spot fueron lotes de 10-15 usuarios, reduciendo el tiempo a 30-45 minutos.

### El Loop Over Items duplicaba datos
El nodo de OpenAI se ejecutaba una vez por cada item del lote, y cada vez `$input.all()` tomaba todos los items. Resultado: 5 respuestas iguales con los mismos 5 usuarios. La solución fue agregar un nodo Code antes de OpenAI que agrupa el lote en un solo item, y cambiar el user message a `{{ $json.prompt }}`.

---

## Decisiones técnicas que tomé

**¿Por qué vistas SQL en vez de cruce con IA?** Porque un JOIN toma milisegundos y es 100% confiable. Mandarle 12,500 filas a GPT para que "cruce" datos es lento, caro, y propenso a errores. La IA se usa donde hay ambigüedad y juicio, el código se usa donde hay lógica determinística.

**¿Por qué GPT-4o-mini para el Agente 1 y GPT-4o para el Agente 2?** Costo vs calidad. El Agente 1 procesa 2,000 usuarios aplicando reglas — no necesita el modelo más potente. El Agente 2 genera recomendaciones personalizadas que requieren razonamiento contextual — ahí sí vale la pena la calidad extra.

**¿Por qué Supabase y no PostgreSQL directo?** Porque Supabase me da PostgreSQL + API REST + Realtime (WebSockets) + hosting managed. No necesito configurar un servidor de base de datos aparte.

**¿Por qué alertas solo para urgencia inmediata?** Porque mandar email por cada usuario en monitoreo sería spam. Solo los casos que necesitan acción hoy merecen interrumpir al analista. Los demás se ven en el dashboard cuando el analista tenga tiempo.

---

## Edge cases considerados

- Usuarios sin tickets (361 de 2,000): el LEFT JOIN los mantiene con NULL en las métricas de tickets, el scoring les da 0 puntos en esa categoría
- Tickets sin CSAT ni fecha de resolución: son los abiertos/en progreso, las columnas aceptan NULL
- Campos vacíos en CSV: se convierten a NULL antes de insertar en Supabase
- Re-ejecución del pipeline: las tablas de resultados se limpian antes de insertar para evitar duplicados
- Usuarios de riesgo bajo: no reciben recomendación, se muestran en el dashboard pero sin acción requerida

---

## Estructura del repositorio

```
alegra-cs/
├── README.md                          # Este archivo
├── n8n/
│   ├── workflow-agent1-scoring.json   # Workflow del Agente 1
│   ├── workflow-agent2-recommendations.json  # Workflow del Agente 2
│   ├── workflow-agent3-report.json    # Workflow del Agente 3 (reporte semanal)
│   └── prompts/
│       ├── system_prompt_agent1.txt   # Prompt del scoring
│       ├── system_prompt_agent2.txt   # Prompt de recomendaciones
│       └── system_prompt_agent3.txt   # Prompt del reporte
├── sql/
│   ├── 01_create_tables.sql           # Tablas base
│   ├── 02_create_results_tables.sql   # Tablas de resultados
│   ├── 03_create_views.sql            # Vistas SQL
│   └── 04_indexes.sql                 # Índices de optimización
├── dashboard/
│   ├── package.json
│   ├── src/
│   │   ├── pages/                     # Dashboard, Alerts, UserDetail, Report, Upload
│   │   ├── components/                # Componentes reutilizables
│   │   ├── hooks/                     # Custom hooks para Supabase
│   │   └── lib/                       # Configuración de Supabase
│   └── ...
└── docs/
    ├── architecture-diagram.png       # Diagrama de arquitectura
    └── screenshots/                   # Capturas del sistema funcionando
```

## Demo en vivo

🔗 Dashboard: https://alegracs.somoscolombiatech.shop

---
