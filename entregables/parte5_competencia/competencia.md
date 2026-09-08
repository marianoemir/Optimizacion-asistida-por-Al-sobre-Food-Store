# Parte 5 — Competencia de optimización entre equipos

**Integrante 3**
**Materia:** Base de Datos II (UTN) — Unidad 2: Optimización de Consultas
**Proyecto Integrador:** Food Store (TP3 Semana 3)

---

## 1. Consulta entregada por la cátedra

```sql
SELECT id, nombre, precio, stock
FROM producto
WHERE categoria_id = 1 AND disponible = TRUE
  AND precio BETWEEN 1000 AND 3000
ORDER BY precio DESC;
```

> Nota: la cátedra entregó la consulta con la columna `activo`, que no existe en el
> esquema del proyecto (`producto` tiene `disponible` y `eliminado`). Se acordó con
> el equipo que se trata de un error de tipeo y se adaptó a `disponible = TRUE`,
> sin cambiar la lógica de la consulta.

## 2. Plan "antes" (sin tocar nada)

```
Sort  (cost=1468.53..1479.67 rows=4455 width=32) (actual time=12.835..13.270 rows=4445.00 loops=1)
  Sort Key: precio DESC
  Sort Method: quicksort  Memory: 435kB
  Buffers: shared hit=925
  ->  Bitmap Heap Scan on producto  (cost=112.74..1198.53 rows=4455 width=32) (actual time=0.997..10.257 rows=4445.00 loops=1)
        Recheck Cond: (categoria_id = 1)
        Filter: (disponible AND (precio >= '1000'::numeric) AND (precio <= '3000'::numeric))
        Rows Removed by Filter: 5560
        Heap Blocks: exact=910
        Buffers: shared hit=922
        ->  Bitmap Index Scan on idx_producto_categoria_id  (cost=0.00..111.63 rows=10045 width=0) (actual time=0.861..0.861 rows=10006.00 loops=1)
              Index Cond: (categoria_id = 1)
              Index Searches: 1
              Buffers: shared hit=12
Planning:
  Buffers: shared hit=120
Planning Time: 5.025 ms
Execution Time: 14.185 ms
```

- **Execution Time (antes):** 14.185 ms
- **Nodo(s) problemático(s) identificado(s):**
  - `Bitmap Heap Scan` + `Filter`: el índice existente (`idx_producto_categoria_id`)
    solo resuelve `categoria_id`, así que trae 10.006 filas candidatas y recién
    después filtra `disponible` y el rango de `precio`, descartando 5.560 filas
    (55% del trabajo de acceso fue innecesario).
  - `Sort`: como el índice usado no viene ordenado por `precio`, hace falta un
    `quicksort` en memoria (435kB) para resolver el `ORDER BY precio DESC`.

## 3. Estrategia propuesta por la IA

**Prompt usado:**
> "Tengo esta consulta y su plan de ejecución real en PostgreSQL. Necesito que
> propongas índices o reescrituras para optimizarla, justificando cada propuesta
> en términos del propio plan (indicando qué nodo ataca: Seq Scan, Sort, Bitmap
> Heap Scan, etc.). [se adjuntó la consulta y el plan "antes" completo, sección 2].
> No apliques nada vos: solo proponé, yo voy a leer y validar cada propuesta antes
> de aplicarla."

**Propuesta(s) de la IA:**
1. **Índice compuesto con orden alineado:**
   `CREATE INDEX idx_producto_cat_disp_precio ON producto (categoria_id, disponible, precio DESC);`
   — elimina el `Filter` (equality antes que el rango evita que `disponible`
   quede como filtro residual) y el `Sort` (el índice ya viene ordenado por
   `precio DESC`, permite `Index Scan Backward`).
2. **Variante covering (Index Only Scan) — elegida:**
   `CREATE INDEX idx_producto_cat_disp_precio_cov ON producto (categoria_id, disponible, precio DESC) INCLUDE (id, nombre, stock);`
   — mismo ataque que la Propuesta 1, más el `INCLUDE` de las columnas
   proyectadas (`id, nombre, stock`) para lograr `Index Only Scan` y eliminar
   también el acceso al heap.
3. **Índice parcial** (`WHERE disponible = TRUE`): más liviano de mantener, pero
   solo sirve mientras la consulta filtre siempre `disponible = TRUE`.
4. **Reescritura:** señaló que a la consulta le falta `AND eliminado = FALSE`
   (regla dura del proyecto), pero se documenta como observación y **no se
   aplica**, porque la consulta fue entregada así por la cátedra y no
   corresponde modificarla unilateralmente para la competencia.

