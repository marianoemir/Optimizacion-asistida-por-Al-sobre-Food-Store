# Protocolo de Seguridad — Food Store

Este documento define los pasos obligatorios que se aplican **siempre**, sin excepción,
antes de que cualquier script (propio o generado por IA) toque la base de datos del proyecto.

## Motor y entorno

- Motor: PostgreSQL
- Base de trabajo local: `food_store_dev`
- Base "plantilla" con el esquema y el seed chico ya aplicados: `plantilla_food_store`
- Base de trabajo descartable para este TP: `copia_trabajo` (o `copia_trabajo_masiva`
  si se quiere distinguir de copias usadas para otras entregas)

## Paso 1 — Copia

Nunca se trabaja directamente sobre la base que contiene datos que importan (ni siquiera
datos de prueba que ya llevan tiempo cargados). Antes de cualquier cambio se crea una copia
descartable:

```bash
createdb -T plantilla_food_store copia_trabajo
```

Si la plantilla `plantilla_food_store` todavía no existe, se crea una vez a partir del esquema:

```bash
createdb plantilla_food_store
psql -d plantilla_food_store -f "Archivos necesarios para la BD/schema.sql"
psql -d plantilla_food_store -f "Archivos necesarios para la BD/objects.sql"
psql -d plantilla_food_store -f "Archivos necesarios para la BD/data.sql"
```

Todo el trabajo de este TP (carga masiva, EXPLAIN ANALYZE, índices, reescrituras, pruebas
de concurrencia) se ejecuta sobre `copia_trabajo`, nunca sobre `plantilla_food_store` ni
sobre ninguna base que tenga datos reales de producción.

> **Nota TP3:** la carga masiva (50.000+ productos, 20.000+ usuarios, 200.000+ pedidos) se
> aplica solo sobre `copia_trabajo`. La plantilla se mantiene liviana con el seed chico
> original, para que cualquier integrante pueda sacar una copia limpia rápido sin arrastrar
> el volumen masivo si no lo necesita.

## Paso 2 — Transacción

Todo script que escriba datos (INSERT, UPDATE, DELETE, o que agregue restricciones) se ejecuta
primero dentro de una transacción abierta, para poder inspeccionar el efecto antes de confirmar
nada:

```sql
BEGIN;

-- acá va el script generado por la IA o el cambio propio

-- se revisa: cuántas filas afectó, qué mensajes tiró, si el resultado
-- es el esperado

ROLLBACK; -- primero SIEMPRE se revierte para confirmar que se entendió el efecto
```

Recién cuando el efecto fue inspeccionado y es el esperado, se repite la operación terminando
en `COMMIT` en lugar de `ROLLBACK`.

Para la **carga masiva de la Parte 1**, dado el volumen (270.000+ filas en total), conviene:
- Probar el script primero con cantidades reducidas (ej: 500 productos, 200 usuarios) dentro
  de `BEGIN...ROLLBACK` para confirmar que no rompe ningún constraint.
- Recién con eso validado, correr la versión completa terminando en `COMMIT`.

## Paso 3 — Respaldo

Antes de cualquier cambio estructural (ALTER, DROP, CREATE TRIGGER, CREATE FUNCTION, CREATE
INDEX, o cualquier migración), se saca un respaldo de la copia de trabajo, independiente del
`ROLLBACK`:

```bash
pg_dump copia_trabajo > respaldos/copia_trabajo_YYYYMMDD_HHMM.sql
```

Los respaldos se guardan en la carpeta `respaldos/` del repo (o fuera del repo si el archivo
es pesado), con fecha y hora en el nombre para poder identificar el punto exacto al que
volver si algo sale mal.

> **Nota TP3:** antes de aplicar cada `CREATE INDEX` propuesto en la Parte 2, sacar respaldo
> de `copia_trabajo` — si el índice no mejora o rompe algo, se vuelve al estado anterior sin
> tener que rehacer la carga masiva completa (que es la parte más lenta de recrear).

## Paso 4 — Estadísticas actualizadas antes de medir

Después de cualquier carga masiva de datos o de crear/eliminar un índice, correr:

```sql
ANALYZE producto;
ANALYZE usuario;
ANALYZE pedido;
ANALYZE detalle_pedido;
```

(o `ANALYZE;` sin argumentos para actualizar todas las tablas de la base)

Sin este paso, el optimizador de PostgreSQL puede seguir usando estadísticas viejas y el
plan de `EXPLAIN ANALYZE` no refleja el volumen real de datos — esto invalida cualquier
comparación de "antes/después" de la Parte 2.

## Regla de fondo

Ningún script generado por OpenCode o Kiro se ejecuta directamente sobre la base. El flujo
siempre es:

1. Se pide el cambio a la IA en modo Plan (sin tocar archivos).
2. Se revisa el plan propuesto.
3. Se aplica y se lee el `git diff` completo, línea por línea.
4. Se prueba el efecto dentro de `BEGIN...ROLLBACK` sobre `copia_trabajo`.
5. Si el cambio es estructural (incluye `CREATE INDEX`), se saca respaldo antes del `COMMIT` final.
6. Si el cambio afecta el volumen de datos o los índices, se corre `ANALYZE` antes de medir.
7. Recién ahí se hace `COMMIT` y se commitea el cambio en Git.

Ningún paso de esta lista se salta, incluso cuando el cambio parece trivial.
