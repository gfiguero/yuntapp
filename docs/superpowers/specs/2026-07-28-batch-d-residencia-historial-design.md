# Batch D — Residencia como historial de estancias (#94 + #97)

**Fecha:** 2026-07-28
**Origen:** auditoría de correctitud 2026-07-26, issues GitHub #94 y #97 (prioridad Alta).
**Rama:** `worktree-fix-batch-d-residencia-historial`

## Principio rector

Una `Residency` representa **una estancia** (un período de residencia de una identidad en un
domicilio), **no** un vínculo permanente. Irse y volver produce **dos filas** de `Residency`.

- El `HouseholdUnit` es una estructura **física**: nunca se duplica ni cambia por movimientos de
  personas. Siempre se reutiliza.
- Todo el historial se conserva (identidades, `VerifiedResidence`, estancias). Nada se sobrescribe
  ni se destruye (coherente con BR-100/BR-030).
- Los dependientes **no** se migran automáticamente. Al volver el jefe de hogar, cada dependiente se
  re-onboardea desde cero (nueva estancia); su estancia anterior queda como historial (BR-034/035/069/099).
- **No** se modifica BR-038: la `Residency` no gana un estado `inactive`. La estancia "vigente" se
  **deriva** como la última estancia aprobada por identidad (patrón que `User#residency` ya usa).

## Contexto verificado en el código

- `residencies` ya tiene su propia FK `verified_residence_id` (cada estancia apunta a una `VerifiedResidence`).
- `HouseholdUnit` también tiene `verified_residence_id` (`belongs_to :verified_residence, optional: true`),
  columna **redundante**: se **lee** operativamente solo en `admin/dependent_reviews_controller.rb:49`.
- `admin/onboarding_reviews_controller.rb#approve_step3` sobrescribe `HouseholdUnit.verified_residence`
  al relinkear una dirección existente (`existing.update!(verified_residence:)`, ~línea 117).
- `residencies` tiene índice único `index_residencies_on_identity_and_unit`
  (`[verified_identity_id, household_unit_id]`, `unique: true`) → causa `RecordNotUnique` en re-onboarding
  e impide el historial de estancias.
- `User#residency` ya resuelve multiplicidad: `verified_identity.residencies.approved.order(created_at: :desc).first`
  (la última estancia aprobada). Igual patrón en `admin/onboarding_reviews/step3.html.erb:89`
  (`residencies.select(&:approved?).max_by(&:created_at)`).
- `HouseholdUnit#approved_residencies` (`has_many -> { where(status: "approved") }`) alimenta:
  - `panel/residence_certificates_controller#selectable_residencies` (línea 105) y el `find` de línea 53.
  - el selector `member_id` en `panel/residence_certificates/new.html.erb:22`.
  - el roster "quién vive aquí" en `admin/onboarding_reviews/step3.html.erb:276`.

## Cambios

### #94 — `VerifiedResidence` con dueño único (`Residency`)

1. **Migración**: `remove_reference :household_units, :verified_residence` (con su FK e índice).
2. **Modelo** `HouseholdUnit`: quitar `belongs_to :verified_residence, optional: true`.
3. **`approve_step3`**:
   - `HouseholdUnit.create!` deja de recibir `verified_residence:`.
   - El branch de relink deja de hacer `existing.update!(verified_residence:)`; solo referencia el
     `existing` sin mutarlo por este campo.
4. **`dependent_reviews#approve`**: el dependiente hereda `verified_residence` de
   `family_group.household_admin&.verified_residence` (la estancia del jefe de su `FamilyGroup`), **no**
   de `household_unit.verified_residence`. Guard: si `family_group.household_admin` es `nil`, abortar la
   transacción con un error claro (defensa ante el hallazgo M2 del code-audit).
5. **`demo_junta_seeder.rb`**: quitar `verified_residence:` del `HouseholdUnit.create!` (línea ~87);
   conservar el de `Residency.create!`.
6. **Fixtures**: quitar cualquier `verified_residence:` en `test/fixtures/household_units.yml` si existe.

### #97 — Historial de estancias (drop del índice único)

