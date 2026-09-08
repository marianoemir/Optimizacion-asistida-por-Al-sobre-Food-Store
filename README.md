# Food Store — TP de Optimización de Consultas con IA (Base de Datos II)

Proyecto integrador de un sistema de venta de comida, implementado en PostgreSQL. Este repositorio contiene el Trabajo Práctico de la Semana 3 (Unidad 2: Optimización de Consultas), resuelto en grupo de 3 integrantes con OpenCode y Gemini como herramientas de IA.

## Grupo

Grupo 10

**Integrantes:**
- Mariano Chirino
- Andrés Fabre
- Facundo Quiroga

## Repositorio

**Link:** https://github.com/marianoemir/Optimizacion-asistida-por-Al-sobre-Food-Store

## Cómo está organizado este repositorio

### Archivos de la base de datos
Están dentro de la carpeta **`Archivos necesarios para la BD/`**:

| Archivo | Contenido |
|---|---|
| `schema.sql` | Tipos ENUM, tablas, constraints e índices |
| `objects.sql` | Vistas, función de cálculo, triggers y procedimiento `sp_crear_pedido` |
| `data.sql` | Datos de prueba (categorías, productos, usuarios, pedidos) |
| `queries.sql` | Historias de usuario resueltas y consultas analíticas |
| `transacciones.sql` | Escenarios de atomicidad, aislamiento y concurrencia (del TP anterior, se mantiene) |
| `carga_masiva.sql` | Script de población masiva de esta entrega: ≥50.000 productos, ≥20.000 usuarios, ≥200.000 pedidos con detalles |

**Orden de ejecución:** `schema.sql → objects.sql → data.sql → carga_masiva.sql`

### Entregables del TP de Optimización de Consultas

| Archivo | Qué contiene |
|---|---|
| `protocolo_seguridad.md` | Los pasos de seguridad (copia, transacción, respaldo, ANALYZE) aplicados antes de cualquier cambio sobre la base |
| `entregables/parte2_laboratorio/ParteAndres.md` | 3 consultas lentas con su plan real antes/después de aplicar índices propuestos por IA |
| `entregables/parte2_laboratorio/Tabla_de_resultados_seccion_2.2.md` | Tabla comparativa resumida de las 3 consultas (nodo, cost, tiempo, mejora) |
| `entregables/parte3_lectura_critica/lectura_critica.md` | Contraste entre la explicación de un plan generada por IA y el plan real, con imprecisiones detectadas |
| `entregables/parte4_consultas_resumen/consultas_parte4.md` | 2 consultas (agregación y subconsulta) generadas bajo spec precisa, con verificación de equivalencia contra una alternativa propia |
| `entregables/parte5_competencia/competencia.md` | Competencia de optimización sobre la consulta común entregada por la cátedra |
| `duia/` | Declaración de Uso de IA de los 3 integrantes, una por cada bloque de trabajo |

### Configuración de IA
- `AGENTS.md`: instrucciones para OpenCode sobre la estructura, el protocolo de seguridad y las reglas duras del proyecto.
- `.kiro/steering/`: convenciones del esquema para Kiro (nombres de tablas, borrado lógico, tipos ENUM, triggers existentes).

## Quién hizo qué

El TP se dividió en bloques de trabajo entre los 3 integrantes:

| Bloque | Integrante | Contenido |
|---|---|---|
| Parte 1 — Carga masiva | Andrés Fabre | Script de población masiva (50.018 productos, 20.006 usuarios, 200.006 pedidos, 400.013+ detalles), verificado sobre `copia_trabajo` |
| Parte 2 — Laboratorio de optimización | Andrés Fabre | 3 consultas lentas, cada una con ciclo completo de EXPLAIN ANALYZE antes/después de proponer y validar un índice |
| Parte 3 — Lectura crítica | Mariano Chirino | Contraste de la explicación de un plan generada por IA contra el plan real, con 2 imprecisiones conceptuales detectadas |
| Parte 4 — Consultas resumen y subconsultas | Facundo Quiroga | 2 consultas (una de agregación con LEFT JOIN, una con subconsulta correlacionada) verificadas por equivalencia con EXCEPT |
| Parte 5 — Competencia de optimización | Mariano Chirino | Índice covering aplicado sobre la consulta común de la cátedra, con mejora real de ~1.52x |

El detalle completo de cada parte (spec o prompt usado, qué generó la IA, qué se aceptó o descartó y por qué, y la verificación con el motor real) está en los archivos de `entregables/` y en la `duia/` correspondiente.

## Cómo levantar el proyecto localmente

```bash
# 1. Crear la plantilla con el esquema y el seed chico
createdb plantilla_food_store
psql -d plantilla_food_store -f "Archivos necesarios para la BD/schema.sql"
psql -d plantilla_food_store -f "Archivos necesarios para la BD/objects.sql"
psql -d plantilla_food_store -f "Archivos necesarios para la BD/data.sql"

# 2. Crear una copia de trabajo descartable a partir de la plantilla
createdb -T plantilla_food_store copia_trabajo

# 3. Aplicar la carga masiva SOLO sobre copia_trabajo
psql -d copia_trabajo -f "Archivos necesarios para la BD/carga_masiva.sql"
```

Antes de aplicar cualquier cambio sobre la base, se sigue el flujo de `protocolo_seguridad.md`: nunca se trabaja sobre `plantilla_food_store` directamente, siempre sobre una copia descartable (`copia_trabajo`), con respaldo previo (`pg_dump` o Backup de pgAdmin) antes de cualquier cambio estructural, y `ANALYZE` corrido después de cualquier carga masiva o creación de índice, antes de medir con `EXPLAIN ANALYZE`.

## Criterio de aceptación

Ninguna propuesta de la IA se aplicó "porque lo dijo la IA": cada índice o reescritura se aplicó solo después de poder explicar, línea por línea, qué nodo del plan atacaba y por qué se esperaba que mejorara — y se documentaron también los casos en los que la propuesta **no** mejoró el tiempo real (ver Consulta 2 de la Parte 2), en vez de descartarlos en silencio.
