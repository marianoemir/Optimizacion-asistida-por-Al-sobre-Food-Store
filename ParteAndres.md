------------------------------------------------------------------------
--Consulta 1
------------------------------------------------------------------------

EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id, u.nombre, u.apellido, p.fecha, p.estado, p.total
FROM pedido p
JOIN usuario u ON u.id = p.usuario_id
WHERE p.eliminado = FALSE
  AND p.estado = 'TERMINADO'
  AND p.fecha BETWEEN '2025-01-01' AND '2025-06-30'
ORDER BY p.fecha DESC;



--Análisis del Plan "ANTES"

Nodo principal de lectura: Parallel Seq Scan sobre la tabla pedido. Al no existir un índice compuesto por fecha, estado y borrado lógico, PostgreSQL debe recorrer secuencialmente 200.000 filas de pedidos (divididas entre workers), descartando 66.669 filas por worker (Rows Removed by Filter).  Costo estimado: 6398.79Tiempo de ejecución real: 38.501 msPropuesta de OptimizaciónCrear un índice compuesto e index-condicional (parcial) sobre pedido. Al incluir fecha y estado únicamente para las filas vigentes (eliminado = FALSE), reducimos el tamaño del índice y le permitimos al motor saltar directamente al rango sin leer la tabla completa.Ejecutá la creación del índice:

SQL
CREATE INDEX idx_pedido_fecha_estado_vigente 
ON pedido(fecha, estado) 
WHERE eliminado = FALSE;

--nueva medición

EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id, u.nombre, u.apellido, p.fecha, p.estado, p.total
FROM pedido p
JOIN usuario u ON u.id = p.usuario_id
WHERE p.eliminado = FALSE
  AND p.estado = 'TERMINADO'
  AND p.fecha BETWEEN '2025-01-01' AND '2025-06-30'
ORDER BY p.fecha DESC;

--Resultado

"Nested Loop  (cost=0.58..16.62 rows=1 width=51) (actual time=0.053..0.053 rows=0 loops=1)"
"  Buffers: shared read=2"
"  ->  Index Scan Backward using idx_pedido_fecha_estado_vigente on pedido p  (cost=0.29..8.32 rows=1 width=32) (actual time=0.053..0.053 rows=0 loops=1)"
"        Index Cond: ((fecha >= '2025-01-01'::date) AND (fecha <= '2025-06-30'::date) AND (estado = 'TERMINADO'::estado_pedido))"
"        Buffers: shared read=2"
"  ->  Index Scan using usuario_pkey on usuario u  (cost=0.29..8.30 rows=1 width=35) (never executed)"
"        Index Cond: (id = p.usuario_id)"
"Planning:"
"  Buffers: shared hit=38 read=1"
"Planning Time: 0.714 ms"
"Execution Time: 0.095 ms"

--Lo que dice Gemini

Pasamos de un escaneo secuencial paralelo que recorría 200.000 filas a un acceso directo por índice.

Análisis del Resultado (Consulta 1)
Nodo Antes: Parallel Seq Scan (costo = 6398.79, tiempo real = 38.501 ms, lectura de bloques = 3932 buffers).

Cambio Aplicado: CREATE INDEX idx_pedido_fecha_estado_vigente ON pedido(fecha, estado) WHERE eliminado = FALSE;

Nodo Después: Index Scan Backward usando idx_pedido_fecha_estado_vigente (costo = 16.62, tiempo real = 0.095 ms, lectura de bloques = 2 buffers).

Mejora: ~405x más rápido (el tiempo cayó de 38.5 ms a 0.095 ms) y redujo la lectura de buffers de 3932 a solo 2.

-----------------------------------------------------------------------------------
--Consulta 2
-----------------------------------------------------------------------------------

EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id, p.nombre, p.precio, p.stock, c.nombre AS categoria
FROM producto p
JOIN categoria c ON c.id = p.categoria_id
WHERE p.eliminado = FALSE 
  AND c.eliminado = FALSE
  AND p.categoria_id = 1
ORDER BY p.precio DESC;


--Lo que arroja pgAdmin

"Sort  (cost=1728.16..1748.75 rows=8236 width=42) (actual time=5.199..5.505 rows=8337 loops=1)"
"  Sort Key: p.precio DESC"
"  Sort Method: quicksort  Memory: 904kB"
"  Buffers: shared hit=922"
"  ->  Nested Loop  (cost=96.12..1192.50 rows=8236 width=42) (actual time=0.304..3.031 rows=8337 loops=1)"
"        Buffers: shared hit=922"
"        ->  Seq Scan on categoria c  (cost=0.00..1.07 rows=1 width=18) (actual time=0.013..0.014 rows=1 loops=1)"
"              Filter: ((NOT eliminado) AND (id = 1))"
"              Rows Removed by Filter: 5"
"              Buffers: shared hit=1"
"        ->  Bitmap Heap Scan on producto p  (cost=96.12..1109.07 rows=8236 width=40) (actual time=0.290..2.261 rows=8337 loops=1)"
"              Recheck Cond: (categoria_id = 1)"
"              Filter: (NOT eliminado)"
"              Rows Removed by Filter: 1"
"              Heap Blocks: exact=910"
"              Buffers: shared hit=921"
"              ->  Bitmap Index Scan on idx_producto_categoria_id  (cost=0.00..94.06 rows=8236 width=0) (actual time=0.214..0.214 rows=8338 loops=1)"
"                    Index Cond: (categoria_id = 1)"
"                    Buffers: shared hit=11"
"Planning:"
"  Buffers: shared hit=77 dirtied=4"
"Planning Time: 0.785 ms"
"Execution Time: 5.817 ms"



