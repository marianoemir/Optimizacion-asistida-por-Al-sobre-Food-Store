# Parte 4 — Consultas resumen y subconsultas bajo especificación precisa

---

## Consulta A — Cantidad de pedidos vigentes por usuario (agregación)

### Spec precisa (usada para generar el SQL con IA)

> Generá una consulta SQL para PostgreSQL sobre el esquema de Food Store que devuelva,
> para cada usuario vigente (eliminado = FALSE), su id, nombre, apellido, y la cantidad
> de pedidos vigentes (eliminado = FALSE) que realizó — incluyendo a los usuarios que
> no tienen ningún pedido, con cantidad 0. Ordená de mayor a menor cantidad de pedidos.
> No uses SELECT *.

### Versión 1 — Generada por IA (OpenCode), con LEFT JOIN

```sql
SELECT 
    u.id,
    u.nombre,
    u.apellido,
    COUNT(p.id) AS cantidad
FROM 
    usuario u
LEFT JOIN 
    pedido p ON p.usuario_id = u.id AND p.eliminado = FALSE
WHERE 
    u.eliminado = FALSE
GROUP BY 
    u.id,
    u.nombre,
    u.apellido
ORDER BY 
    cantidad DESC;
```

**Resultado:** 20.005 filas (20.006 usuarios totales de la carga masiva + seed, menos 1
usuario dado de baja lógica). Los 5 usuarios originales del seed (Ana, Juan, Lucía,
Mariano, Sofía) encabezan el ranking con 11 pedidos cada uno. Se confirmó que existen
usuarios con `cantidad = 0` (últimas filas del resultado, ej. Usuario_19996 a
Usuario_20000), validando que el `LEFT JOIN` no descarta usuarios sin pedidos.

### Versión 2 — Alternativa propia, con subconsulta correlacionada

```sql
SELECT
    u.id,
    u.nombre,
    u.apellido,
    (
        SELECT COUNT(*)
        FROM pedido p
        WHERE p.usuario_id = u.id
          AND p.eliminado = FALSE
    ) AS cantidad
FROM usuario u
WHERE u.eliminado = FALSE
ORDER BY cantidad DESC;
```

**Resultado:** 20.005 filas, idéntico patrón de datos (mismo top 5, mismos usuarios en 0).

### Verificación de equivalencia (EXCEPT, en ambos sentidos)

```sql
-- Sentido 1: filas en Versión 1 que no están en Versión 2
(
    SELECT u.id, u.nombre, u.apellido, COUNT(p.id) AS cantidad
    FROM usuario u
    LEFT JOIN pedido p ON p.usuario_id = u.id AND p.eliminado = FALSE
    WHERE u.eliminado = FALSE
    GROUP BY u.id, u.nombre, u.apellido
)
EXCEPT
(
    SELECT u.id, u.nombre, u.apellido,
        (SELECT COUNT(*) FROM pedido p WHERE p.usuario_id = u.id AND p.eliminado = FALSE) AS cantidad
    FROM usuario u
    WHERE u.eliminado = FALSE
);
-- Resultado: 0 filas

-- Sentido 2: filas en Versión 2 que no están en Versión 1
(
    SELECT u.id, u.nombre, u.apellido,
        (SELECT COUNT(*) FROM pedido p WHERE p.usuario_id = u.id AND p.eliminado = FALSE) AS cantidad
    FROM usuario u
    WHERE u.eliminado = FALSE
)
EXCEPT
(
    SELECT u.id, u.nombre, u.apellido, COUNT(p.id) AS cantidad
    FROM usuario u
    LEFT JOIN pedido p ON p.usuario_id = u.id AND p.eliminado = FALSE
    WHERE u.eliminado = FALSE
    GROUP BY u.id, u.nombre, u.apellido
);
-- Resultado: 0 filas
```

**✅ Equivalencia verificada:** ambas direcciones del `EXCEPT` devuelven 0 filas.

---

## Consulta B — Productos con precio por encima del promedio de su categoría (subconsulta)

### Spec precisa (usada para generar el SQL con IA)

> Generá una consulta SQL para PostgreSQL sobre el esquema de Food Store que devuelva,
> para cada producto vigente (eliminado = FALSE) cuya categoría también esté vigente
> (eliminado = FALSE), el id del producto, su nombre, su precio, y el nombre de su
> categoría — pero solo para los productos cuyo precio sea mayor al precio promedio
> de los productos vigentes de esa misma categoría. Ordená de mayor a menor precio.
> No uses SELECT *.

