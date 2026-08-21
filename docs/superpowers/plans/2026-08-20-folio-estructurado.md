# Folio estructurado del certificado de residencia — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cambiar el folio a `CR-{año}-{junta}-{correlativo}` y calcular el correlativo desde columnas enteras en vez de parsear strings.

**Architecture:** Dos columnas nuevas (`folio_year`, `folio_sequence`) guardan el dato; el folio pasa a ser su representación, construida con `format`. El correlativo se obtiene con un `MAX(folio_sequence)` por junta y año, protegido por un índice único parcial. Los folios ya emitidos no se tocan (BR-008): solo se les puebla las columnas nuevas para que el correlativo continúe.

**Tech Stack:** Rails 8.1.3.1, SQLite3, Minitest con fixtures YAML.

**Spec:** `docs/superpowers/specs/2026-08-20-folio-estructurado-design.md`

## Global Constraints

- **BR-008**: un certificado `issued` es inmutable. Ningún folio existente se reescribe, ni siquiera en la migración de backfill.
- **BR-006**: se reescribe en `CLAUDE.md` como parte de la Tarea 3. No renumerar; editar la fila existente.
- **Formato exacto del folio nuevo**: `CR-2026-0002-00015` — prefijo `CR`, año 4 dígitos, junta 4 dígitos con padding de ceros, correlativo 5 dígitos con padding de ceros, separados por `-`.
- **Sin dígito verificador.** Decisión del owner; no agregarlo por iniciativa propia.
- **Migraciones DDL y DML separadas**, según la skill `db-migrate` del proyecto: una migración crea columnas e índice, otra puebla datos.
- Todos los tests corren con `bin/rails test`. El proyecto usa **fixtures YAML, no factories**.
- Linter: `bin/standardrb` debe quedar limpio antes de cada commit.

---

### Task 1: Columnas, índice y backfill

**Files:**
- Create: `db/migrate/<timestamp>_add_folio_components_to_residence_certificates.rb`
- Create: `db/migrate/<timestamp>_backfill_folio_components.rb`
- Modify: `db/schema.rb` (lo regenera `db:migrate`, no editar a mano)
- Test: `test/models/residence_certificate_test.rb`

**Interfaces:**
- Consumes: nada.
- Produces: columnas `residence_certificates.folio_year` (integer, nullable) y `residence_certificates.folio_sequence` (integer, nullable); índice único parcial `index_residence_certificates_on_association_year_sequence`.

- [ ] **Step 1: Generar la migración de columnas**

```bash
bin/rails generate migration AddFolioComponentsToResidenceCertificates
```

- [ ] **Step 2: Escribir la migración de columnas**

Reemplazar el contenido del archivo generado por:

```ruby
class AddFolioComponentsToResidenceCertificates < ActiveRecord::Migration[8.1]
  # El correlativo del folio pasa a vivir en columnas enteras: el folio deja de
  # ser el dato y pasa a ser su representación. Ambas son nullable porque un
  # certificado sin emitir no tiene folio (BR-064: nace en pending_payment).
  def change
    add_column :residence_certificates, :folio_year, :integer
    add_column :residence_certificates, :folio_sequence, :integer

    # Parcial: las filas sin emitir tienen NULL y no deben competir por el
    # índice. Mismo patrón que los índices únicos parciales de #108.
    add_index :residence_certificates,
      [:neighborhood_association_id, :folio_year, :folio_sequence],
      unique: true,
      where: "folio_sequence IS NOT NULL",
      name: "index_residence_certificates_on_association_year_sequence"
  end
end
```

- [ ] **Step 3: Generar la migración de backfill**

```bash
bin/rails generate migration BackfillFolioComponents
```

- [ ] **Step 4: Escribir la migración de backfill**

Reemplazar el contenido del archivo generado por:

