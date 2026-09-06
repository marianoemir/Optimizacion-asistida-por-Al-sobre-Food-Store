# Tabla de resultados — sección 2.2 (verificada y corregida)

| # | Consulta | Plan antes (nodo, cost, tiempo real) | Cambio aplicado | Plan después (nodo, cost, tiempo real) | Mejora |
|---|---|---|---|---|---|
| 1 | Historial de pedidos por rango de fechas y estado | **Seq Scan** on pedido (Hash Join)<br>Cost: 825.13..8303.55<br>Buffers: 3932<br>Tiempo: 27.910 ms | `CREATE INDEX idx_pedido_fecha_estado_vigente ON pedido(fecha, estado) WHERE eliminado = FALSE;` | **Bitmap Heap Scan** on pedido usando el índice (Hash Join)<br>Cost: 1969.51..6256.51<br>Buffers: 2125 (2063 hit + 62 read)<br>Tiempo: 13.318 ms | **~2.1x más rápido** (27.910 ms → 13.318 ms), buffers reducidos casi a la mitad |
| 2 | Búsqueda de productos por categoría y precio | **Sort** (quicksort, 1007kB) + Bitmap Heap Scan on producto (índice existente `idx_producto_categoria_id`)<br>Cost: 1913.52..1938.51<br>Buffers: 920<br>Tiempo: 7.750 ms | `CREATE INDEX idx_producto_categoria_precio_vigente ON producto(categoria_id, precio DESC) WHERE eliminado = FALSE;` | **Sin cambio.** El optimizador descartó el índice nuevo y mantuvo el mismo plan (Sort + Bitmap Heap Scan con el índice viejo)<br>Cost: 1913.52..1938.51<br>Buffers: 920<br>Tiempo: 7.750 ms | **Descartado / Sin cambio.** PostgreSQL prefirió mantener el ordenamiento en memoria por el volumen de filas devuelto (~10.000), que resulta más barato que usar el índice B-Tree nuevo |
| 3 | Ranking de clientes por total gastado | **Seq Scan** on pedido + Hash Join + HashAggregate<br>Cost: 8698.53..8698.55<br>Buffers: 4307<br>Tiempo: 88.860 ms | `CREATE INDEX idx_pedido_usuario_total_estado ON pedido(usuario_id, total) WHERE eliminado = FALSE AND estado IN ('CONFIRMADO', 'TERMINADO');` | **Index Only Scan** on pedido (Heap Fetches: 0) + Hash Join + HashAggregate<br>Cost: 5643.71..5643.74<br>Buffers: 845 (376 hit + 469 read)<br>Tiempo: 52.341 ms | **~1.7x más rápido** (88.860 ms → 52.341 ms), buffers reducidos en más del 80% |

---

**Nota metodológica:** estos números corresponden a una segunda medición sobre `copia_trabajo`
recreada después de corregir un bug en `carga_masiva.sql` (las fechas de los pedidos no
caían en el rango que usa la Consulta 1, y el paso de carga de detalles asumía IDs de
pedido incorrectos). Los valores difieren levemente de una primera corrida por el volumen
de datos y la aleatoriedad de `random()` en la generación, pero las conclusiones sobre
qué índices ayudan y cuáles no se mantienen consistentes.