**Justificación de la IA para cada propuesta** (contra qué nodo del plan apunta):
la IA ligó cada propuesta a un nodo puntual del plan real (`Filter`, `Sort`,
`Bitmap Heap Scan`) en vez de dar una respuesta genérica, incluyendo el motivo
técnico de por qué el orden de columnas `(categoria_id, disponible, precio DESC)`
evita que `Filter: disponible` reaparezca sobre el resultado.

## 4. Validación del equipo

- [x] Se leyó línea por línea la propuesta antes de aplicarla
- [x] Se descartó la propuesta de reescritura (agregar `eliminado = FALSE`) por
      alterar la consulta entregada por la cátedra, no por estar mal razonada
- **Estrategia elegida y por qué:** Propuesta 2 (covering). Se priorizó el mejor
  tiempo real posible (criterio de la competencia) sobre el menor costo de
  escritura, ya que este índice es para medición/lectura y no hay una carga de
  escritura relevante que penalizar en este ejercicio.

## 5. Plan "después" (con la estrategia aplicada)

```
Index Only Scan using idx_producto_cat_disp_precio_cov on producto  (cost=0.41..263.89 rows=4459 width=32) (actual time=0.426..8.975 rows=4445.00 loops=1)
  Index Cond: ((categoria_id = 1) AND (disponible = true) AND (precio >= '1000'::numeric) AND (precio <= '3000'::numeric))
  Heap Fetches: 2
  Index Searches: 1
  Buffers: shared hit=2 read=39
Planning:
  Buffers: shared hit=79 read=1
Planning Time: 5.314 ms
Execution Time: 9.311 ms
```

- **Execution Time (después):** 9.311 ms
- El `Filter` y el `Sort` desaparecieron por completo, tal como anticipaba la
  propuesta: las 4 condiciones (`categoria_id`, `disponible`, rango de `precio`)
  quedaron resueltas en un único `Index Cond`, y el orden ya viene dado por el
  índice.
- `Heap Fetches: 2` (no 0): casi todo se resolvió por índice, salvo 2 filas que
  sí requirieron acceso al heap (posiblemente por páginas cuyo *visibility map*
  no estaba del todo actualizado). No invalida el resultado, pero se documenta
  como matiz honesto para la defensa oral.

## 6. Tabla de resultados

| Equipo | Estrategia aplicada | Tiempo antes (ms) | Tiempo después (ms) | Mejora (x) |
|---|---|---|---|---|
| (nuestro equipo) | Índice covering `(categoria_id, disponible, precio DESC) INCLUDE (id, nombre, stock)` | 14.185 | 9.311 | 1.52x |

> Mejora (x) = Tiempo antes / Tiempo después = 14.185 / 9.311 ≈ 1.52

## 7. Bitácora — qué se probó, qué se descartó y por qué

| Propuesta probada | ¿Se aplicó? | Resultado | Motivo |
|---|---|---|---|
| Índice compuesto simple `(categoria_id, disponible, precio DESC)` (Propuesta 1) | No | No medido | Se prefirió directamente la variante covering (Propuesta 2), que domina a la 1 en tiempo de lectura sin costo adicional relevante para este ejercicio |
| Índice covering `(categoria_id, disponible, precio DESC) INCLUDE (id, nombre, stock)` (Propuesta 2) | **Sí** | 14.185 ms → 9.311 ms (1.52x) | Elimina `Filter`, `Sort` y casi todo el acceso al heap (`Index Only Scan`) |
| Índice parcial `WHERE disponible = TRUE` (Propuesta 3) | No | No medido | Más liviano, pero se descartó por ser menos general que la Propuesta 2 y no aportar ninguna ventaja de tiempo adicional para esta consulta puntual |
| Agregar `AND eliminado = FALSE` a la consulta (Propuesta 4) | No | No aplica | Detectado como falta real respecto a la convención del proyecto, pero se descarta porque alteraría la consulta entregada por la cátedra para la competencia |

## 8. Entregable

- [x] Consulta original de la cátedra (adaptada de `activo` a `disponible` por
      acuerdo del equipo, sección 1)
- [x] Plan antes (texto completo, sección 2)
- [x] Prompt + propuesta(s) de la IA (sección 3)
- [x] Plan después (texto completo, sección 5)
- [x] Tabla de resultados (sección 6)
- [x] Bitácora completa (sección 7)
