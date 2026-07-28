# Fundación RUT en la Junta — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Agregar `rut` obligatorio, único y validado (módulo 11) a `NeighborhoodAssociation`, con backfill de datos existentes, de modo que ninguna junta pueda existir sin RUT (BR-119/BR-120/BR-121).

**Architecture:** Migración expand-contract (agregar columna nullable → backfill determinístico → `NOT NULL` + índice único). Normalización y validación en el modelo reutilizando el algoritmo módulo 11 del `RunValidator` existente. Enforcement defensivo en la emisión de certificados. Como `rut` pasa a `NOT NULL`, hay que dar RUT a todas las fixtures y a todo sitio que cree juntas inline (ripple), incluido el `DemoJuntaSeeder`.

**Tech Stack:** Rails 8.1, SQLite3, Minitest + fixtures YAML (ERB), Standard Ruby.

**Prerrequisito:** ninguno. Este plan se puede shippear solo. El Plan 2 (onboarding de administración) depende de este.

---

### Task 1: Migración — agregar `rut` con backfill (expand-contract)

**Files:**
- Create: `db/migrate/20260727120000_add_rut_to_neighborhood_associations.rb`
- Modify: `db/schema.rb` (se regenera al migrar)

- [ ] **Step 1: Escribir la migración**

```ruby
# db/migrate/20260727120000_add_rut_to_neighborhood_associations.rb
class AddRutToNeighborhoodAssociations < ActiveRecord::Migration[8.1]
  # BR-119/BR-121: toda junta debe tener RUT. Expand-contract:
  # 1) columna nullable, 2) backfill determinístico válido, 3) NOT NULL + índice único.
  def up
    add_column :neighborhood_associations, :rut, :string

    # Backfill de juntas heredadas con un RUT válido y único por fila.
    # Rango 60.000.000+id: 8 dígitos, único (id único), DV módulo 11 correcto.
    # Los RUTs reales se corrigen luego desde el panel superadmin.
    execute("SELECT id FROM neighborhood_associations").each do |row|
      id = row.is_a?(Array) ? row.first : row["id"]
      body = (60_000_000 + id.to_i).to_s
      rut = "#{body}-#{dv(body)}"
      execute("UPDATE neighborhood_associations SET rut = #{connection.quote(rut)} WHERE id = #{id.to_i}")
    end

    change_column_null :neighborhood_associations, :rut, false
    add_index :neighborhood_associations, :rut, unique: true
  end

  def down
    remove_index :neighborhood_associations, :rut
    remove_column :neighborhood_associations, :rut
  end

  private

  # Dígito verificador módulo 11 (idéntico a RunValidator#calculate_dv).
  def dv(body)
    sum = 0
    multiplier = 2
    body.to_s.reverse.each_char do |char|
      sum += char.to_i * multiplier
      multiplier = (multiplier == 7) ? 2 : multiplier + 1
    end
    remainder = 11 - (sum % 11)
    case remainder
    when 11 then "0"
    when 10 then "K"
    else remainder.to_s
    end
  end
end
```

- [ ] **Step 2: Correr la migración**

Run: `bin/rails db:migrate`
Expected: crea la columna, hace backfill sin error, agrega `NOT NULL` + índice único. `db/schema.rb` ahora incluye `t.string "rut", null: false` y el índice `index_neighborhood_associations_on_rut` unique.

- [ ] **Step 3: Verificar el backfill en consola**

Run: `bin/rails runner 'puts NeighborhoodAssociation.where(rut: nil).count; puts NeighborhoodAssociation.first&.rut.inspect'`
Expected: `0` juntas sin rut; el primer rut tiene formato `600000XX-D`.

- [ ] **Step 4: Commit**

```bash
git add db/migrate/20260727120000_add_rut_to_neighborhood_associations.rb db/schema.rb
git commit -m "feat(junta): agregar rut NOT NULL unico con backfill (BR-119/121)"
```

---

### Task 2: Fixtures — dar `rut` a todas las juntas para que cargue la suite

**Files:**
- Modify: `test/fixtures/neighborhood_associations.yml`

Contexto: el archivo genera 30 fixtures en un loop ERB (`association_0`..`association_29`) más `manios_de_buin`. Con `rut NOT NULL`, cargar fixtures sin `rut` falla. Se agrega un `rut` determinístico válido a cada una. Rango 61.000.000+ para no colisionar con el backfill (60M) ni con los RUTs demo (70M).

- [ ] **Step 1: Agregar helper DV y `rut` en el loop ERB y en la fixture hardcodeada**

Abrir `test/fixtures/neighborhood_associations.yml`. En la cabecera ERB (donde se define el array `factions` y el loop), agregar un lambda para el DV y emitir `rut` en cada registro. Ejemplo del bloque ERB resultante (ajustar a la estructura existente del archivo, conservando `name` y `commune`):