```ruby
class BackfillFolioComponents < ActiveRecord::Migration[8.1]
  # BR-008: los folios emitidos NO se reescriben. Solo se pueblan las columnas
  # nuevas, para que el correlativo continúe donde iba en vez de reiniciar y
  # chocar. El parseo del formato viejo (`CR-{junta}-{n}`) ocurre una única vez,
  # aquí, sobre datos conocidos — no en la ruta de emisión.
  def up
    ResidenceCertificate.where.not(folio: nil).find_each do |cert|
      sequence = cert.folio.to_s.split("-").last.to_i
      year = cert.issue_date&.year || cert.created_at.year

      say "backfill ##{cert.id} folio=#{cert.folio} -> year=#{year} sequence=#{sequence}"
      cert.update_columns(folio_year: year, folio_sequence: sequence)
    end
  end

  def down
    ResidenceCertificate.update_all(folio_year: nil, folio_sequence: nil)
  end
end
```

- [ ] **Step 5: Aplicar las migraciones**

Run: `bin/rails db:migrate`
Expected: ambas migraciones aplican; el log muestra una línea `backfill #N ...` por cada certificado de las fixtures que tenga folio.

- [ ] **Step 6: Verificar que el rollback es reversible**

Run: `bin/rails db:rollback STEP=2 && bin/rails db:migrate`
Expected: baja y vuelve a subir sin error. Confirma que el `down` del backfill y el `change` de las columnas son reversibles.

- [ ] **Step 7: Escribir el test del backfill**

Agregar en `test/models/residence_certificate_test.rb`, junto a los demás tests de folio:

```ruby
test "el backfill dejó folio_year y folio_sequence en los certificados con folio" do
  cert = ResidenceCertificate.where.not(folio: nil).first
  assert_not_nil cert, "las fixtures deben tener al menos un certificado con folio"
  assert_not_nil cert.folio_year, "el backfill debe poblar folio_year"
  assert_not_nil cert.folio_sequence, "el backfill debe poblar folio_sequence"
end
```

- [ ] **Step 8: Correr el test**

Run: `bin/rails test test/models/residence_certificate_test.rb -n "/backfill/"`
Expected: PASS. Si falla con `folio_year` nil, la base de test se preparó desde `schema.rb` sin correr el backfill: correr `bin/rails db:test:prepare` y repetir.

- [ ] **Step 9: Commit**

```bash
git add db/migrate db/schema.rb test/models/residence_certificate_test.rb
git commit -m "feat(certificados): columnas folio_year y folio_sequence con backfill"
```

---

### Task 2: Asignación del folio desde las columnas

**Files:**
- Modify: `app/models/residence_certificate.rb` (`issue!` líneas ~187-219, `next_folio` líneas ~259-268, `folio_collision?` líneas ~273-286)
- Test: `test/models/residence_certificate_test.rb` (tests de folio, líneas ~69-150)

**Interfaces:**
- Consumes: columnas `folio_year` y `folio_sequence` de la Tarea 1.
- Produces: `ResidenceCertificate#next_folio_sequence(year)` → `Integer`; `ResidenceCertificate#build_folio(year, sequence)` → `String`; constante `FOLIO_PREFIX = "CR"`. `next_folio` deja de existir.

- [ ] **Step 1: Escribir los tests del formato nuevo**

Reemplazar el test `"issue! sets folio with the CR-{association}-{sequence} format (BR-006)"` (línea ~69) por estos tres:

