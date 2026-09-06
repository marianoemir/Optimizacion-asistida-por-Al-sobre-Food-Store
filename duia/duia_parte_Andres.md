# Declaración de Uso de IA (DUIA) — Parte 1 y Parte 2

**Nombre y Apellido:** Andrés Fabre
**Rol / Asignación:** Parte 1 (carga masiva) + Parte 2 (laboratorio de optimización)
**Materia:** Base de Datos II (UTN) — Unidad 2: Optimización de Consultas
**Proyecto Integrador:** Food Store (TP3 Semana 3)

---

## Registro de Interacciones y Decisiones con IA

| Herramienta | Para qué se usó | Prompt / Spec (resumen) | Se aceptó / se descartó y por qué |
|---|---|---|---|
| OpenCode / Gemini | Generar script de carga masiva (Parte 1) | *"Generá un script SQL para PostgreSQL que inserte 20.000 usuarios, 50.000 productos y 200.000 pedidos con sus detalles, respetando las restricciones del schema (CHECK, UNIQUE, FK)."* | **Se aceptó, con correcciones posteriores.** Se detectaron y corrigieron 3 problemas tras revisión propia: (1) las fechas de pedido se generaban relativas a `CURRENT_DATE`, sin garantía de caer en el rango fijo usado por la Consulta 1; (2) la carga de `detalle_pedido` asumía que los pedidos nuevos tenían ids 1-200.000, cuando en realidad arrancaban en el id 7 (por los 6 pedidos ya cargados en `data.sql`), corrompiendo esos pedidos originales; (3) la asignación de categoría a los productos no filtraba categorías vigentes. |
| OpenCode / Gemini | Optimización Consulta 1 (Historial de pedidos por fecha y estado) | *"Proponé un índice para filtrar la tabla pedido por rango de fechas, estado = 'TERMINADO' y eliminado = FALSE."* | **Se aceptó.** Se creó el índice parcial compuesto `idx_pedido_fecha_estado_vigente`. El optimizador pasó de un `Seq Scan` leyendo 200.006 filas a un `Bitmap Heap Scan`, reduciendo el tiempo de ejecución real de **27.910 ms** a **13.318 ms** (~2.1x más rápido, devuelve 18.000 filas). |
| OpenCode / Gemini | Optimización Consulta 2 (Catálogo de productos por categoría ordenados por precio) | *"Proponé un índice para evitar el nodo Sort en memoria (quicksort) al filtrar productos por categoría y ordenarlos por precio descendente."* | **Se descartó.** Se creó el índice compuesto `idx_producto_categoria_precio_vigente`, pero en las mediciones con `EXPLAIN ANALYZE` PostgreSQL decidió mantener el mismo plan (`Bitmap Heap Scan` con el índice existente + `Sort` en memoria, quicksort), ignorando el índice nuevo por el volumen devuelto por categoría (~10.000 filas). Se documenta el hallazgo según el criterio de aceptación de la cátedra: tiempo idéntico antes y después (7.750 ms). |
| OpenCode / Gemini | Optimización Consulta 3 (Ranking de clientes por monto gastado) | *"Proponé un índice de cobertura o parcial sobre pedido para optimizar una consulta de agregación SUM(total) con GROUP BY usuario_id sobre pedidos confirmados/terminados."* | **Se aceptó.** Se creó el índice condicional `idx_pedido_usuario_total_estado`. Permitió al motor realizar un `Index Only Scan` con **0 Heap Fetches**, reduciendo el costo estimado de 8698.55 a 5643.74 y el tiempo de ejecución real de **88.860 ms** a **52.341 ms** (~1.7x más rápido). |

---


