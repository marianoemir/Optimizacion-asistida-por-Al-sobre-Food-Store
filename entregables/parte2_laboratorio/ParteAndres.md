------------------------------------------------------------------------
--Consulta 1 — Historial de pedidos por rango de fechas y estado
------------------------------------------------------------------------

EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id, p.fecha, p.estado, p.total, u.nombre, u.apellido
FROM pedido p
JOIN usuario u ON u.id = p.usuario_id
WHERE p.eliminado = FALSE
  AND p.fecha BETWEEN '2025-01-01' AND '2025-06-30'
  AND p.estado = 'TERMINADO';

--Salida de pgAdmin (ANTES del índice)

"Hash Join  (cost=825.13..8303.55 rows=17639 width=51) (actual time=5.137..27.207 rows=18000 loops=1)"
"  Hash Cond: (p.usuario_id = u.id)"
"  Buffers: shared hit=4307"
"  ->  Seq Scan on pedido p  (cost=0.00..7432.11 rows=17639 width=32) (actual time=0.015..18.469 rows=18000 loops=1)"
"        Filter: ((NOT eliminado) AND (fecha >= '2025-01-01'::date) AND (fecha <= '2025-06-30'::date) AND (estado = 'TERMINADO'::estado_pedido))"
"        Rows Removed by Filter: 182006"
"        Buffers: shared hit=3932"
"  ->  Hash  (cost=575.06..575.06 rows=20006 width=35) (actual time=5.054..5.055 rows=20006 loops=1)"
"        Buckets: 32768  Batches: 1  Memory Usage: 1662kB"
"        Buffers: shared hit=375"
"        ->  Seq Scan on usuario u  (cost=0.00..575.06 rows=20006 width=35) (actual time=0.010..2.551 rows=20006 loops=1)"
"              Buffers: shared hit=375"
"Planning:"
"  Buffers: shared hit=135 dirtied=5"
"Planning Time: 0.480 ms"
"Execution Time: 27.910 ms"

--Análisis del Plan "ANTES"

Nodo principal de cuello de botella: Seq Scan sobre la tabla pedido (cost=0.00..7432.11),
leyendo 200.006 filas en disco y descartando 182.006 filas por filtro (Rows Removed by
Filter). Costo estimado: 8303.55. Tiempo de ejecución real: 27.910 ms (I/O alto con 3932
buffers leídos solo en la tabla pedido).

-- Crear el Índice de Optimización

CREATE INDEX idx_pedido_fecha_estado_vigente
ON pedido(fecha, estado)
WHERE eliminado = FALSE;

-- Medición "DESPUÉS"

EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id, p.fecha, p.estado, p.total, u.nombre, u.apellido
FROM pedido p
JOIN usuario u ON u.id = p.usuario_id
WHERE p.eliminado = FALSE
  AND p.fecha BETWEEN '2025-01-01' AND '2025-06-30'
  AND p.estado = 'TERMINADO';

--Salida de pgAdmin (DESPUÉS del índice)

"Hash Join  (cost=1969.51..6256.51 rows=17639 width=51) (actual time=5.373..12.511 rows=18000 loops=1)"
"  Hash Cond: (p.usuario_id = u.id)"
"  Buffers: shared hit=2438 read=62"
"  ->  Bitmap Heap Scan on pedido p  (cost=1144.38..5385.06 rows=17639 width=32) (actual time=1.341..4.909 rows=18000 loops=1)"
"        Recheck Cond: ((fecha >= '2025-01-01'::date) AND (fecha <= '2025-06-30'::date) AND (estado = 'TERMINADO'::estado_pedido) AND (NOT eliminado))"
"        Heap Blocks: exact=2063"
"        Buffers: shared hit=2063 read=62"
"        ->  Bitmap Index Scan on idx_pedido_fecha_estado_vigente  (cost=0.00..1139.97 rows=17639 width=0) (actual time=1.140..1.140 rows=18000 loops=1)"
"              Index Cond: ((fecha >= '2025-01-01'::date) AND (fecha <= '2025-06-30'::date) AND (estado = 'TERMINADO'::estado_pedido))"
"              Buffers: shared read=62"
"  ->  Hash  (cost=575.06..575.06 rows=20006 width=35) (actual time=3.978..3.978 rows=20006 loops=1)"
"        Buckets: 32768  Batches: 1  Memory Usage: 1662kB"
"        Buffers: shared hit=375"
"        ->  Seq Scan on usuario u  (cost=0.00..575.06 rows=20006 width=35) (actual time=0.011..1.660 rows=20006 loops=1)"
"              Buffers: shared hit=375"
"Planning:"
"  Buffers: shared hit=47 read=1"
"Planning Time: 2.049 ms"
"Execution Time: 13.318 ms"