```ruby
test "issue! genera el folio con el formato CR-anio-junta-correlativo (BR-006)" do
  cert = ResidenceCertificate.create!(
    member: @member, household_unit: @household_unit,
    neighborhood_association: @association, purpose: "trámite bancario", status: "paid"
  )
  cert.issue!

  assert_match(/\ACR-\d{4}-\d{4}-\d{5}\z/, cert.folio)
  assert_equal Date.current.year, cert.folio_year
  assert_equal format("CR-%04d-%04d-%05d", cert.folio_year, @association.id, cert.folio_sequence), cert.folio
end

test "el correlativo del folio es por junta y por anio" do
  first = ResidenceCertificate.create!(
    member: @member, household_unit: @household_unit,
    neighborhood_association: @association, purpose: "uno", status: "paid"
  ).tap(&:issue!)

  second = ResidenceCertificate.create!(
    member: @member, household_unit: @household_unit,
    neighborhood_association: @association, purpose: "dos", status: "paid"
  ).tap(&:issue!)

  assert_equal first.folio_sequence + 1, second.folio_sequence
  assert_equal first.folio_year, second.folio_year
end

test "el correlativo reinicia al cambiar de anio" do
  cert = ResidenceCertificate.create!(
    member: @member, household_unit: @household_unit,
    neighborhood_association: @association, purpose: "del futuro", status: "paid"
  )
  # Un año sin certificados previos arranca en 1, sin importar el correlativo
  # que lleve el año en curso.
  cert.issue!(issue_date: Date.new(Date.current.year + 1, 1, 5))

  assert_equal 1, cert.folio_sequence
  assert_equal Date.current.year + 1, cert.folio_year
  assert_equal format("CR-%04d-%04d-00001", Date.current.year + 1, @association.id), cert.folio
end
```

- [ ] **Step 2: Correr los tests para verificar que fallan**

Run: `bin/rails test test/models/residence_certificate_test.rb -n "/folio/"`
Expected: FAIL. Los del formato nuevo fallan porque `issue!` sigue produciendo `CR-2-N` y `folio_year` queda nil.

- [ ] **Step 3: Reemplazar `next_folio` por el cálculo sobre columnas**

En `app/models/residence_certificate.rb`, borrar el método `next_folio` completo (líneas ~259-268) y poner en su lugar:

```ruby
  # Correlativo siguiente de la junta para ese año. Consulta agregada sobre la
  # columna entera: sin parseo de strings y sin cargar los folios en memoria.
  def next_folio_sequence(year)
    max = self.class
      .where(neighborhood_association_id: neighborhood_association_id, folio_year: year)
      .maximum(:folio_sequence) || 0
    max + 1
  end

  # El folio es la representación del dato, no el dato. Ver BR-006.
  def build_folio(year, sequence)
    format("%s-%04d-%04d-%05d", FOLIO_PREFIX, year, neighborhood_association_id, sequence)
  end
```

- [ ] **Step 4: Declarar la constante del prefijo**

En `app/models/residence_certificate.rb`, junto a `FOLIO_MAX_ATTEMPTS = 5` (línea ~178), agregar:

```ruby
  FOLIO_PREFIX = "CR"
```

- [ ] **Step 5: Asignar las tres columnas en `issue!`**

En `issue!`, reemplazar el bloque `assign_attributes` (líneas ~200-208) por:

```ruby
          year = issue_date.year
          sequence = folio_sequence || next_folio_sequence(year)

          assign_attributes(
            folio_year: folio_year || year,
            folio_sequence: sequence,
            folio: folio.presence || build_folio(year, sequence),
            validation_token: validation_token.presence || SecureRandom.uuid,
            validation_code: validation_code.presence || generate_validation_code,
            issue_date: issue_date,
            expiration_date: issue_date + VALIDITY_PERIOD,
            issued_at: Time.current,
            status: "issued"
          )
```

- [ ] **Step 6: Limpiar las tres asignaciones al reintentar**

En el `rescue` de `issue!` (línea ~213), reemplazar `self.folio = nil` por:

```ruby
        self.folio = nil
        self.folio_sequence = nil
```

`folio_year` no se limpia: el año no cambia entre reintentos, solo el correlativo.

- [ ] **Step 7: Hacer explícita la detección de la colisión nueva**

En `folio_collision?` (línea ~273), reemplazar la rama `ActiveRecord::RecordNotUnique` por:

```ruby
    when ActiveRecord::RecordNotUnique
      # SQLite (BD de prod) reporta las columnas en el mensaje: tanto
      # "...residence_certificates.folio" como
      # "...residence_certificates.folio_sequence" contienen "folio". El match
      # por substring cubre ambos índices, pero se deja explícito para que no
      # dependa del azar de los nombres. NO matchea payment_id/validation_*.
      error.message.include?("folio") || error.message.include?("folio_sequence")
```