```erb
<%
  dv = ->(body) {
    sum = 0; m = 2
    body.to_s.reverse.each_char { |c| sum += c.to_i * m; m = (m == 7) ? 2 : m + 1 }
    r = 11 - (sum % 11)
    r == 11 ? "0" : (r == 10 ? "K" : r.to_s)
  }
%>
<% 30.times do |i| %>
association_<%= i %>:
  name: <%= factions[i % factions.size] %>
  commune: commune_0_0_<%= i % 10 %>
  rut: <%= body = (61_000_000 + i).to_s; "#{body}-#{dv.call(body)}" %>
<% end %>

manios_de_buin:
  name: Junta de Vecinos Mañíos de Buin
  commune: commune_0_0_39
  rut: <%= body = "61999001"; "#{body}-#{dv.call(body)}" %>
```

- [ ] **Step 2: Verificar que la suite carga fixtures**

Run: `bin/rails test test/models/neighborhood_association_test.rb`
Expected: los tests cargan (pueden pasar/fallar por assertions viejas, pero NO deben fallar por `NOT NULL constraint failed: neighborhood_associations.rut`).

- [ ] **Step 3: Commit**

```bash
git add test/fixtures/neighborhood_associations.yml
git commit -m "test(fixtures): rut valido en fixtures de juntas"
```

---

### Task 3: Ripple — dar `rut` a toda creación inline de juntas (app + tests + seeder)

**Files:**
- Modify: `app/services/demo_junta_seeder.rb`
- Modify: cualquier archivo bajo `test/` o `app/` que cree `NeighborhoodAssociation` sin `rut` (descubrir con grep)

- [ ] **Step 1: Descubrir todos los sitios de creación**

Run: `grep -rn "NeighborhoodAssociation.create\|NeighborhoodAssociation.new\|neighborhood_associations.create\|NeighborhoodAssociation\.find_or_create" app test lib db/seeds.rb`
Expected: lista de sitios. Cada uno que no pase `rut:` debe corregirse.

- [ ] **Step 2: `DemoJuntaSeeder` — asignar un RUT de prueba provisto**

En `app/services/demo_junta_seeder.rb`, agregar una constante con los 10 RUTs válidos provistos y usar el primero al crear la junta demo (línea ~52).

```ruby
# Cerca de ASSOCIATION_NAME (línea ~18):
DEMO_RUTS = %w[
  70207956-K 71724860-0 74426693-9 83014859-0 83312584-2
  86429665-3 91399989-4 91750662-0 94600037-K 96807455-5
].freeze
```

```ruby
# Reemplazar la creación de la junta (línea ~52):
@association = NeighborhoodAssociation.create!(name: ASSOCIATION_NAME, commune: @commune, rut: DEMO_RUTS.first)
```

- [ ] **Step 3: Corregir cada creación inline restante**

Para cada sitio del Step 1 sin `rut:`, agregar un RUT válido. En tests, usar un RUT determinístico único por sitio (rango 62.000.000+). Patrón para tests:

```ruby
NeighborhoodAssociation.create!(name: "Junta X", rut: "62000001-#{Rut.dv("62000001")}")
```

Si hay muchos sitios de test, añadir un helper en `test/test_helper.rb`:

```ruby
# test/test_helper.rb — helper para RUT válido en tests
def valid_test_rut(seq)
  body = (62_000_000 + seq).to_s
  sum = 0; m = 2
  body.reverse.each_char { |c| sum += c.to_i * m; m = (m == 7) ? 2 : m + 1 }
  r = 11 - (sum % 11)
  dv = r == 11 ? "0" : (r == 10 ? "K" : r.to_s)
  "#{body}-#{dv}"
end
```

y usar `rut: valid_test_rut(1)` (secuencia distinta por creación dentro del mismo test).

- [ ] **Step 4: Verificar que no quedan creaciones sin rut**

Run: `grep -rn "NeighborhoodAssociation.create\|NeighborhoodAssociation.new" app test lib db/seeds.rb`
Revisar manualmente que cada resultado incluye `rut:` (o construye una junta inválida a propósito para un test de validación).

- [ ] **Step 5: Commit**

```bash
git add app/services/demo_junta_seeder.rb test/test_helper.rb
git add -A test app lib
git commit -m "chore(junta): rut en creaciones inline de juntas (seeder + tests)"
```

---

### Task 4: Modelo — normalización + validación de `rut`

**Files:**
- Modify: `app/models/neighborhood_association.rb`
- Test: `test/models/neighborhood_association_test.rb`

- [ ] **Step 1: Escribir los tests que fallan**