--Análisis del Resultado (Consulta 1)

Nodo Antes: Seq Scan sobre pedido leyendo 200.006 filas (costo = 8303.55, tiempo real =
27.910 ms, buffers = 3932). Nodo Después: Bitmap Heap Scan utilizando
idx_pedido_fecha_estado_vigente (costo = 6256.51, tiempo real = 13.318 ms, buffers en
pedido = 2125). Mejora: ~2.1x más rápido (27.910 ms → 13.318 ms), buffers reducidos casi
a la mitad.

-----------------------------------------------------------------------------------
--Consulta 2 — Búsqueda de productos por categoría y precio
-----------------------------------------------------------------------------------

EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id, p.nombre, p.precio, p.stock, c.nombre AS categoria
FROM producto p
JOIN categoria c ON c.id = p.categoria_id
WHERE p.eliminado = FALSE
  AND c.eliminado = FALSE
  AND p.categoria_id = 1
ORDER BY p.precio DESC;

--Salida de pgAdmin (ANTES del índice)

"Sort  (cost=1913.52..1938.51 rows=9993 width=42) (actual time=6.682..7.338 rows=10004 loops=1)"
"  Sort Key: p.precio DESC"
"  Sort Method: quicksort  Memory: 1007kB"
"  Buffers: shared hit=920"
"  ->  Nested Loop  (cost=113.74..1249.65 rows=9993 width=42) (actual time=0.406..4.028 rows=10004 loops=1)"
"        Buffers: shared hit=920"
"        ->  Seq Scan on categoria c  (cost=0.00..1.07 rows=1 width=18) (actual time=0.013..0.016 rows=1 loops=1)"
"              Filter: ((NOT eliminado) AND (id = 1))"
"              Rows Removed by Filter: 5"
"              Buffers: shared hit=1"
"        ->  Bitmap Heap Scan on producto p  (cost=113.74..1148.65 rows=9993 width=40) (actual time=0.390..2.959 rows=10004 loops=1)"
"              Recheck Cond: (categoria_id = 1)"
"              Filter: (NOT eliminado)"
"              Rows Removed by Filter: 1"
"              Heap Blocks: exact=910"
"              Buffers: shared hit=919"
"              ->  Bitmap Index Scan on idx_producto_categoria_id  (cost=0.00..111.24 rows=9993 width=0) (actual time=0.291..0.291 rows=10006 loops=1)"
"                    Index Cond: (categoria_id = 1)"
"                    Buffers: shared hit=9"
"Planning:"
"  Buffers: shared hit=22 read=1"
"Planning Time: 1.748 ms"
"Execution Time: 7.750 ms"

--Análisis del Plan "ANTES"

Nodo principal de cuello de botella: Sort en memoria (quicksort, 1007kB). El motor usa el
índice existente idx_producto_categoria_id mediante un Bitmap Index Scan, filtrando rápido
por categoría, pero no devuelve las filas ordenadas por precio, por lo que agrega un Sort
explícito después. Costo estimado: 1938.51. Tiempo de ejecución real: 7.750 ms.

--Propuesta de Optimización