- [ ] **Step 8: Adaptar los dos tests de colisión**

Los tests de las líneas ~99 y ~130 mockean `next_folio`, que ya no existe. En el primero
(`"issue! recovers from a folio collision..."`), reemplazar el bloque desde `taken_folio =` hasta el
`end` del `define_singleton_method` por:

```ruby
    taken_sequence = taken.folio_sequence
    calls = 0
    cert.define_singleton_method(:next_folio_sequence) do |year|
      calls += 1
      (calls == 1) ? taken_sequence : super(year)
    end
```

y su última aserción por:

```ruby
    assert_match(/\ACR-\d{4}-\d{4}-\d{5}\z/, cert.folio)
```

En el segundo (`"issue! gives up after max attempts..."`), reemplazar el `define_singleton_method` por:

```ruby
    cert.define_singleton_method(:next_folio_sequence) { |_year| 1 }
```

Y en ambos tests, el certificado `taken` que se crea al inicio debe llevar las columnas nuevas para
que la colisión ocurra de verdad. Reemplazar su `folio:` por:

```ruby
      folio: "CR-#{Date.current.year}-#{format("%04d", @association.id)}-00001",
      folio_year: Date.current.year, folio_sequence: 1,
```

- [ ] **Step 9: Correr todos los tests de folio**

Run: `bin/rails test test/models/residence_certificate_test.rb`
Expected: PASS, incluidos los dos de colisión y el de agotamiento de reintentos.

- [ ] **Step 10: Correr la suite completa**

Run: `bin/rails test`
Expected: PASS. Prestar atención a `test/controllers/` y `test/jobs/`: cualquier test que afirme el
formato viejo del folio hay que actualizarlo al nuevo.

- [ ] **Step 11: Verificar el linter**

Run: `bin/standardrb`
Expected: `no offenses detected`

- [ ] **Step 12: Commit**

```bash
git add app/models/residence_certificate.rb test/
git commit -m "feat(certificados): folio CR-anio-junta-correlativo calculado desde columnas"
```

---

### Task 3: Reglas de negocio y verificación de convivencia

**Files:**
- Modify: `CLAUDE.md` (fila BR-006 de la tabla de reglas)
- Test: `test/models/residence_certificate_test.rb`

**Interfaces:**
- Consumes: `build_folio` y `next_folio_sequence` de la Tarea 2.
- Produces: nada que consuman otras tareas.

- [ ] **Step 1: Escribir el test de convivencia de formatos**

El caso real de producción: una junta con folios viejos que emite uno nuevo. Agregar:

```ruby
test "una junta con folios del formato viejo continua el correlativo, sin reescribirlos" do
  viejo = ResidenceCertificate.create!(
    member: @member, household_unit: @household_unit,
    neighborhood_association: @association, purpose: "formato viejo", status: "issued",
    folio: "CR-#{@association.id}-14", folio_year: Date.current.year, folio_sequence: 14,
    issue_date: Date.current, expiration_date: 30.days.from_now.to_date
  )

  nuevo = ResidenceCertificate.create!(
    member: @member, household_unit: @household_unit,
    neighborhood_association: @association, purpose: "formato nuevo", status: "paid"
  )
  nuevo.issue!

  assert_equal 15, nuevo.folio_sequence, "el correlativo debe continuar desde el folio viejo"
  assert_equal format("CR-%04d-%04d-00015", Date.current.year, @association.id), nuevo.folio
  assert_equal "CR-#{@association.id}-14", viejo.reload.folio, "BR-008: el folio viejo no se reescribe"
end

test "filter_by_folio encuentra ambos formatos" do
  ResidenceCertificate.create!(
    member: @member, household_unit: @household_unit,
    neighborhood_association: @association, purpose: "viejo", status: "issued",
    folio: "CR-#{@association.id}-14", folio_year: Date.current.year, folio_sequence: 14,
    issue_date: Date.current, expiration_date: 30.days.from_now.to_date
  )
  ResidenceCertificate.create!(
    member: @member, household_unit: @household_unit,
    neighborhood_association: @association, purpose: "nuevo", status: "issued",
    folio: format("CR-%04d-%04d-00015", Date.current.year, @association.id),
    folio_year: Date.current.year, folio_sequence: 15,
    issue_date: Date.current, expiration_date: 30.days.from_now.to_date
  )

  assert_equal 2, ResidenceCertificate.filter_by_folio("14").count +
    ResidenceCertificate.filter_by_folio("15").count
end
```

