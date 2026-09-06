# Declaración de Uso de IA (DUIA) — Parte 4

**Rol / Asignación:** Parte 4 — Consultas resumen y subconsultas bajo especificación precisa
**Materia:** Base de Datos II (UTN) — Unidad 2: Optimización de Consultas
**Proyecto Integrador:** Food Store (TP3 Semana 3)

---

## Registro de Interacciones y Decisiones con IA

| Herramienta | Para qué se usó | Prompt / Spec (resumen) | Se aceptó / se descartó y por qué |
|---|---|---|---|
| OpenCode | Consulta A: cantidad de pedidos vigentes por usuario, incluyendo usuarios con 0 pedidos | *"Generá una consulta que devuelva id, nombre, apellido y cantidad de pedidos vigentes por usuario vigente, incluyendo a los que no tienen pedidos con cantidad 0. Ordená de mayor a menor. No SELECT *."* | **Se aceptó.** Devolvió un `LEFT JOIN` entre `usuario` y `pedido` con `COUNT` y `GROUP BY`. Se verificó que efectivamente incluye usuarios con `cantidad = 0` (20.005 filas totales) y que el orden es correcto. |
| OpenCode | Consulta B: productos con precio por encima del promedio de su categoría | *"Generá una consulta que devuelva productos vigentes de categorías vigentes cuyo precio supere el promedio de su propia categoría. Ordená de mayor a menor precio. No SELECT *."* | **Se aceptó como solución correcta**, aunque se detectó un problema de rendimiento no cubierto por la spec: usa una subconsulta correlacionada que recalcula el promedio por cada producto evaluado (~49.2 segundos de ejecución sobre 50.018 productos). Se documenta como hallazgo adicional, no se descarta la consulta porque el resultado es correcto — solo ineficiente a esta escala. |

---

## Verificación de equivalencia

Para ambas consultas se escribió una segunda versión propia con estructura distinta
(subconsulta vs. JOIN) y se verificó la equivalencia de resultados con `EXCEPT` en los
dos sentidos, obteniendo 0 filas de diferencia en los cuatro casos. Detalle completo en
`consultas_parte4.md`.


