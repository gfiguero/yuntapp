# Batch D — Residencia como historial de estancias — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolver #94 (VerifiedResidence con dueño único en `Residency`) y #97 (historial de estancias sin `RecordNotUnique`), modelando `Residency` como una estancia y no como un vínculo permanente.

**Architecture:** Una migración de contracción elimina la columna redundante `household_units.verified_residence_id` y el índice único `[verified_identity_id, household_unit_id]` de `residencies`. Los controllers de aprobación dejan de usar/sobrescribir el campo del `HouseholdUnit`; los dependientes heredan la residencia de su `FamilyGroup`; el re-ingreso crea una nueva `Residency`. Un método `HouseholdUnit#current_residencies` deriva "residente actual" (última estancia aprobada por identidad) para deduplicar el selector de certificados y el roster.

**Tech Stack:** Rails 8.1, SQLite3, Minitest + fixtures YAML.

**Spec:** `docs/superpowers/specs/2026-07-28-batch-d-residencia-historial-design.md`

---

## File Structure

- `db/migrate/<timestamp>_drop_household_unit_verified_residence_and_residency_uniqueness.rb` — Crear. Migración única (contracción).
- `db/schema.rb` — Modificado por la migración.
- `app/models/household_unit.rb` — Modificar: quitar `belongs_to :verified_residence`; agregar `current_residencies`.
- `app/controllers/admin/onboarding_reviews_controller.rb` — Modificar: `approve_step3` deja de tocar `HouseholdUnit.verified_residence`; `.uniq` en el pluck de household_unit_ids.
- `app/controllers/admin/dependent_reviews_controller.rb` — Modificar: `approve` hereda `verified_residence` de `family_group.household_admin`.
- `app/controllers/panel/residence_certificates_controller.rb` — Modificar: `selectable_residencies` usa `current_residencies`.
- `app/views/admin/onboarding_reviews/step3.html.erb` — Modificar (línea ~276): roster usa `current_residencies`.
- `app/services/demo_junta_seeder.rb` — Modificar: quitar `verified_residence:` del `HouseholdUnit.create!`.
- `test/fixtures/household_units.yml` — Modificar: quitar `verified_residence:` de `selendis_household`.
- `test/controllers/admin/onboarding_reviews_controller_test.rb` — Modificar tests que usan `hu.verified_residence`; agregar test de re-ingreso (#97).
- `test/controllers/admin/dependent_reviews_controller_test.rb` — Modificar/agregar: aserción de herencia (#94).
- `test/models/household_unit_test.rb` — Agregar tests de `current_residencies` (crear archivo si no existe).

---

## Task 1: Migración de contracción + cambios acoplados (deja la app booteable con el nuevo schema)

Esta tarea elimina la columna y el índice, y actualiza en el mismo commit todo lo que los referencia, para que la suite vuelva a verde. El RED intermedio es la propia rotura por el drop (fixtures/controllers que aún tocan la columna).

**Files:**
- Create: `db/migrate/<timestamp>_drop_household_unit_verified_residence_and_residency_uniqueness.rb`
- Modify: `db/schema.rb` (auto), `app/models/household_unit.rb`, `test/fixtures/household_units.yml`, `app/services/demo_junta_seeder.rb`, `app/controllers/admin/onboarding_reviews_controller.rb`, `app/controllers/admin/dependent_reviews_controller.rb`
- Modify (tests que referencian la columna): `test/controllers/admin/onboarding_reviews_controller_test.rb`

- [ ] **Step 1: Generar la migración**

Run: `bin/rails g migration DropHouseholdUnitVerifiedResidenceAndResidencyUniqueness`

Reemplazar el cuerpo del archivo generado por:

```ruby
class DropHouseholdUnitVerifiedResidenceAndResidencyUniqueness < ActiveRecord::Migration[8.1]
  def change
    # #94: Residency es la única dueña de la VerifiedResidence. La columna en
    # HouseholdUnit era redundante y provocaba herencia cruzada entre FamilyGroups.
    remove_reference :household_units, :verified_residence, foreign_key: true

    # #97: permitir historial de estancias — una identidad puede tener varias
    # Residency en el mismo HouseholdUnit a lo largo del tiempo (irse y volver).
    remove_index :residencies,
      column: [:verified_identity_id, :household_unit_id],
      name: "index_residencies_on_identity_and_unit",
      unique: true
  end
end
```

- [ ] **Step 2: Aplicar la migración**

Run: `bin/rails db:migrate`
Expected: migración OK; `db/schema.rb` ya no tiene `t.integer "verified_residence_id"` ni el índice en `household_units`, ni `index_residencies_on_identity_and_unit`.

- [ ] **Step 3: Quitar `belongs_to :verified_residence` de `HouseholdUnit`**

En `app/models/household_unit.rb`, eliminar la línea:

```ruby
  belongs_to :verified_residence, optional: true
```

- [ ] **Step 4: Quitar `verified_residence` del fixture `selendis_household`**

En `test/fixtures/household_units.yml`, en el bloque `selendis_household:`, eliminar la línea:

```yaml
  verified_residence: selendis_verified_residence
```

- [ ] **Step 5: Quitar `verified_residence` del `HouseholdUnit.create!` del seeder**

En `app/services/demo_junta_seeder.rb` (línea ~87), el `HouseholdUnit.create!` pasa de:

```ruby
      number: residence.number, street_name: residence.street_name, verified_residence: residence)
```

a:

```ruby
      number: residence.number, street_name: residence.street_name)
```

(Conservar el `verified_residence: residence` que va en los `Residency.create!` de las líneas ~91 y ~102.)

- [ ] **Step 6: `approve_step3` deja de tocar `HouseholdUnit.verified_residence`**

En `app/controllers/admin/onboarding_reviews_controller.rb`, el paso 5 (relink/creación de HouseholdUnit) pasa de:

```ruby
        # 5. Relink existing or create new HouseholdUnit
        household_unit = if params[:household_unit_id].present? && params[:household_unit_id] != "new"
          existing = current_neighborhood_association.household_units.find(params[:household_unit_id])
          existing.update!(verified_residence: verified_residence)
          existing
        else
          HouseholdUnit.create!(
            neighborhood_delegation: delegation,
            commune: residence_req.commune,
            number: residence_req.number,
            street_name: residence_req.street_name,
            address_detail: residence_req.address_detail,
            verified_residence: verified_residence
          )
        end
```

a:

```ruby
        # 5. Relink existing or create new HouseholdUnit (estructura física: no se
        #    le asocia VerifiedResidence; cada Residency lleva la suya — #94).
        household_unit = if params[:household_unit_id].present? && params[:household_unit_id] != "new"
          current_neighborhood_association.household_units.find(params[:household_unit_id])
        else
          HouseholdUnit.create!(
            neighborhood_delegation: delegation,
            commune: residence_req.commune,
            number: residence_req.number,
            street_name: residence_req.street_name,
            address_detail: residence_req.address_detail
          )
        end
```

(El `Residency.create!` del paso 7 conserva su `verified_residence: verified_residence` sin cambios.)

- [ ] **Step 7: `.uniq` en el pluck de household_unit_ids**

En `app/controllers/admin/onboarding_reviews_controller.rb` (línea ~37), de:

```ruby
      identity_hu_ids = @existing_identity&.residencies&.pluck(:household_unit_id) || []
```

a:

```ruby
      identity_hu_ids = @existing_identity&.residencies&.pluck(:household_unit_id)&.uniq || []
```

- [ ] **Step 8: Dependiente hereda la residencia de su FamilyGroup (#94)**

En `app/controllers/admin/dependent_reviews_controller.rb`, dentro de `approve`, de:

```ruby
        family_group = @dependent_request.family_group
        household_unit = family_group.household_unit
        verified_residence = household_unit.verified_residence
```

a:

```ruby
        family_group = @dependent_request.family_group
        household_unit = family_group.household_unit
        # #94/BR-067: el dependiente hereda la VerifiedResidence del household_admin
        # de SU FamilyGroup, no una compartida a nivel de HouseholdUnit.
        household_admin_residency = family_group.household_admin
        unless household_admin_residency
          raise "FamilyGroup ##{family_group.id} sin household_admin: no se puede heredar la residencia del dependiente"
        end
        verified_residence = household_admin_residency.verified_residence
```

- [ ] **Step 9: Arreglar tests existentes que usan `hu.verified_residence`**

En `test/controllers/admin/onboarding_reviews_controller_test.rb`:

(a) Test "step3 shows update transitions when pre-existing identity found" (~línea 83-90), de:

```ruby
      hu = household_units(:selendis_household)
      Residency.create!(
        verified_identity: existing_identity,
        verified_residence: hu.verified_residence,
        household_unit: hu,
        household_admin: false,
        status: "approved"
      )
```

a:

```ruby
      hu = household_units(:selendis_household)
      Residency.create!(
        verified_identity: existing_identity,
        verified_residence: verified_residences(:selendis_verified_residence),
        household_unit: hu,
        household_admin: false,
        status: "approved"
      )
```

(b) Test "step3 shows household units from identity's existing residencies" (~línea 150-156), de:

```ruby
      other_hu = household_units(:selendis_household)
      Residency.create!(
        verified_identity: existing_identity,
        verified_residence: other_hu.verified_residence,
        household_unit: other_hu,
        household_admin: false,
        status: "approved"
      )
```

a:

```ruby
      other_hu = household_units(:selendis_household)
      Residency.create!(
        verified_identity: existing_identity,
        verified_residence: verified_residences(:selendis_verified_residence),
        household_unit: other_hu,
        household_admin: false,
        status: "approved"
      )
```

(c) Test "approve_step3 creates all records": la aserción sobre el HouseholdUnit (~línea 228), de:

```ruby
      # Verify household unit linked to verified residence
      household_unit = HouseholdUnit.last
      assert_equal verified_residence, household_unit.verified_residence
```

a:

```ruby
      # #94: la VerifiedResidence vive en la Residency, no en el HouseholdUnit.
      household_unit = HouseholdUnit.last
      assert_equal verified_residence, Residency.last.verified_residence
```

- [ ] **Step 10: Correr la suite completa**

Run: `bin/rails test`
Expected: PASS (0 failures, 0 errors). Si algún otro test referencia `verified_residence` de un HouseholdUnit, aplicarle el mismo patrón (usar `verified_residences(:selendis_verified_residence)` o la Residency).

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "fix(#94): Residency es dueña única de la VerifiedResidence; drop columna household_units.verified_residence y del índice único de residencies (#97)"
```

---

## Task 2: Test de herencia del dependiente (#94)

**Files:**
- Test: `test/controllers/admin/dependent_reviews_controller_test.rb`

- [ ] **Step 1: Escribir el test de herencia family-scoped**

Agregar al final de la clase `Admin::DependentReviewsControllerTest` (antes del `end` de la clase):

```ruby
    test "approved dependent inherits verified_residence from its family_group household_admin (#94)" do
      sign_in @admin

      # Segundo FamilyGroup en el MISMO household_unit, con otro household_admin
      # y otra VerifiedResidence — no debe filtrarse al dependiente de selendis.
      other_household = household_units(:selendis_household)
      other_family_group = FamilyGroup.create!(household_unit: other_household)
      other_identity = VerifiedIdentity.create!(
        run: "7000001-6", first_name: "Otro", last_name: "Jefe",
        phone: "+56911110000", email: "otro.jefe@example.com"
      )
      other_residence = VerifiedResidence.create!(
        number: "999", neighborhood_association: @neighborhood_association
      )
      Residency.create!(
        verified_identity: other_identity, verified_residence: other_residence,
        household_unit: other_household, family_group: other_family_group,
        household_admin: true, status: "approved"
      )

      patch approve_admin_dependent_review_url(@dependent_request)

      new_dependent_residency = Residency.where(household_admin: false).order(:created_at).last
      expected = family_groups(:selendis_family_group).household_admin.verified_residence
      assert_equal expected, new_dependent_residency.verified_residence
      assert_not_equal other_residence, new_dependent_residency.verified_residence
    end
```

- [ ] **Step 2: Correr el test**

Run: `bin/rails test test/controllers/admin/dependent_reviews_controller_test.rb -n "/inherits verified_residence/"`
Expected: PASS (la lógica ya se implementó en Task 1). Si falla por `VerifiedResidence.create!` requiriendo más atributos, inspeccionar `app/models/verified_residence.rb` y agregar los `presence`-required (p. ej. `residence_verification_request` si fuera obligatorio; usar el mínimo válido).

- [ ] **Step 3: Commit**

```bash
git add test/controllers/admin/dependent_reviews_controller_test.rb
git commit -m "test(#94): dependiente hereda la VerifiedResidence de su FamilyGroup, no de otra familia del domicilio"
```

---

## Task 3: Test de historial de estancias (#97)

**Files:**
- Test: `test/controllers/admin/onboarding_reviews_controller_test.rb`

- [ ] **Step 1: Escribir el test de re-ingreso**

Agregar al final de la clase `Admin::OnboardingReviewsControllerTest`:

```ruby
    test "re-onboarding same identity to same household_unit creates a new residency (history preserved, #97)" do
      sign_in @admin

      # Estancia PREVIA de la misma identidad (mismo RUN del onboarding en curso)
      # en un household_unit existente — simula "se fue y vuelve".
      existing_identity = VerifiedIdentity.create!(
        run: @identity_request.run, first_name: "Karax", last_name: "Khalai",
        phone: "+56999990000", email: "karax.prev@example.com"
      )
      hu = household_units(:matching_karax_household)
      prior_residence = VerifiedResidence.create!(
        number: hu.number, neighborhood_association: @onboarding_request.neighborhood_association
      )
      prior_family_group = FamilyGroup.create!(household_unit: hu)
      prior_residency = Residency.create!(
        verified_identity: existing_identity, verified_residence: prior_residence,
        household_unit: hu, family_group: prior_family_group,
        household_admin: true, status: "approved"
      )

      # Aprobar el onboarding relinkeando al MISMO household_unit debe crear una
      # SEGUNDA Residency (nueva estancia), no reventar por índice único.
      assert_difference -> { Residency.where(verified_identity: existing_identity, household_unit: hu).count }, 1 do
        assert_nothing_raised do
          patch review_step3_admin_onboarding_request_url(@onboarding_request),
            params: {household_unit_id: hu.id}
        end
      end

      @onboarding_request.reload
      assert @onboarding_request.approved?

      # La estancia anterior se conserva intacta (historial).
      assert Residency.exists?(prior_residency.id)
      # User#residency devuelve la estancia más reciente.
      assert_equal existing_identity, @karax.reload.verified_identity
      latest = existing_identity.residencies.approved.order(created_at: :desc).first
      assert_not_equal prior_residency, latest
      assert_equal hu, latest.household_unit
    end
```

- [ ] **Step 2: Correr el test**

Run: `bin/rails test test/controllers/admin/onboarding_reviews_controller_test.rb -n "/re-onboarding same identity/"`
Expected: PASS (el índice único ya se eliminó en Task 1; `approve_step3` ya crea filas nuevas). Si falla porque `@karax` no queda ligado a `existing_identity` (la aprobación reutiliza la identidad por RUN), ajustar la aserción a `@karax.reload.verified_identity.run == @identity_request.run`.

- [ ] **Step 3: Commit**

```bash
git add test/controllers/admin/onboarding_reviews_controller_test.rb
git commit -m "test(#97): re-onboarding al mismo domicilio crea una nueva estancia y conserva el historial"
```

---

## Task 4: `HouseholdUnit#current_residencies` + wiring

**Files:**
- Modify: `app/models/household_unit.rb`
- Modify: `app/controllers/panel/residence_certificates_controller.rb`
- Modify: `app/views/admin/onboarding_reviews/step3.html.erb`
- Test: `test/models/household_unit_test.rb`

- [ ] **Step 1: Escribir el test de `current_residencies`**

Crear/editar `test/models/household_unit_test.rb`. Si el archivo no existe, crearlo con este contenido; si existe, agregar los tests dentro de la clase:

```ruby
require "test_helper"

class HouseholdUnitTest < ActiveSupport::TestCase
  test "current_residencies returns the latest approved residency per identity (#97)" do
    hu = household_units(:selendis_household)
    identity = verified_identities(:selendis_persona)
    residence = verified_residences(:selendis_verified_residence)

    # Estancia previa (más antigua) de la misma identidad en el mismo domicilio.
    older = Residency.create!(
      verified_identity: identity, verified_residence: residence,
      household_unit: hu, household_admin: true, status: "approved",
      created_at: 2.years.ago
    )
    # La fixture selendis_residency (misma identidad) es más reciente.
    current = residencies(:selendis_residency)

    ids = hu.current_residencies.map(&:id)
    assert_includes ids, current.id
    assert_not_includes ids, older.id, "no debe listar la estancia antigua de la misma persona"
    # Una sola fila por identidad.
    assert_equal hu.current_residencies.map(&:verified_identity_id).uniq.length,
      hu.current_residencies.length
  end

  test "current_residencies includes distinct identities once each" do
    hu = household_units(:selendis_household)
    ids = hu.current_residencies.map(&:verified_identity_id)
    assert_equal ids, ids.uniq
    # selendis (admin) y vorazun (dependiente) son residentes actuales.
    assert_includes ids, verified_identities(:selendis_persona).id
    assert_includes ids, verified_identities(:vorazun_persona).id
  end
end
```

- [ ] **Step 2: Correr el test (debe fallar)**

Run: `bin/rails test test/models/household_unit_test.rb`
Expected: FAIL con `NoMethodError: undefined method 'current_residencies'`.

- [ ] **Step 3: Implementar `current_residencies`**

En `app/models/household_unit.rb`, agregar dentro de la clase (junto a `household_admin`):

```ruby
  # #97: "residente actual" = última estancia aprobada por identidad. Con el
  # historial de estancias (varias Residency por identidad+domicilio), deduplica
  # a una fila por persona. El corte de acceso real sigue siendo Member (BR-091).
  def current_residencies
    approved_residencies
      .group_by(&:verified_identity_id)
      .values
      .map { |stays| stays.max_by(&:created_at) }
  end
```

- [ ] **Step 4: Correr el test (debe pasar)**

Run: `bin/rails test test/models/household_unit_test.rb`
Expected: PASS.

- [ ] **Step 5: Usar `current_residencies` en el selector de certificados**

En `app/controllers/panel/residence_certificates_controller.rb`, en `selectable_residencies`, de:

```ruby
      current_user.household_unit.approved_residencies.select do |residency|
```

a:

```ruby
      current_user.household_unit.current_residencies.select do |residency|
```

- [ ] **Step 6: Usar `current_residencies` en el roster de step3**

En `app/views/admin/onboarding_reviews/step3.html.erb` (línea ~276), de:

```erb
                  <%= hu.approved_residencies.map(&:name).join(', ').presence || I18n.t('admin.onboarding_reviews.step3.no_members') %>
```

a:

```erb
                  <%= hu.current_residencies.map(&:name).join(', ').presence || I18n.t('admin.onboarding_reviews.step3.no_members') %>
```

- [ ] **Step 7: Correr la suite completa**

Run: `bin/rails test`
Expected: PASS (0 failures, 0 errors).

- [ ] **Step 8: Commit**

```bash
git add app/models/household_unit.rb app/controllers/panel/residence_certificates_controller.rb app/views/admin/onboarding_reviews/step3.html.erb test/models/household_unit_test.rb
git commit -m "feat(#97): HouseholdUnit#current_residencies (residente actual) + úsalo en selector de certificados y roster"
```

---

## Task 5: Verificación final (linters + bin/ci)

**Files:** ninguno (solo verificación; corregir hallazgos si aparecen).

- [ ] **Step 1: Linters**

Run: `bin/standardrb && bundle exec erb_lint --lint-all`
Expected: sin ofensas. Corregir estilo con `bin/standardrb --fix` si hace falta.

- [ ] **Step 2: Pipeline completo**

Run: `bin/ci`
Expected: verde en estilo, seguridad (brakeman/bundler-audit/importmap), zeitwerk, tests locales, build de imagen de producción y tests containerizados. (Requiere Docker corriendo.)

- [ ] **Step 3: Commit de cierre (si los linters cambiaron algo)**

```bash
git add -A
git commit -m "chore: linters Batch D" || echo "nada que commitear"
```

---

## Self-Review (completado por el autor del plan)

- **Cobertura del spec:** #94 (drop columna + herencia dependiente + seeder + modelo) → Task 1/2. #97 (drop índice + historial) → Task 1/3. `current_residencies` + wiring → Task 4. Migración única sin backfill → Task 1. Tests → Tasks 2/3/4. Verificación → Task 5. Sin gaps.
- **Placeholders:** ninguno; todo el código y comandos son concretos.
- **Consistencia de tipos:** `current_residencies` devuelve `Array<Residency>`; se consume con `.select`/`.map` (Array), no con métodos de relación. `family_group.household_admin` → `Residency`; `.verified_residence` → `VerifiedResidence`. Coherente entre tasks.