- [ ] **Step 2: Correr los tests**

Run: `bin/rails test test/models/residence_certificate_test.rb -n "/formato|filter_by_folio/"`
Expected: PASS (la implementación de la Tarea 2 ya los satisface; estos tests fijan el comportamiento
de convivencia para que nadie lo rompa después).

- [ ] **Step 3: Reescribir BR-006 en CLAUDE.md**

Buscar la fila `| BR-006 | Integridad |` y reemplazarla íntegra por:

```markdown
| BR-006 | Integridad | El folio del certificado es `CR-{año}-{junta}-{correlativo}` con padding (ej. `CR-2026-0002-00015`): tipo de documento, año de emisión, junta emisora y correlativo de esa junta **en ese año**. Es el identificador oficial del documento. El correlativo vive en las columnas `folio_year` y `folio_sequence` —protegidas por un índice único parcial— y el folio es su **representación**, no el dato: antes se calculaba parseando el string del folio anterior, lo que convertía silenciosamente en `0` cualquier formato inesperado. **Formato anterior (`CR-{junta}-{correlativo}`, sin año) reemplazado el 2026-08-20**; los certificados emitidos con él lo conservan para siempre (BR-008 los declara inmutables y sus PDF ya descargados citan ese folio), así que ambos formatos conviven y las búsquedas aceptan los dos. El folio **no** lleva datos personales ni del domicilio: son mutables y el documento es público (ver BR-078). Para verificación telefónica existe el `validation_code` (BR-074), no el folio |
```

- [ ] **Step 4: Correr la suite completa y el linter**

Run: `bin/rails test && bin/standardrb`
Expected: ambos PASS.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md test/models/residence_certificate_test.rb
git commit -m "docs(certificados): reescribe BR-006 con el folio estructurado"
```

- [ ] **Step 6: Verificación final antes del PR**

Run: `bin/ci`
Expected: todos los pasos en verde, incluida la pasada de production parity y el signoff.

Si el signoff falla con `repository has uncommitted or unpushed changes`, pushear la rama primero: el
orden correcto es push → signoff.

---

## Notas para quien ejecute

**Lo que este plan deliberadamente no hace:**

- No agrega dígito verificador. Fue una propuesta descartada por el owner.
- No reescribe folios existentes. BR-008 lo prohíbe y hay PDFs descargados que los citan.
- No toca `validation_code` ni `validation_token`. El folio no es el identificador de verificación
  pública.
- No cambia el layout del PDF: `CertificatePdfService` imprime `certificate.folio` y seguirá haciéndolo.

**El riesgo real está en la Tarea 2, paso 10.** El formato del folio aparece en 12 archivos entre
vistas, mailers, PDF y el servicio de MercadoPago. Ninguno construye el folio —todos lo leen— pero
puede haber tests que afirmen el formato viejo. Correr la suite completa, no solo los tests del modelo.

**Verificación en producción tras el deploy** (el backfill corre solo en el boot, vía `db:prepare`):

```ruby
ResidenceCertificate.where.not(folio: nil).pluck(:folio, :folio_year, :folio_sequence)
```

Los 7 certificados de producción deben quedar con `folio_year: 2026` y sus correlativos 7, 8, 10, 11,
12, 13 y 14. El siguiente certificado emitido debe recibir `CR-2026-0002-00015`.