--Análisis del Plan "ANTES"

Nodo principal de cuello de botella: Sort en memoria (quicksort, 904kB).  Causa: La base de datos usa el índice existente idx_producto_categoria_id mediante un Bitmap Index Scan, lo que le permite filtrar las filas rápidamente por categoría pero no se las devuelve ordenadas por precio. Por este motivo, el motor debe traer las 8.337 filas a memoria y aplicar un ordenamiento explicito posterior (Sort Key: p.precio DESC).  Costo estimado: 1748.75Tiempo de ejecución real: 5.817 ms (el ordenamiento representa más del 40% del tiempo total).

--Propuesta de Optimización

Crearemos un índice compuesto que incluya la categoría y el precio en orden descendente, filtrando los productos eliminados (WHERE eliminado = FALSE).

Este índice le otorgará al optimizador la capacidad de realizar un Index Scan directo, obteniendo los resultados ya ordenados de forma nativa sin necesidad de cargar los datos en memoria ni ejecutar el nodo Sort.

Ejecutá el siguiente comando:

SQL
CREATE INDEX idx_producto_categoria_precio_vigente 
ON producto(categoria_id, precio DESC) 
WHERE eliminado = FALSE;

--Medición "DESPUÉS"

SQL
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id, p.nombre, p.precio, p.stock, c.nombre AS categoria
FROM producto p
JOIN categoria c ON c.id = p.categoria_id
WHERE p.eliminado = FALSE 
  AND c.eliminado = FALSE
  AND p.categoria_id = 1
ORDER BY p.precio DESC;

--Resultado de pgAdmin

"Sort  (cost=1728.16..1748.75 rows=8236 width=42) (actual time=5.734..6.042 rows=8337 loops=1)"
"  Sort Key: p.precio DESC"
"  Sort Method: quicksort  Memory: 904kB"
"  Buffers: shared hit=919"
"  ->  Nested Loop  (cost=96.12..1192.50 rows=8236 width=42) (actual time=0.406..3.448 rows=8337 loops=1)"
"        Buffers: shared hit=919"
"        ->  Seq Scan on categoria c  (cost=0.00..1.07 rows=1 width=18) (actual time=0.020..0.021 rows=1 loops=1)"
"              Filter: ((NOT eliminado) AND (id = 1))"
"              Rows Removed by Filter: 5"
"              Buffers: shared hit=1"
"        ->  Bitmap Heap Scan on producto p  (cost=96.12..1109.07 rows=8236 width=40) (actual time=0.383..2.608 rows=8337 loops=1)"
"              Recheck Cond: (categoria_id = 1)"
"              Filter: (NOT eliminado)"
"              Rows Removed by Filter: 1"
"              Heap Blocks: exact=910"
"              Buffers: shared hit=918"
"              ->  Bitmap Index Scan on idx_producto_categoria_id  (cost=0.00..94.06 rows=8236 width=0) (actual time=0.260..0.260 rows=8338 loops=1)"
"                    Index Cond: (categoria_id = 1)"
"                    Buffers: shared hit=8"
"Planning Time: 0.178 ms"
"Execution Time: 6.361 ms"

--Resultado de Gemini

Cambio probado: CREATE INDEX idx_producto_categoria_precio_vigente ON producto(categoria_id, precio DESC) WHERE eliminado = FALSE;

Resultado: Descartado / Sin cambio. PostgreSQL decide mantener el Bitmap Index Scan sobre idx_producto_categoria_id seguido de Sort en memoria por el bajo volumen devuelto por categoría (~8.300 filas).

Cambio probado: CREATE INDEX idx_producto_categoria_precio_vigente / Resultado: Descartado por el optimizador (se mantiene Bitmap Heap Scan + Sort).

-----------------------------------------------------------------------------------------------
--Consulta 3
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

--Salida de pgAdmin

