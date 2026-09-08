# Declaración de Uso de IA (DUIA) — Parte 3 y Parte 5

**Rol / Asignación:** Integrante 3 — Parte 3 (Lectura crítica) + Parte 5 (Competencia)
**Materia:** Base de Datos II (UTN) — Unidad 2: Optimización de Consultas
**Proyecto Integrador:** Food Store (TP3 Semana 3)

---

## Registro de Interacciones y Decisiones con IA

| Herramienta | Para qué se usó | Prompt / Spec (resumen) | Se aceptó / se descartó y por qué |
|---|---|---|---|
| IA (Parte 3) | Explicar en lenguaje natural el plan real "después" de la Consulta 3 de la Parte 2 (ranking de clientes por monto gastado, con `idx_pedido_usuario_total_estado` ya aplicado) | *"Explicame este plan de ejecución de PostgreSQL en lenguaje natural, nodo por nodo (de adentro hacia afuera). Para cada nodo indicá qué hace y por qué el motor lo eligió. No tengo más contexto que este texto."* Se le pasó únicamente el texto crudo del plan, sin la consulta ni ningún análisis previo. | **Se contrastó frase por frase contra el plan real.** De 5 afirmaciones evaluadas, se detectaron 2 imprecisiones reales: (1) la IA confundió el predicado de un índice parcial con columnas cubiertas por el índice; (2) mencionó "bloques de disco" cuando el plan mostraba `shared hit` (caché), no `read` (disco). Una tercera afirmación (mapa de visibilidad) fue calificada como "no verificable con el texto dado" — técnicamente correcta en general, pero no sustentada por el plan entregado. Las otras 2 afirmaciones fueron correctas. Detalle completo en `lectura_critica.md`. |
| IA (Parte 5) | Proponer índices/reescrituras para la consulta común de la competencia (productos por categoría con filtro de precio y disponibilidad, sin índice específico) | *"Tengo esta consulta y su plan de ejecución real en PostgreSQL. Necesito que propongas índices o reescrituras para optimizarla, justificando cada propuesta en términos del propio plan (indicando qué nodo ataca). No apliques nada vos: solo proponé, yo voy a leer y validar cada propuesta antes de aplicarla."* Se adjuntó la consulta y el plan "antes" completo. | **Se evaluaron 4 propuestas, se aplicó 1.** (1) Índice compuesto simple — no aplicado, se prefirió directamente la variante covering. (2) Índice covering con `INCLUDE` — **aceptado y aplicado**: eliminó el `Filter`, el `Sort`, y logró casi un `Index Only Scan` completo (`Heap Fetches: 2`), mejorando el tiempo real de 14.185 ms a 9.311 ms (~1.52x). (3) Índice parcial `WHERE disponible = TRUE` — descartado por no aportar ventaja adicional sobre la Propuesta 2 para esta consulta puntual. (4) Reescritura agregando `AND eliminado = FALSE` — detectada como falta real respecto a la convención del proyecto, pero descartada por alterar la consulta entregada por la cátedra sin autorización del equipo. Detalle completo en `competencia.md`. |

---

## Notas de criterio de aceptación

- En la Parte 5, se leyó línea por línea cada propuesta antes de aplicar cualquier
  `CREATE INDEX`, y se documentó explícitamente por qué se descartaron 2 de las 4
  propuestas (no solo la que "no funcionó", sino también las que funcionaban pero no
  se justificaba aplicar).
- En la Parte 3, se identificó honestamente que la IA acertó en 2 de las 5 afirmaciones
  evaluadas (no se buscó forzar errores donde no los había): no confundió `cost` con
  tiempo real, y no inventó `Rows Removed by Filter` inexistente.
- Se documentó un matiz técnico (`Heap Fetches: 2`, no 0, en el plan "después" de la
  Parte 5) en vez de presentar el resultado como perfecto — es coherente con el
  criterio de la cátedra de documentar hallazgos honestamente, incluso cuando no son
  100% ideales.