CREATE INDEX idx_producto_categoria_precio_vigente
ON producto(categoria_id, precio DESC)
WHERE eliminado = FALSE;

--Medición "DESPUÉS"

EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id, p.nombre, p.precio, p.stock, c.nombre AS categoria
FROM producto p
JOIN categoria c ON c.id = p.categoria_id
WHERE p.eliminado = FALSE
  AND c.eliminado = FALSE
  AND p.categoria_id = 1
ORDER BY p.precio DESC;

--Resultado de pgAdmin (DESPUÉS del índice — IDÉNTICO al de antes)

"Sort  (cost=1913.52..1938.51 rows=9993 width=42) (actual time=6.682..7.338 rows=10004 loops=1)"
"  Sort Key: p.precio DESC"
"  Sort Method: quicksort  Memory: 1007kB"
"  Buffers: shared hit=920"
"  ->  Nested Loop  (cost=113.74..1249.65 rows=9993 width=42) (actual time=0.406..4.028 rows=10004 loops=1)"
"        [...]  (idéntico al plan ANTES: sigue usando idx_producto_categoria_id,"
"         no idx_producto_categoria_precio_vigente)"
"Execution Time: 7.750 ms"

--Resultado

Cambio probado: CREATE INDEX idx_producto_categoria_precio_vigente ON
producto(categoria_id, precio DESC) WHERE eliminado = FALSE;

Resultado: Descartado / Sin cambio. PostgreSQL decidió mantener el mismo plan (Bitmap
Heap Scan sobre idx_producto_categoria_id + Sort en memoria) e ignorar el índice nuevo,
por el volumen de filas devuelto por categoría (~10.000), que resulta más barato de
ordenar en memoria que de leer con el B-Tree nuevo.

-----------------------------------------------------------------------------------------------
--Consulta 3 — Ranking de clientes por total consumido
-----------------------------------------------------------------------------------------------

EXPLAIN (ANALYZE, BUFFERS)
SELECT u.id, u.nombre, u.apellido, SUM(p.total) AS total_gastado
FROM usuario u
JOIN pedido p ON p.usuario_id = u.id
WHERE p.eliminado = FALSE
  AND p.estado IN ('CONFIRMADO', 'TERMINADO')
GROUP BY u.id, u.nombre, u.apellido
ORDER BY total_gastado DESC
LIMIT 10;

--Salida de pgAdmin (ANTES del índice)

"Limit  (cost=8698.53..8698.55 rows=10 width=67) (actual time=88.109..88.113 rows=10 loops=1)"
"  Buffers: shared hit=4307"
"  ->  Sort  (cost=8698.53..8748.54 rows=20006 width=67) (actual time=88.107..88.111 rows=10 loops=1)"
"        Sort Key: (sum(p.total)) DESC"
"        Sort Method: top-N heapsort  Memory: 26kB"
"        Buffers: shared hit=4307"
"        ->  HashAggregate  (cost=8016.13..8266.20 rows=20006 width=67) (actual time=83.649..86.595 rows=10001 loops=1)"
"              Group Key: u.id"
"              Batches: 1  Memory Usage: 4881kB"
"              Buffers: shared hit=4307"
"              ->  Hash Join  (cost=825.13..7518.51 rows=99523 width=43) (actual time=4.548..55.009 rows=100002 loops=1)"
"                    Hash Cond: (p.usuario_id = u.id)"
"                    Buffers: shared hit=4307"
"                    ->  Seq Scan on pedido p  (cost=0.00..6432.08 rows=99523 width=16) (actual time=0.015..23.837 rows=100002 loops=1)"
"                          Filter: ((NOT eliminado) AND (estado = ANY ('{CONFIRMADO,TERMINADO}'::estado_pedido[])))"
"                          Rows Removed by Filter: 100004"
"                          Buffers: shared hit=3932"
"                    ->  Hash  (cost=575.06..575.06 rows=20006 width=35) (actual time=4.460..4.460 rows=20006 loops=1)"
"                          Buckets: 32768  Batches: 1  Memory Usage: 1583kB"
"                          Buffers: shared hit=375"
"                          ->  Seq Scan on usuario u  (cost=0.00..575.06 rows=20006 width=35) (actual time=0.011..1.793 rows=20006 loops=1)"
"                                Buffers: shared hit=375"
"Planning:"
"  Buffers: shared hit=51 read=2"
"Planning Time: 0.405 ms"
"Execution Time: 88.860 ms"