Agregar a `test/models/neighborhood_association_test.rb`:

```ruby
test "normaliza el rut quitando puntos y agregando guion" do
  na = NeighborhoodAssociation.new(name: "J", rut: "70.207.956-k")
  na.valid?
  assert_equal "70207956-K", na.rut
end

test "es invalido sin rut" do
  na = NeighborhoodAssociation.new(name: "J", rut: nil)
  assert_not na.valid?
  assert_includes na.errors.attribute_names, :rut
end

test "es invalido con digito verificador incorrecto" do
  na = NeighborhoodAssociation.new(name: "J", rut: "70207956-5")
  assert_not na.valid?
  assert_includes na.errors.attribute_names, :rut
end

test "es valido con rut correcto" do
  na = NeighborhoodAssociation.new(name: "J", rut: "71724860-0", commune: communes(:commune_0_0_0))
  assert na.valid?, na.errors.full_messages.to_sentence
end

test "rut es unico" do
  existente = neighborhood_associations(:manios_de_buin)
  dup = NeighborhoodAssociation.new(name: "Otra", rut: existente.rut)
  assert_not dup.valid?
  assert_includes dup.errors.attribute_names, :rut
end
```

- [ ] **Step 2: Correr los tests para verlos fallar**

Run: `bin/rails test test/models/neighborhood_association_test.rb -n "/rut/"`
Expected: FAIL (normalización y validación aún no existen).

- [ ] **Step 3: Implementar normalización + validación en el modelo**

En `app/models/neighborhood_association.rb`, tras `validates :name, presence: true`:

```ruby
  before_validation :normalize_rut

  # BR-119: RUT obligatorio, único y con DV válido (módulo 11). Reutiliza RunValidator.
  validates :rut, presence: true, uniqueness: true
  validates :rut, run: true, if: -> { rut.present? }
```

y como método privado (agregar `private` al final del modelo si no existe):

```ruby
  private

  # Mismo patrón que VerifiedIdentity#normalize_run_field.
  def normalize_rut
    return unless rut.present?
    self.rut = rut.to_s.gsub(/[.\-\s]/, "").upcase
    self.rut = "#{rut[0..-2]}-#{rut[-1]}" if rut.match?(/\A\d{7,8}[0-9K]\z/)
  end
```

- [ ] **Step 4: Correr los tests para verlos pasar**

Run: `bin/rails test test/models/neighborhood_association_test.rb -n "/rut/"`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add app/models/neighborhood_association.rb test/models/neighborhood_association_test.rb
git commit -m "feat(junta): normalizacion y validacion de rut (BR-119)"
```

---

### Task 5: Enforcement BR-120 — no emitir certificado sin junta con RUT

**Files:**
- Modify: `app/models/residence_certificate.rb` (método `issue!`, ~línea 117)
- Test: `test/models/residence_certificate_test.rb`

Nota: con `rut NOT NULL` el caso es estructuralmente imposible, pero la guarda documenta y protege el invariante legal (BR-120) ante futuros cambios.

- [ ] **Step 1: Escribir el test que falla**

Agregar a `test/models/residence_certificate_test.rb`:

```ruby
test "issue! falla si la junta no tiene rut" do
  cert = residence_certificates(:paid_unissued) # una fixture en estado paid
  cert.neighborhood_association.update_column(:rut, nil) # saltar validacion a proposito
  assert_raises(RuntimeError) { cert.issue! }
end
```

(Si no existe una fixture `paid_unissued`, usar la que esté en estado `paid` sin emitir; ver `test/fixtures/residence_certificates.yml` y ajustar el nombre.)

- [ ] **Step 2: Correr el test para verlo fallar**

Run: `bin/rails test test/models/residence_certificate_test.rb -n "/issue! falla si la junta no tiene rut/"`
Expected: FAIL (hoy emite igual).

- [ ] **Step 3: Agregar la guarda en `issue!`**

En `app/models/residence_certificate.rb`, dentro de `issue!`, tras la línea `raise "Cannot issue certificate ..." unless paid?`:

```ruby
    raise "Cannot issue certificate ##{id}: junta sin RUT (no constituida legalmente, BR-120)" if neighborhood_association.rut.blank?
