-- PROTOCOLO DE SEGURIDAD: Carga masiva dentro de una transacción
BEGIN;

-- 1. Cargar 20.000 Usuarios
-- Cumple con el CHECK chk_usuario_mail_formato y tiene nombre y apellido separadamente
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

-- 2. Cargar 50.000 Productos
-- Se distribuyen entre las categorías existentes en la base
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
    ORDER BY id 
    OFFSET (i % (SELECT GREATEST(COUNT(*), 1) FROM categoria)) 
    LIMIT 1
) c;

-- 3. Cargar 200.000 Pedidos
INSERT INTO pedido (fecha, estado, total, forma_pago, usuario_id, eliminado)
SELECT 
    CURRENT_DATE - (i % 365) AS fecha,
    (ARRAY['PENDIENTE', 'CONFIRMADO', 'TERMINADO', 'CANCELADO']::estado_pedido[])[1 + (i % 4)] AS estado,
    0.00 AS total, -- Se actualizará luego al calcular subtotales
    (ARRAY['TARJETA', 'TRANSFERENCIA', 'EFECTIVO']::forma_pago[])[1 + (i % 3)] AS forma_pago,
    u.id AS usuario_id,
    FALSE AS eliminado
FROM generate_series(1, 200000) AS i
CROSS JOIN LATERAL (
    SELECT id 
    FROM usuario 
    ORDER BY id 
    OFFSET (i % 20000) 
    LIMIT 1
) u;

-- 4. Cargar Detalles de Pedidos (2 renglones por pedido = 400.000 filas)
-- Desactivamos temporalmente el trigger de recálculo masivo para acelerar el INSERT
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

-- Reactivamos el trigger
ALTER TABLE detalle_pedido ENABLE TRIGGER trg_total_ins;

-- 5. Actualizar los totales de los pedidos de forma eficiente
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

-- Actualizar estadísticas del optimizador de PostgreSQL (Requisito de la Cátedra)
ANALYZE categoria;
ANALYZE producto;
ANALYZE usuario;
ANALYZE pedido;
ANALYZE detalle_pedido;