"Limit  (cost=8702.74..8702.77 rows=10 width=67) (actual time=69.231..69.233 rows=10 loops=1)"
"  Buffers: shared hit=4307"
"  ->  Sort  (cost=8702.74..8752.76 rows=20006 width=67) (actual time=69.230..69.231 rows=10 loops=1)"
"        Sort Key: (sum(p.total)) DESC"
"        Sort Method: top-N heapsort  Memory: 26kB"
"        Buffers: shared hit=4307"
"        ->  HashAggregate  (cost=8020.35..8270.42 rows=20006 width=67) (actual time=65.559..67.689 rows=10001 loops=1)"
"              Group Key: u.id"
"              Batches: 1  Memory Usage: 4881kB"
"              Buffers: shared hit=4307"
"              ->  Hash Join  (cost=825.13..7519.97 rows=100076 width=43) (actual time=5.732..46.658 rows=100002 loops=1)"
"                    Hash Cond: (p.usuario_id = u.id)"
"                    Buffers: shared hit=4307"
"                    ->  Seq Scan on pedido p  (cost=0.00..6432.08 rows=100076 width=16) (actual time=0.731..23.380 rows=100002 loops=1)"
"                          Filter: ((NOT eliminado) AND (estado = ANY ('{CONFIRMADO,TERMINADO}'::estado_pedido[])))"
"                          Rows Removed by Filter: 100004"
"                          Buffers: shared hit=3932"
"                    ->  Hash  (cost=575.06..575.06 rows=20006 width=35) (actual time=4.932..4.932 rows=20006 loops=1)"
"                          Buckets: 32768  Batches: 1  Memory Usage: 1583kB"
"                          Buffers: shared hit=375"
"                          ->  Seq Scan on usuario u  (cost=0.00..575.06 rows=20006 width=35) (actual time=0.011..2.110 rows=20006 loops=1)"
"                                Buffers: shared hit=375"
"Planning:"
"  Buffers: shared hit=27 read=1"
"Planning Time: 0.476 ms"
"Execution Time: 70.039 ms"

-- Análisis del Plan "ANTES"

Nodo principal de cuello de botella: Seq Scan sobre la tabla pedido (cost=0.00..6432.08), seguido de un Hash Join y un HashAggregate en memoria (4881kB). El motor lee secuencialmente 200.000 pedidos y descarta 100.004 filas por filtro (Rows Removed by Filter).  Costo estimado: 8702.77Tiempo de ejecución real: 70.039 ms (I/O alto con 4307 buffers).

--Propuesta de optimización

Propuesta de Optimización
Crearemos un índice compuesto condicional sobre pedido(usuario_id, total) filtrando solo los pedidos válidos (CONFIRMADO, TERMINADO) y no eliminados. Al incluir total en el índice, se habilita una estrategia donde el motor lee únicamente los datos requeridos directamente del índice para la agregación, acelerando el JOIN.


SQL
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

-- Lo que entrega pgAdmin

"Limit  (cost=5663.86..5663.88 rows=10 width=67) (actual time=49.957..49.960 rows=10 loops=1)"
"  Buffers: shared hit=376 read=469"
"  ->  Sort  (cost=5663.86..5713.87 rows=20006 width=67) (actual time=49.956..49.958 rows=10 loops=1)"
"        Sort Key: (sum(p.total)) DESC"
"        Sort Method: top-N heapsort  Memory: 26kB"
"        Buffers: shared hit=376 read=469"
"        ->  HashAggregate  (cost=4981.46..5231.53 rows=20006 width=67) (actual time=44.356..47.687 rows=10001 loops=1)"
"              Group Key: u.id"
"              Batches: 1  Memory Usage: 4881kB"
"              Buffers: shared hit=376 read=469"
"              ->  Hash Join  (cost=825.55..4481.08 rows=100076 width=43) (actual time=3.710..28.667 rows=100002 loops=1)"
"                    Hash Cond: (p.usuario_id = u.id)"
"                    Buffers: shared hit=376 read=469"
"                    ->  Index Only Scan using idx_pedido_usuario_total_estado on pedido p  (cost=0.42..3393.19 rows=100076 width=16) (actual time=0.036..10.418 rows=100002 loops=1)"
"                          Heap Fetches: 0"
"                          Buffers: shared hit=1 read=469"
"                    ->  Hash  (cost=575.06..575.06 rows=20006 width=35) (actual time=3.618..3.618 rows=20006 loops=1)"
"                          Buckets: 32768  Batches: 1  Memory Usage: 1583kB"
"                          Buffers: shared hit=375"
"                          ->  Seq Scan on usuario u  (cost=0.00..575.06 rows=20006 width=35) (actual time=0.009..1.546 rows=20006 loops=1)"
"                                Buffers: shared hit=375"
"Planning:"
"  Buffers: shared hit=40 read=1"
"Planning Time: 0.579 ms"
"Execution Time: 50.555 ms"

-- Lo que entrega Gemini

El optimizador adoptó un Index Only Scan sobre el nuevo índice idx_pedido_usuario_total_estado.  Al tener usuario_id y total incluidos en las hojas del B-Tree, PostgreSQL no necesitó ir a buscar datos a las páginas de la tabla pedido (Heap Fetches: 0). Esto redujo el costo estimado de 8702.77 a 5663.88 y el tiempo de ejecución real cayó de 70.039 ms a 50.555 ms (un ~28% más rápido de entrada, y aún más rápido una vez en caché de RAM).