### Versión 1 — Generada por IA (OpenCode), con subconsulta correlacionada

```sql
SELECT 
    p.id,
    p.nombre,
    p.precio,
    c.nombre AS categoria
FROM 
    producto p
JOIN 
    categoria c ON c.id = p.categoria_id
WHERE 
    p.eliminado = FALSE 
    AND c.eliminado = FALSE
    AND p.precio > (
        SELECT AVG(p2.precio)
        FROM producto p2
        WHERE p2.categoria_id = p.categoria_id 
          AND p2.eliminado = FALSE
    )
ORDER BY 
    p.precio DESC;
```

**Resultado:** 25.016 filas. **Tiempo de ejecución: ~49.2 segundos.**

### Versión 2 — Alternativa propia, con JOIN a tabla derivada

```sql
SELECT p.id, p.nombre, p.precio, c.nombre AS categoria
FROM producto p
JOIN categoria c ON c.id = p.categoria_id
JOIN (
    SELECT categoria_id, AVG(precio) AS precio_promedio
    FROM producto
    WHERE eliminado = FALSE
    GROUP BY categoria_id
) prom ON prom.categoria_id = p.categoria_id
WHERE p.eliminado = FALSE
  AND c.eliminado = FALSE
  AND p.precio > prom.precio_promedio
ORDER BY p.precio DESC;
```

**Resultado:** 25.016 filas (idéntico). **Tiempo de ejecución: ~0.09 segundos.**

### Hallazgo de rendimiento (no pedido por la consigna, pero relevante)

La Versión 1 (subconsulta correlacionada) recalcula el promedio de la categoría **una
vez por cada uno de los 50.018 productos evaluados**, mientras que la Versión 2 calcula
el promedio de cada categoría **una sola vez** (agrupando primero, solo 6 categorías) y
luego lo reutiliza vía JOIN. Esta diferencia estructural explica una mejora de **~546x**
en tiempo de ejecución (49.2 s → 0.09 s) para el mismo resultado exacto — un ejemplo
claro de que dos consultas SQL-equivalentes pueden tener costos de ejecución radicalmente
distintos según cómo estén escritas, más allá de los índices disponibles.

### Verificación de equivalencia (EXCEPT, en ambos sentidos)

```sql
-- Sentido 1: filas en Versión 1 que no están en Versión 2
(
    SELECT p.id, p.nombre, p.precio, c.nombre AS categoria
    FROM producto p
    JOIN categoria c ON c.id = p.categoria_id
    WHERE p.eliminado = FALSE AND c.eliminado = FALSE
      AND p.precio > (
          SELECT AVG(p2.precio) FROM producto p2
          WHERE p2.categoria_id = p.categoria_id AND p2.eliminado = FALSE
      )
)
EXCEPT
(
    SELECT p.id, p.nombre, p.precio, c.nombre AS categoria
    FROM producto p
    JOIN categoria c ON c.id = p.categoria_id
    JOIN (
        SELECT categoria_id, AVG(precio) AS precio_promedio
        FROM producto WHERE eliminado = FALSE GROUP BY categoria_id
    ) prom ON prom.categoria_id = p.categoria_id
    WHERE p.eliminado = FALSE AND c.eliminado = FALSE
      AND p.precio > prom.precio_promedio
);
-- Resultado: 0 filas

-- Sentido 2: filas en Versión 2 que no están en Versión 1
(
    SELECT p.id, p.nombre, p.precio, c.nombre AS categoria
    FROM producto p
    JOIN categoria c ON c.id = p.categoria_id
    JOIN (
        SELECT categoria_id, AVG(precio) AS precio_promedio
        FROM producto WHERE eliminado = FALSE GROUP BY categoria_id
    ) prom ON prom.categoria_id = p.categoria_id
    WHERE p.eliminado = FALSE AND c.eliminado = FALSE
      AND p.precio > prom.precio_promedio
)
EXCEPT
(
    SELECT p.id, p.nombre, p.precio, c.nombre AS categoria
    FROM producto p
    JOIN categoria c ON c.id = p.categoria_id
    WHERE p.eliminado = FALSE AND c.eliminado = FALSE
      AND p.precio > (
          SELECT AVG(p2.precio) FROM producto p2
          WHERE p2.categoria_id = p.categoria_id AND p2.eliminado = FALSE
      )
);
-- Resultado: 0 filas
```

**✅ Equivalencia verificada:** ambas direcciones del `EXCEPT` devuelven 0 filas.