```

- [ ] **Step 4: Correr el test para verlo pasar**

Run: `bin/rails test test/models/residence_certificate_test.rb -n "/issue! falla si la junta no tiene rut/"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/residence_certificate.rb test/models/residence_certificate_test.rb
git commit -m "feat(cert): bloquear emision si la junta no tiene rut (BR-120)"
```

---

### Task 6: Superadmin — campo RUT en el formulario de junta

**Files:**
- Modify: `app/controllers/superadmin/neighborhood_associations_controller.rb` (`neighborhood_association_params`, ~línea 89)
- Modify: `app/views/superadmin/neighborhood_associations/_form.html.erb`
- Modify: `config/locales/es.yml`, `config/locales/en.yml`
- Test: `test/controllers/superadmin/neighborhood_associations_controller_test.rb`

- [ ] **Step 1: Escribir el test de controller que falla**

Agregar a `test/controllers/superadmin/neighborhood_associations_controller_test.rb`:

```ruby
test "crea junta con rut" do
  sign_in users(:superadmin) # ajustar al helper/fixture de superadmin del proyecto
  assert_difference "NeighborhoodAssociation.count", 1 do
    post superadmin_neighborhood_associations_path, params: {
      neighborhood_association: { name: "Nueva Junta", rut: "83014859-0" }
    }
  end
  assert_equal "83014859-0", NeighborhoodAssociation.last.rut
end
```

- [ ] **Step 2: Correr el test para verlo fallar**

Run: `bin/rails test test/controllers/superadmin/neighborhood_associations_controller_test.rb -n "/crea junta con rut/"`
Expected: FAIL (`rut` no está permitido → `NOT NULL` viola / no persiste).

- [ ] **Step 3: Permitir `rut` en strong params**

En `app/controllers/superadmin/neighborhood_associations_controller.rb`:

```ruby
  def neighborhood_association_params
    params.require(:neighborhood_association).permit(:name, :rut)
  end
```

- [ ] **Step 4: Agregar el campo al formulario**

En `app/views/superadmin/neighborhood_associations/_form.html.erb`, entre el bloque de `:name` y el `form.submit`:

```erb
  <% invalid = neighborhood_association.errors.include?(:rut) %>
  <%= form.label :rut, I18n.t('activerecord.attributes.neighborhood_association.rut'), class: "floating-label" do %>
    <%= form.text_field :rut, class: "input w-full validator #{'input-error' if invalid}", required: true, placeholder: I18n.t('activerecord.attributes.neighborhood_association.rut') %>
    <span><%= I18n.t('activerecord.attributes.neighborhood_association.rut') %></span>
  <% end %>
  <%= raw(error_message(invalid, neighborhood_association.errors.full_messages_for(:rut))) %>
```

- [ ] **Step 5: Agregar la traducción del atributo**

En `config/locales/es.yml`, bajo `activerecord: attributes: neighborhood_association:` agregar `rut: RUT`. Repetir en `config/locales/en.yml` con `rut: Tax ID (RUT)`. (Las claves de error `invalid_rut_format`/`invalid_rut_check_digit` ya existen para `RunValidator`.)

- [ ] **Step 6: Correr el test para verlo pasar**

Run: `bin/rails test test/controllers/superadmin/neighborhood_associations_controller_test.rb -n "/crea junta con rut/"`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/superadmin/neighborhood_associations_controller.rb app/views/superadmin/neighborhood_associations/_form.html.erb config/locales/es.yml config/locales/en.yml test/controllers/superadmin/neighborhood_associations_controller_test.rb
git commit -m "feat(superadmin): campo rut en formulario de junta"
```

---

### Task 7: Verificación integral

- [ ] **Step 1: Suite completa**

Run: `bin/rails test`
Expected: PASS (0 failures, 0 errors). Si algún test falla por `NOT NULL rut`, volver a Task 3 y corregir el sitio de creación.

- [ ] **Step 2: Linters**

Run: `bin/standardrb && bundle exec erb_lint --lint-all`
Expected: sin ofensas (o autofix con `bin/standardrb --fix`).

- [ ] **Step 3: Zeitwerk + seguridad rápida**

Run: `bin/rails zeitwerk:check`
Expected: OK.

- [ ] **Step 4: Commit final si hubo ajustes**

```bash
git add -A
git commit -m "chore(junta): ajustes finales fundacion rut"
```

---

## Self-Review (cobertura del spec)

- **BR-119** (rut obligatorio, único, DV) → Tasks 1, 4.
- **BR-120** (no emitir sin rut) → Task 5.
- **BR-121** (no existe junta sin rut; rut no codifica entorno) → Task 1 (`NOT NULL`), Tasks 2/3 (todas las juntas con rut). El rango usado es solo para backfill/tests, sin semántica de entorno.
- **Backfill de juntas heredadas / demo** → Task 1 (prod), Task 3 (`DemoJuntaSeeder` con los 10 RUTs provistos), Task 2 (fixtures).
- **Ripple `NOT NULL`** → Task 3 (grep + fix de creaciones inline).

Fuera de alcance de este plan (van en Plan 2): `AdministrationRequest`, flujo del panel, revisión del staff, transacción de aprobación y notificaciones.
