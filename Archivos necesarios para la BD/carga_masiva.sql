-- ============================================================
-- FOOD STORE — carga_masiva.sql (CORREGIDO)
-- Correr SOLO sobre copia_trabajo, nunca sobre plantilla_food_store
-- Protocolo de seguridad: respaldo previo obligatorio (hay ALTER TABLE)
-- ============================================================

-- pg_dump copia_trabajo > respaldos/copia_trabajo_antes_carga_masiva.sql
-- (correr esta línea en la terminal ANTES de seguir, no es parte del script SQL)

BEGIN;

-- ============================================================
-- 1. Cargar 20.000 usuarios
-- ============================================================
INSERT INTO usuario (nombre, apellido, mail, celular, contrasena, rol, eliminado)
SELECT
    'Usuario_' || i AS nombre,
    'Apellido_' || i AS apellido,
    'usuario_' || i || '@test.com' AS mail,
    '261' || LPAD(i::text, 7, '0') AS celular,
    '$2a$10$e8.y7/S8S.a...hash_ficticio' AS contrasena,
    'USUARIO'::rol AS rol,
    FALSE AS eliminado
FROM generate_series(1, 20000) AS i;

-- ============================================================
-- 2. Cargar 50.000 productos
--    CORREGIDO: se filtran categorías vigentes (eliminado = FALSE)
--    para no repartir productos nuevos en "Descontinuados".
-- ============================================================
INSERT INTO producto (nombre, precio, descripcion, stock, disponible, categoria_id, eliminado)
SELECT
    'Producto_' || i AS nombre,
    ROUND((500 + (random() * 4500))::numeric, 2) AS precio,
    'Descripción del producto masivo número ' || i AS descripcion,
    (random() * 200)::int AS stock,
    TRUE AS disponible,
    c.id AS categoria_id,
    FALSE AS eliminado
FROM generate_series(1, 50000) AS i
CROSS JOIN LATERAL (
    SELECT id
    FROM categoria
    WHERE eliminado = FALSE
    ORDER BY id
    OFFSET (i % (SELECT GREATEST(COUNT(*), 1) FROM categoria WHERE eliminado = FALSE))
    LIMIT 1
) c;

-- ============================================================
-- 3. Cargar 200.000 pedidos
--    CORREGIDO (fecha): se usa un rango FIJO de 2 años
--    ('2025-01-01' en adelante) en vez de CURRENT_DATE, para que
--    cualquier consulta con fechas fijas (ej. Consulta 1 de Andrés,
--    BETWEEN '2025-01-01' AND '2025-06-30') tenga garantizado
--    devolver filas sin importar qué día se corra este script.
--    CORREGIDO (usuario_id): se reemplaza el CROSS JOIN LATERAL con
--    ORDER BY + OFFSET (que se repetía 200.000 veces) por aritmética
--    directa sobre IDs secuenciales — mismo patrón que ya se usaba
--    para producto_id en el paso 4, y mucho más rápido.
-- ============================================================
INSERT INTO pedido (fecha, estado, total, forma_pago, usuario_id, eliminado)
SELECT
    ('2025-01-01'::date + (i % 500)) AS fecha,
    (ARRAY['PENDIENTE', 'CONFIRMADO', 'TERMINADO', 'CANCELADO']::estado_pedido[])[1 + (i % 4)] AS estado,
    0.00 AS total,
    (ARRAY['TARJETA', 'TRANSFERENCIA', 'EFECTIVO']::forma_pago[])[1 + (i % 3)] AS forma_pago,
    ((i % 20000) + 1) AS usuario_id,
    FALSE AS eliminado
FROM generate_series(1, 200000) AS i;

-- ============================================================
-- 4. Cargar detalles de pedidos (2 renglones por pedido = 400.000 filas)
--    Sin cambios: ya usaba aritmética directa para producto_id.
-- ============================================================
ALTER TABLE detalle_pedido DISABLE TRIGGER trg_total_ins;

INSERT INTO detalle_pedido (cantidad, precio_unitario, subtotal, pedido_id, producto_id, eliminado)
SELECT
    d.cantidad,
    p.precio AS precio_unitario,
    ROUND((d.cantidad * p.precio)::numeric, 2) AS subtotal,
    d.pedido_id,
    d.producto_id,
    FALSE AS eliminado
FROM (
    SELECT
        p_id AS pedido_id,
        ((p_id * 7 + k) % 50000) + 1 AS producto_id,
        1 + (k % 5) AS cantidad
    FROM generate_series(1, 200000) AS p_id
    CROSS JOIN generate_series(1, 2) AS k
) d
JOIN producto p ON p.id = d.producto_id;

ALTER TABLE detalle_pedido ENABLE TRIGGER trg_total_ins;

-- ============================================================
-- 5. Actualizar los totales de los pedidos
-- ============================================================
WITH subtotales AS (
    SELECT pedido_id, SUM(subtotal) AS total_calculado
    FROM detalle_pedido
    WHERE eliminado = FALSE
    GROUP BY pedido_id
)
UPDATE pedido p
SET total = s.total_calculado
FROM subtotales s
WHERE p.id = s.pedido_id;

COMMIT;

-- ============================================================
-- Actualizar estadísticas del optimizador (obligatorio antes de medir)
-- ============================================================
ANALYZE categoria;
ANALYZE producto;
ANALYZE usuario;
ANALYZE pedido;
ANALYZE detalle_pedido;

-- ============================================================
-- Verificación rápida post-carga (correr aparte, no hace falta transacción)
-- ============================================================
-- SELECT COUNT(*) FROM usuario;          -- esperado: 20006 (20000 + 6 del seed)
-- SELECT COUNT(*) FROM producto;         -- esperado: 50018 (50000 + 18 del seed)
-- SELECT COUNT(*) FROM pedido;           -- esperado: 200006 (200000 + 6 del seed)
-- SELECT COUNT(*) FROM detalle_pedido;   -- esperado: 400000+ (más los del seed)
-- SELECT COUNT(*) FROM pedido
--   WHERE fecha BETWEEN '2025-01-01' AND '2025-06-30'; -- debe dar > 0