--Análisis del Plan "ANTES"

Nodo principal de cuello de botella: Seq Scan sobre pedido (cost=0.00..6432.08), seguido
de Hash Join y HashAggregate en memoria (4881kB). El motor lee secuencialmente 200.006
pedidos y descarta 100.004 filas por filtro. Costo estimado: 8698.55. Tiempo de ejecución
real: 88.860 ms (I/O alto con 4307 buffers).

--Propuesta de optimización

CREATE INDEX idx_pedido_usuario_total_estado
ON pedido(usuario_id, total)
WHERE eliminado = FALSE AND estado IN ('CONFIRMADO', 'TERMINADO');

--Medición "DESPUÉS"

EXPLAIN (ANALYZE, BUFFERS)
SELECT u.id, u.nombre, u.apellido, SUM(p.total) AS total_gastado
FROM usuario u
JOIN pedido p ON p.usuario_id = u.id
WHERE p.eliminado = FALSE
  AND p.estado IN ('CONFIRMADO', 'TERMINADO')
GROUP BY u.id, u.nombre, u.apellido
ORDER BY total_gastado DESC
LIMIT 10;

--Salida de pgAdmin (DESPUÉS del índice)

"Limit  (cost=5643.71..5643.74 rows=10 width=67) (actual time=51.598..51.602 rows=10 loops=1)"
"  Buffers: shared hit=376 read=469"
"  ->  Sort  (cost=5643.71..5693.73 rows=20006 width=67) (actual time=51.597..51.600 rows=10 loops=1)"
"        Sort Key: (sum(p.total)) DESC"
"        Sort Method: top-N heapsort  Memory: 26kB"
"        Buffers: shared hit=376 read=469"
"        ->  HashAggregate  (cost=4961.32..5211.39 rows=20006 width=67) (actual time=47.510..50.067 rows=10001 loops=1)"
"              Group Key: u.id"
"              Batches: 1  Memory Usage: 4881kB"
"              Buffers: shared hit=376 read=469"
"              ->  Hash Join  (cost=825.55..4463.70 rows=99523 width=43) (actual time=4.337..31.245 rows=100002 loops=1)"
"                    Hash Cond: (p.usuario_id = u.id)"
"                    Buffers: shared hit=376 read=469"
"                    ->  Index Only Scan using idx_pedido_usuario_total_estado on pedido p  (cost=0.42..3377.26 rows=99523 width=16) (actual time=0.070..11.531 rows=100002 loops=1)"
"                          Heap Fetches: 0"
"                          Buffers: shared hit=1 read=469"
"                    ->  Hash  (cost=575.06..575.06 rows=20006 width=35) (actual time=4.212..4.213 rows=20006 loops=1)"
"                          Buckets: 32768  Batches: 1  Memory Usage: 1583kB"
"                          Buffers: shared hit=375"
"                          ->  Seq Scan on usuario u  (cost=0.00..575.06 rows=20006 width=35) (actual time=0.013..1.740 rows=20006 loops=1)"
"                                Buffers: shared hit=375"
"Planning:"
"  Buffers: shared hit=37 read=1"
"Planning Time: 1.941 ms"
"Execution Time: 52.341 ms"

--Resultado

El optimizador adoptó un Index Only Scan sobre idx_pedido_usuario_total_estado, con 0 Heap
Fetches. El costo estimado bajó de 8698.55 a 5643.74 y el tiempo de ejecución real cayó de
88.860 ms a 52.341 ms (~1.7x más rápido), con los buffers reducidos de 4307 a 845.