1. **Migración**: `remove_index :residencies, name: "index_residencies_on_identity_and_unit"`
   (era `[verified_identity_id, household_unit_id]`, `unique: true`). Se conservan los índices
   no-únicos sobre `verified_identity_id` y `household_unit_id`.
2. **`approve_step3`**: sin cambios de lógica adicionales — ya crea `FamilyGroup` y `Residency` nuevos
   en cada aprobación. Al no existir el índice único, el re-ingreso crea una **nueva estancia** y
   conserva las anteriores. **No** se usa `find_or_create_by` ni se reutiliza/sobrescribe la fila.
3. Los dependientes que vuelven (mismo RUN, mismo `household_unit`) dejan de chocar con el índice; su
   `Residency(dependent)` anterior queda en el `FamilyGroup` anterior como historial.

### "Residente actual" — deduplicación (evita el duplicado del regreso)

Al permitir múltiples estancias, la misma persona que se fue y volvió tendría dos `Residency`
aprobadas en el mismo `household_unit`. Para que el selector de certificados y el roster muestren una
sola fila por persona (la estancia vigente):

1. **`HouseholdUnit#current_residencies`**: devuelve la última `Residency` aprobada **por cada**
   `verified_identity` (una fila por persona). Implementación en Ruby sobre `approved_residencies`
   (`group_by(&:verified_identity_id)` → `max_by(&:created_at)`), o una consulta equivalente; se prioriza
   claridad y correctitud sobre micro-optimización (los domicilios tienen pocos residentes).
2. Usar `current_residencies` en:
   - `panel/residence_certificates_controller#selectable_residencies` (reemplaza `approved_residencies`
     como fuente; se mantiene el filtro por `Member` aprobado — BR-091).
   - el roster de `admin/onboarding_reviews/step3.html.erb:276`.
3. El `find(params[:member_id])` (línea 53) sigue operando por id de `Residency`; el id proviene del
   selector deduplicado, por lo que apunta a la estancia vigente.
4. `admin/onboarding_reviews_controller.rb:37`
   (`@existing_identity.residencies.pluck(:household_unit_id)`) → agregar `.uniq`.

El corte de acceso sigue siendo por `Member` aprobado (BR-091): quien se fue y **no** volvió queda
excluido del selector aunque su última estancia siga `approved`.

## Migración (una sola)

`remove_reference :household_units, :verified_residence, foreign_key: true` +
`remove_index :residencies, name: "index_residencies_on_identity_and_unit"`.

- **Sin backfill**: los datos ya viven en `Residency.verified_residence`.
- **Sin expand-contract**: tras los cambios de código (mismo PR) nadie lee la columna ni depende del
  índice único, por lo que la contracción es segura en un paso.

## Reglas de negocio

- Coherente con BR-030/100 (nada se destruye), BR-034/035/069/099 (dependientes no se migran), BR-038
  (sin estado `inactive` en `Residency`; vigencia derivada), BR-040/041/067 (aislamiento entre
  `FamilyGroup` y trazabilidad documental — el fix de #94 lo restaura), BR-091 (acceso por `Member`).
- No introduce reglas nuevas. Si al implementar surge un invariante nuevo (p. ej. "el selector de
  certificados usa la estancia vigente"), documentarlo como BR con el próximo ID disponible.

## Testing

- **#94**: un dependiente de `FamilyGroup` B hereda la `VerifiedResidence` del household_admin de B, y
  **no** la del último household_admin que onboardeó en la misma dirección (FamilyGroup A). Verificar
  también que `approve_step3` ya no toca `HouseholdUnit` por este campo.
- **#97**: re-onboarding de la misma identidad al mismo `household_unit` crea una segunda `Residency`
  aprobada sin lanzar `RecordNotUnique`; la estancia anterior se conserva; `User#residency` devuelve la
  nueva.
- **`current_residencies`**: una identidad con dos estancias aprobadas aparece una sola vez (la última);
  una identidad con una sola estancia aparece normal.
- **Regresión**: suite completa (`bin/rails test`) + `bin/ci` (incluye tests containerizados).

## Fuera de alcance (Batch D)

- Hallazgos Media (#98–#102) y Baja (#103, #105–#109).
- Revisión de BR-038 (marcar estancias terminadas): explícitamente **no** se aborda; la vigencia se
  deriva.
