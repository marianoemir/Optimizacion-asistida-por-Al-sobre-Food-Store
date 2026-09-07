# Parte 3 — Lectura crítica de planes interpretados por IA

**Integrante 3**
**Materia:** Base de Datos II (UTN) — Unidad 2: Optimización de Consultas
**Proyecto Integrador:** Food Store (TP3 Semana 3)

---

## 1. Plan elegido

Se tomó el plan **"después"** de la Consulta 3 de la Parte 2 (ranking de clientes por
monto gastado, con el índice `idx_pedido_usuario_total_estado` ya aplicado por
Integrante 1), por ser el que presenta más nodos y decisiones del optimizador para
analizar (`Index Only Scan`, `Heap Fetches: 0`, `Hash Join`, `HashAggregate`, `Sort`
top-N, `Limit`).

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT u.id, u.nombre, u.apellido, SUM(p.total) AS total_gastado
FROM usuario u
JOIN pedido p ON p.usuario_id = u.id
WHERE p.eliminado = FALSE
  AND p.estado IN ('CONFIRMADO', 'TERMINADO')
GROUP BY u.id, u.nombre, u.apellido
ORDER BY total_gastado DESC
LIMIT 10;
```

```
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
"Planning Time: 0.579 ms"
"Execution Time: 50.555 ms"
```

## 2. Prompt usado

> "Explicame este plan de ejecución de PostgreSQL en lenguaje natural, nodo por nodo
> (de adentro hacia afuera). Para cada nodo indicá qué hace y por qué el motor lo
> eligió. No tengo más contexto que este texto."

Se le pasó a la IA **únicamente el texto del plan de arriba**, sin la consulta con
alias descriptivos ni el análisis que ya había escrito Integrante 1 en `ParteAndres.md`,
para no contaminar su respuesta con una interpretación previa.

## 3. Respuesta de la IA (íntegra)

1. **Seq Scan en `usuario u`**: lee de forma secuencial los 20.006 registros de la
   tabla `usuario` en memoria caché (`shared hit=375`). Lo eligió porque no hay
   filtros sobre `usuario` y el motor necesita procesarla entera para el JOIN.
2. **Hash**: construye una tabla hash en memoria (1583kB) con las 20.006 filas de
   `usuario`, indexada por la clave de unión, para resolver el JOIN de forma O(1).
3. **Index Only Scan en `pedido p`** (con `idx_pedido_usuario_total_estado`): recorre
   el índice cubriente y obtiene los 100.002 registros que cumplen los filtros,
   logrando `Heap Fetches: 0`. Lo eligió porque el índice contiene todas las columnas
   necesarias para el `WHERE` (`estado`, `eliminado`), el `JOIN` (`usuario_id`) y el
   `SUM` (`total`); al estar los datos limpios en el mapa de visibilidad, evita
   lecturas costosas a la tabla `pedido`.
4. **Hash Join**: compara las 100.002 filas del índice contra la tabla hash de
   `usuario` bajo `p.usuario_id = u.id`. Es la estrategia óptima para relacionar una
   tabla moderada con un conjunto grande de datos.
5. **HashAggregate**: agrupa por `u.id` y suma `total`, reduciendo a 10.001 filas,
   evitando un ordenamiento previo para el `GROUP BY`.
6. **Sort**: ordena las 10.001 filas por `total_gastado` DESC con `top-N heapsort`
   (26kB), porque el `LIMIT 10` le permite a Postgres usar ese algoritmo en vez de
   ordenar todo el conjunto.
7. **Limit**: toma las primeras 10 filas del `Sort` y termina, atendiendo el `LIMIT 10`.

## 4. Tabla de contraste

+-------------------------------------------+--------------------+------------------------------------------------------------+
| Afirmación de la IA                       | ¿Es correcta?      | Corrección/Evidencia                                       |
+-------------------------------------------+--------------------+------------------------------------------------------------+
|       "El índice contiene todas las       |         No         |       El índice idx_pedido_usuario_total_estado solo       |
|     columnas necesarias para el WHERE     |                    |      tiene como columnas usuario_id y total. estado y      |
|            (estado, eliminado)"           |                    |       eliminado no están en el índice como columnas        |
|                                           |                    |           — son la condición del índice parcial            |
|                                           |                    |       (WHERE eliminado = FALSE AND estado IN (...)).       |
|                                           |                    |    La IA confunde "predicado de un índice parcial" con     |
|                                           |                    |  "columna cubierta". Por eso, además, el plan no muestra   |
|                                           |                    |           ningún Index Cond sobre esas columnas:           |
|                                           |                    |        el filtro ya está resuelto en la definición         |
|                                           |                    |                del índice, no en el acceso.                |
+-------------------------------------------+--------------------+------------------------------------------------------------+
|      "Al estar los datos limpios en       | No verificable con |    Es una explicación técnicamente razonable de por qué    |
|       el mapa de visibilidad, evita       |    el texto dado   |   puede darse Heap Fetches: 0 (requiere que las páginas    |
|             lecturas costosas"            |                    |    estén marcadas como all-visible), pero no surge del     |
|                                           |                    |     plan que le pasaste — el texto no menciona el mapa     |
|                                           |                    |  de visibilidad en ningún lado. La IA agregó conocimiento  |
|                                           |                    |       externo presentándolo como si viniera del plan.      |
+-------------------------------------------+--------------------+------------------------------------------------------------+
| "Logró Heap Fetches: 0, lo que significa  |         Si         |      Coincide con el plan real: Heap Fetches: 0 bajo       |
|        que no necesitó ir a buscar        |                    | el Index Only Scan. Interpretación correcta (a diferencia  |
|        datos a la tabla principal"        |                    |      del error típico de leerlo como "no leyó nada").      |
+-------------------------------------------+--------------------+------------------------------------------------------------+
|      "Escaneo secuencial completo...      |      Imprecisa     |   El plan muestra Buffers: shared hit=375 para usuario,    |
|            para obtener todos             |                    |  es decir, 375 bloques desde la caché de shared_buffers,   |
|           sus bloques de disco"           |                    |  no desde disco (no hay read=). Decir "bloques de disco"   |
|                                           |                    | es engañoso — precisamente esa es la diferencia entre hit  |
|                                           |                    |                y read en EXPLAIN (BUFFERS).                |
+-------------------------------------------+--------------------+------------------------------------------------------------+
|        "Reduciendo el resultado a         |         Si         | Coincide con actual ... rows=10001 del nodo HashAggregate  |
|       10.001 filas" (HashAggregate)       |                    |                      en el plan real.                      |
+-------------------------------------------+--------------------+------------------------------------------------------------+


## 5. Justificación técnica para la defensa oral

1. **Índice parcial vs. índice cubriente**: el error más relevante de la IA es tratar
   el predicado `WHERE` del índice parcial como si fueran columnas incluidas
   (covering). Un índice parcial reduce el tamaño del índice y filtra en su
   *definición*; un índice cubriente incluye columnas extra para que el `Index Only
   Scan` no tenga que ir a la tabla. `idx_pedido_usuario_total_estado` es **ambas
   cosas a la vez** (parcial en su predicado, cubriente en `usuario_id, total`), y la
   IA solo identificó la segunda característica, mezclándola con la primera.
2. **Cache hit vs. lectura a disco**: `Buffers: shared hit=N` y `read=N` no son
   intercambiables. `hit` es un bloque servido desde `shared_buffers` (RAM);
   `read` implica ir al sistema operativo / disco. La IA generalizó "escaneo
   secuencial" con "bloques de disco" sin fijarse en que, en este plan puntual, no
   hubo ningún `read` para la tabla `usuario`.
3. **Conocimiento externo no verificable**: la mención al "mapa de visibilidad" es
   correcta en términos generales de PostgreSQL, pero **no está en el plan dado** —
   por consigna, la IA debía limitarse al texto entregado. Esto ilustra un riesgo
   típico de pedirle explicaciones a una IA: rellena huecos con conocimiento previo
   y lo presenta con la misma confianza que lo que sí puede leer del plan.
4. Cabe destacar que **no** se detectó el error típico de confundir `cost` (estimado)
   con `actual time` (real), ni se inventó ningún `Rows Removed by Filter` inexistente
   en este plan — la IA acertó en esos dos puntos.

## 6. Entregable

- Plan real (antes/después de Parte 2, tomado de `ParteAndres.md`, Consulta 3).
- Prompt usado y respuesta íntegra de la IA (sección 3).
- Tabla de contraste completa (sección 4), con al menos una imprecisión conceptual
  real detectada y corregida con evidencia del propio plan.
