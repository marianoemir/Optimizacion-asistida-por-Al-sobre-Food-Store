# Declaración de Uso de IA (DUIA) — Integrante 1

**Nombre y Apellido:** Andrés Fabre  
**Rol / Asignación:** Integrante 1 — Parte 2: Laboratorio de optimización  
**Materia:** Base de Datos II (UTN) — Unidad 2: Optimización de Consultas  
**Proyecto Integrador:** Food Store (TP3 Semana 3)

\---

## Registro de Interacciones y Decisiones con IA

|Herramienta|Para qué se usó|Prompt / Spec (resumen)|Se aceptó / se descartó y por qué|
|-|-|-|-|
|OpenCode / Gemini|Optimización Consulta 1 (Historial de pedidos por fecha y estado)|*"Proponé un índice para filtrar la tabla pedido por rango de fechas, estado = 'TERMINADO' y eliminado = FALSE."*|**\*\*Se aceptó.\*\* Se creó el índice parcial compuesto `idx\_pedido\_fecha\_estado\_vigente`. El optimizador pasó de un `Seq Scan` leyendo 200.000 filas a un `Bitmap Heap Scan`, reduciendo el tiempo de ejecución de \*\*27.237 ms\*\* a \*\*12.818 ms\*\* (devuelve 18.000 filas).**|
|OpenCode / Gemini|Optimización Consulta 2 (Catálogo de productos por categoría ordenados por precio)|*"Proponé un índice para evitar el nodo Sort en memoria (quicksort) al filtrar productos por categoría y ordenarlos por precio descendente."*|**Se descartó.** Se creó el índice compuesto `idx\\\_producto\\\_categoria\\\_precio\\\_vigente`, pero en las mediciones con `EXPLAIN ANALYZE` PostgreSQL decidió mantener el `Bitmap Heap Scan` + `quicksort` en memoria por el bajo volumen devuelto por categoría (\~8.300 filas). Se documenta el hallazgo según el criterio de aceptación de la cátedra.|
|OpenCode / Gemini|Optimización Consulta 3 (Ranking de clientes por monto gastado)|*"Proponé un índice de cobertura o parcial sobre pedido para optimizar una consulta de agregación SUM(total) con GROUP BY usuario\_id sobre pedidos confirmados/terminados."*|**Se aceptó.** Se creó el índice condicional `idx\\\_pedido\\\_usuario\\\_total\\\_estado`. Permitió al motor realizar un `Index Only Scan` con **0 Heap Fetches**, reduciendo el costo estimado de 8702.77 a 5663.88 y el tiempo de ejecución real de **70.039 ms** a **50.555 ms**.|

\---

## Justificación Técnica para la Defensa Oral

1. **Consulta 1:** Al agregar `(fecha, estado)` con el filtro `WHERE eliminado = FALSE`, se evita escanear 200.000 filas secuencialmente y se responde la consulta leyendo únicamente 2 bloques del índice B-Tree.
2. **Consulta 2:** Es un ejemplo clave de que la presencia de un índice B-Tree no garantiza su uso. El planificador estimó que el costo de un `Bitmap Index Scan` con ordenamiento posterior en memoria (904 kB) era más eficiente que saltar por las hojas del nuevo B-Tree.
3. **Consulta 3:** Incluir la columna `total` en el B-Tree transformó el acceso a la tabla `pedido` en un `Index Only Scan`, evitando lecturas a las páginas de datos en disco (Heap) para calcular la sumatoria.

