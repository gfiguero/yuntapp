---
name: db-migrate
description: Crea y aplica migraciones Rails de forma segura. Verifica indices, null constraints, rollback y consistencia con el schema.
user-invocable: true
allowed-tools:
  - Read
  - Write
  - Edit
  - Grep
  - Bash(git diff*)
  - Bash(bin/rails generate migration*)
  - Bash(bin/rails db:migrate*)
  - Bash(bin/rails db:rollback*)
  - Bash(bin/rails test*)
  - Bash(ls db/migrate*)
  - Bash(grep*)
---

# DB Migrate Skill

Crea y aplica migraciones Rails con checklist de seguridad para yuntapp (SQLite3).

## Input

`$ARGUMENTS` — Descripcion de la migracion. Ejemplos:
- `/db-migrate añadir campo notes a members`
- `/db-migrate crear tabla listing_categories con name y slug`
- `/db-migrate añadir indice en household_units.delegation_id`
- `/db-migrate renombrar columna en board_members`

## Procedimiento

### Fase 1: Analisis del schema actual

Leer `db/schema.rb` para entender el estado de la tabla afectada.

Verificar si ya existe una migracion similar:
```bash
ls db/migrate/ | grep -i <tabla>
```

### Fase 2: Generar la migracion

Usar el generador de Rails:
```bash
bin/rails generate migration <NombreMigracion> [campo:tipo ...]
```

Convenciones de naming:
- Anadir campo: `AddNombreToTabla`
- Crear tabla: `CreateTablas`
- Remover campo: `RemoveNombreFromTabla`
- Anadir indice: `AddIndexOnTablaColumna`
- Cambiar tipo: `ChangeNombreTipoEnTabla`

### Fase 3: Checklist pre-migracion

Antes de aplicar, verificar en el archivo generado:

#### 3.1 Null constraints
Para cada columna nueva, decidir explicitamente:
- Si el campo es requerido: `null: false` con `default` si aplica
- Si es opcional: `null: true` (raro — documentar el porque)

> Rails usa `null: true` por defecto. Siempre decidir conscientemente.

#### 3.2 Indices
Verificar que existen indices para:
- Toda foreign key (`_id` columns) → `add_index :tabla, :column_id`
- Columnas usadas en WHERE frecuente (status, active, run, email)
- Unicidad requerida → `add_index :tabla, :columna, unique: true`

#### 3.3 Rollback
Verificar que el metodo `change` es reversible:
- `add_column` — reversible automaticamente
- `remove_column` — requiere `up/down` con tipo explicito
- `rename_column` — reversible automaticamente
- `create_table` — reversible automaticamente
- `change_column_default` — necesita valor anterior en `down`

#### 3.4 Impacto en datos existentes
Si se agrega `null: false` a tabla con datos:
- Agregar `default:` temporal o backfill explicito antes del constraint
- Alertar si la tabla tiene registros en produccion

#### 3.5 Consistencia con modelos
Verificar que el modelo refleja la nueva columna:
- Nueva FK → agregar `belongs_to` en el modelo
- Nuevo campo requerido → agregar `validates :campo, presence: true`

### Fase 4: Aplicar migracion

```bash
bin/rails db:migrate
```

Si falla, diagnosticar y hacer rollback:
```bash
bin/rails db:rollback
```

### Fase 5: Verificar schema.rb

```bash
git diff db/schema.rb
```

Confirmar que:
- La columna/tabla aparece correctamente
- Los indices estan presentes
- El tipo de dato es correcto

### Fase 6: Actualizar modelos si aplica

Si se agrego una foreign key, verificar:
- `belongs_to :modelo` en el modelo hijo
- `has_many :modelos` en el modelo padre (si aplica)
- Validaciones necesarias en ambos lados

### Fase 7: Actualizar fixtures si aplica

Si se agrego un campo `null: false` sin default, actualizar fixtures:
```bash
grep -rl "<tabla>:" test/fixtures/
```

Agregar el campo a cada fixture afectado.

### Fase 8: Verificar tests

```bash
bin/rails test
```

Si algun test falla por la nueva migracion, diagnosticar y corregir.

### Fase 9: Resumen

```
## Migracion aplicada

| Campo | Valor |
|-------|-------|
| Migracion | YYYYMMDDHHMMSS_nombre.rb |
| Tabla | nombre_tabla |
| Cambios | descripcion |
| Indices | lista o "ninguno" |
| Null constraints | lista |
| Rollback | seguro / requiere down manual |
| Fixtures actualizados | si/no |
| Tests | pass/fail |
```

## Patron expand-contract (renombrar/eliminar columnas)

Nunca renombrar o eliminar una columna directamente en produccion. Usar el patron de tres pasos:

```
Paso 1 — Expand (migracion 1):
  Agregar la columna nueva (nullable)
  Deploy: la app escribe en AMBAS columnas

Paso 2 — Migrate (migracion 2, datos):
  Backfill de la columna vieja a la nueva
  Deploy: la app solo lee la nueva columna

Paso 3 — Contract (migracion 3):
  Eliminar la columna vieja
```

Ejemplo — renombrar `username` a `display_name` en `members`:

```ruby
# Migracion 1: add_display_name_to_members
add_column :members, :display_name, :string

# Migracion 2: backfill_display_name_in_members (datos separados)
Member.find_each do |m|
  m.update_column(:display_name, m.username)
end

# Migracion 3: remove_username_from_members
remove_column :members, :username
```

## Migraciones de datos en batch (tablas grandes)

Para tablas con muchos registros, nunca hacer UPDATE masivo en una sola transaccion:

```ruby
# MALO — bloquea la tabla entera
class BackfillNormalizedRun < ActiveRecord::Migration[8.1]
  def up
    Member.update_all("normalized_run = LOWER(run)")
  end
end

# BUENO — procesa en batches de 500
class BackfillNormalizedRun < ActiveRecord::Migration[8.1]
  def up
    Member.find_each(batch_size: 500) do |member|
      member.update_column(:normalized_run, member.run&.downcase)
    end
  end

  def down
    Member.update_all(normalized_run: nil)
  end
end
```

## Anti-patrones a evitar

| Anti-patron | Por que falla | Alternativa |
|-------------|--------------|-------------|
| SQL manual en produccion | Sin trazabilidad, no repetible | Siempre usar archivos de migracion |
| Editar migracion ya deployada | Causa drift entre entornos | Crear nueva migracion correctiva |
| NOT NULL sin default en tabla con datos | Bloquea en SQLite3 | Agregar nullable, backfill, luego constraint |
| Schema + datos en una migracion | Dificil de rollback, transaccion larga | Separar en dos migraciones |
| Eliminar columna antes de eliminar el codigo | Errores en produccion | Eliminar el codigo primero, luego la columna |

## Reglas

- **Nunca null: true sin decision consciente** — explicar en comentario si es opcional
- **Siempre indice en foreign keys** — sin excepciones
- **Verificar rollback** — antes de aplicar en produccion
- **Actualizar fixtures** — si se anaden columnas not null sin default
- **Un cambio por migracion** — no mezclar multiples cambios sin relacion
- **Nunca modificar migraciones ya mergeadas** — crear nueva migracion para corregir
- **Nunca `bin/rails db:schema:load` en produccion** — solo migraciones incrementales
- **Separar schema de datos** — migraciones DDL y DML en archivos distintos
- **Batches para tablas grandes** — usar `find_each` o `in_batches` nunca `update_all` masivo
