# Code Audit - 2026-07-21

Auditoría completa del codebase yuntapp. No se encontraron auditorías previas en `docs/`. Todos los tests (480) pasan, Brakeman reporta 0 warnings, Bundler Audit reporta 0 vulnerabilidades y StandardRB reporta 0 ofensas en 293 archivos. Los hallazgos se enfocan en problemas de autorización multi-tenant, seguridad de datos, race conditions, inconsistencias de modelo y code quality.

---

## Severidad Alta

### H1. `search` actions sin scope multi-tenant en admin controllers

**Archivos:**
- `app/controllers/admin/residence_certificates_controller.rb:27`
- `app/controllers/admin/household_units_controller.rb:22`
- `app/controllers/admin/neighborhood_delegations_controller.rb:22`
- `app/controllers/admin/board_members_controller.rb:22`
- `app/controllers/admin/listings_controller.rb:22`
- `app/controllers/admin/users_controller.rb:22`
- `app/controllers/admin/members_controller.rb:22`

```ruby
# Ejemplo en admin/household_units_controller.rb:22
def search
  @household_units = params[:items].present? ? HouseholdUnit.filter_by_id(params[:items]) : HouseholdUnit.all
  # Sin current_neighborhood_association scope — devuelve TODAS las asociaciones
end
```

Mientras que `set_household_units` y `set_household_unit` usan correctamente `current_neighborhood_association.household_units`, la acción `search` (GET, JSON) expone todos los registros de todas las asociaciones sin filtrar. Lo mismo ocurre en otros 6 controllers admin.

**Impacto:** Cualquier admin de cualquier junta puede ver (y filtrar) todos los `HouseholdUnit`, `NeighborhoodDelegation`, `BoardMember`, `Listing`, `Member` y `User` de TODAS las juntas del sistema a través del endpoint `/admin/{resource}/search.json`. Violación directa de BR-007.

**Fix:** Aplicar el mismo `current_neighborhood_association` scope que en los métodos protegidos `set_*`:

```ruby
def search
  scope = current_neighborhood_association.household_units
  @household_units = params[:items].present? ? scope.filter_by_id(params[:items]) : scope
end
```

---

### H2. `Admin::ListingsController` sin ningún scope multi-tenant

**Archivo:** `app/controllers/admin/listings_controller.rb:77-78`

```ruby
def set_listing
  @listing = Listing.find(params[:id])  # Sin scope de asociación
end

def set_listings
  @listings = Listing.all  # TODOS los listings del sistema
end
```

A diferencia de los otros controllers admin que al menos filtran en `set_*` (pero no en `search`), este controller no filtra NUNCA por asociación. `Listing` no pertenece a `NeighborhoodAssociation` — está vinculado directamente a `User`, y `User` pertenece a `NeighborhoodAssociation`. Adicionalmente, el `listing_params` permite `user_id` arbitrario.

**Impacto:** Cualquier admin puede ver, editar, crear y eliminar listings de cualquier usuario del sistema. Además puede asignar listings a cualquier `user_id`, incluso de otras asociaciones.

**Fix:** Agregar scope multi-tenant en todos los métodos:

```ruby
def set_listing
  @listing = current_neighborhood_association.listings.find(params[:id])
end

def set_listings
  @listings = current_neighborhood_association.listings
end
```

Y agregar `has_many :listings, through: :users` en `NeighborhoodAssociation`, o scopear vía users IDs.

---

### H3. Race condition en `IssueCertificateJob` — certificado puede emitirse dos veces

**Archivo:** `app/jobs/issue_certificate_job.rb:6-15`

```ruby
def perform(certificate_id)
  certificate = ResidenceCertificate.find_by(id: certificate_id)
  return if certificate.nil?
  return if certificate.issued?
  return unless certificate.paid?

  certificate.issue!       # Transición paid → issued
  CertificatePdfService.new(certificate).generate_and_attach!
  ResidenceCertificateMailer.issued(certificate).deliver_later
end
```

Si `IssueCertificateJob` se ejecuta dos veces simultáneamente (race condition típica de jobs, posiblemente por reintentos paralelos o por dos webhooks de MP cerca del timeout), ambos procesos pueden pasar los guards `if certificate.issued?` y `unless certificate.paid?` antes de que el primero complete la transacción `issue!`. `issue!` usa una transacción, pero no hay un lock a nivel DB.

**Impacto:** Doble emisión del mismo certificado: dos PDFs, dos correos, posible folio duplicado o token único violado (aunque el índice único en `validation_token` lo frenaría con excepción). En el peor caso, el segundo job lanza error, el certificado queda en `paid` (retry loop infinito).

**Fix:** Agregar `with_lock` en `issue!` o un lock optimista/pesimista antes de la transición:

```ruby
def perform(certificate_id)
  certificate = ResidenceCertificate.find_by(id: certificate_id)
  return if certificate.nil?

  certificate.with_lock do
    return if certificate.issued?
    return unless certificate.paid?
    certificate.issue!
  end

  CertificatePdfService.new(certificate).generate_and_attach!
  ResidenceCertificateMailer.issued(certificate).deliver_later
end
```

---

### H4. Webhook de MercadoPago no valida `external_reference` contra datos locales

**Archivo:** `app/controllers/webhooks/mercadopago_controller.rb:59-83`

```ruby
def process_payment(payment, data_id)
  return unless payment.is_a?(Hash)
  ...
  certificate = ResidenceCertificate.find_by(id: external_reference)
  ...
  when "approved"
    certificate.mark_as_paid!(payment_id: data_id)
  ...
end
```

El webhook recibe un `payment_id` de MP, verifica firma HMAC (BR-072), consulta el payment en MP para obtener su estado, y si es "approved" marca el certificado como pagado. Sin embargo, no hay validación de que el `amount` del pago coincida con el `amount` del certificado, ni de que el `neighborhood_association` del certificado coincida con lo esperado.

**Impacto:** Si un atacante llegara a generar un pago válido por un monto menor (ej: $1 en vez de $5.000) y lograra que ese payment_id sea referenciado hacia un certificado de mayor valor (manipulando la `external_reference`), el sistema marcaría como pagado un certificado por un monto incorrecto. Aunque la firma HMAC mitiga el vector principal, un error de configuración de MP que asigne `external_reference` incorrecta pasaría inadvertido.

**Fix:** Validar el `amount` del pago contra el `certificate.amount`:

```ruby
def process_payment(payment, data_id)
  return unless payment.is_a?(Hash)
  ...
  certificate = ResidenceCertificate.find_by(id: external_reference)
  return unless certificate

  paid_amount = payment["transaction_amount"] || payment[:transaction_amount]
  unless paid_amount.to_i == certificate.amount
    Rails.logger.warn("MercadoPago webhook: amount mismatch for certificate ##{certificate.id} (expected #{certificate.amount}, got #{paid_amount})")
    return
  end
  ...
end
```

---

### H5. `VerificationsController` no filtra certificados `paid` — pero `find_for_public_verification` sí

**Archivo:** `app/controllers/verifications_controller.rb:30`

```ruby
def show
  @certificate = ResidenceCertificate.find_for_public_verification(params[:identifier])
  if @certificate.nil?
    render :not_found, status: :not_found
  end
end
```

El scope `findable_publicly` filtra correctamente solo certificados `issued`. No es un bug actual, pero si se eliminara ese scope por error, quedaría expuesta información sensible de certificados no emitidos.

Marcado como Alta porque es una dependencia frágil: el scope protector está a nivel de modelo, pero el controller no tiene validación redundante. Si alguien modifica `find_for_public_verification` y olvida el scope, certificados en `paid` con su RUN, dirección y datos quedarían públicamente visibles.

**Fix:** Agregar validación redundante en el controller:

```ruby
def show
  @certificate = ResidenceCertificate.find_for_public_verification(params[:identifier])
  if @certificate.nil? || !@certificate.issued?
    render :not_found, status: :not_found
  end
end
```

---

## Severidad Media

### M1. N+1 query en `panel/residence_certificates#create`

**Archivo:** `app/controllers/panel/residence_certificates_controller.rb:40-41`

```ruby
residency = current_user.household_unit.approved_residencies.find(params[:residence_certificate][:member_id])
member = residency.verified_identity.members.find_by(neighborhood_association: association)
```

Dos queries secuenciales en el hot path de creación de certificado (transacción de pago). Miramos datos de `residency` y su `verified_identity` para buscar el `member`.

**Impacto:** 2 queries extras por cada certificado creado. Bajo carga (muchos certificados simultáneos), esto agrega latencia.

**Fix:** Usar `includes`:

```ruby
residency = current_user.household_unit.approved_residencies
  .includes(verified_identity: :members)
  .find(params[:residence_certificate][:member_id])
member = residency.verified_identity.members.find_by(neighborhood_association: association)
```

---

### M2. `FamilyGroup#household_admin` no protege contra `nil`

**Archivo:** `app/models/family_group.rb:6-8`

```ruby
def household_admin
  residencies.find_by(household_admin: true)
end
```

Retorna `nil` si no hay un `household_admin`. Esto es correcto para búsquedas, pero si se usa con `delegate` u otros métodos que esperan un objeto real, causaría `NoMethodError`. Similar al problema de `User#household_admin?` que ya maneja con `|| false`.

**Impacto:** Llamadas encadenadas como `family_group.household_admin.name` explotarían si no hay admin. Es un bug latente en vistas o helpers.

**Fix:** Agregar manejo de nil o un método `household_admin?`:

```ruby
def household_admin
  residencies.find_by(household_admin: true)
end

def household_admin?
  household_admin.present?
end
```

---

### M3. `generate_folio!` y `next_folio` tienen race condition de folio

**Archivo:** `app/models/residence_certificate.rb:82-84 y 152-155`

```ruby
def next_folio
  sequence = self.class.where(neighborhood_association_id: neighborhood_association_id).maximum(:id) || 0
  "CR-#{neighborhood_association_id}-#{sequence + 1}"
end
```

Dos certificados emitidos concurrentemente pueden leer el mismo `maximum(:id)` y generar el mismo folio. El índice único `(neighborhood_association_id, folio)` en DB lo detendría en el `save!`, pero el job fallaría y entraría en retry.

**Impacto:** Retry de jobs, posible double-billing o confusión en la trazabilidad de folios.

**Fix:** Usar una secuencia atómica con `with_lock` dentro de `issue!`, o usar un `AUTOINCREMENT` explícito para el sequence number. Como el folio se genera dentro de `issue!` que ya tiene transacción, agregar `with_lock` en `ResidenceCertificate`:

No simple, ya que `issue!` no es un método de instancia que adquiera lock. Recomendación: usar un contador atómico con `update_counters` o delegar a un `SequenceNumber` por asociación.

---

### M4. `Admin::OnboardingRequestsController#search` expone solicitudes hasta `draft`

**Archivo:** `app/controllers/admin/onboarding_requests_controller.rb:16-23`

```ruby
def search
  @onboarding_requests = params[:items].present? ? base_scope.filter_by_id(params[:items]) : base_scope
end

def base_scope
  current_neighborhood_association.onboarding_requests.where.not(status: "draft")
end
```

A diferencia de otros search actions, este está correctamente scoped por asociación y excluye `draft`. Se menciona como hallazgo M4 para destacar que es el único que lo hace bien y que el resto de los controllers deberían replicar este patrón (ver H1).

**Impacto:** No es un bug — es la implementación correcta que sirve como benchmark. Se referencia para el orden de implementación.

---

### M5. Index únicos en SQLite con `WHERE ... IS NOT NULL` no son portables a PostgreSQL

**Archivo:** `db/schema.rb:80, 209, 211, 239, 240, 241, 303`

Varios índices únicos parciales (con `WHERE`):
- `index_communes_on_code (UNIQUE) WHERE code IS NOT NULL`
- `index_regions_on_code (UNIQUE) WHERE code IS NOT NULL`
- `index_regions_on_position (UNIQUE) WHERE position IS NOT NULL`
- `index_residence_certificates_on_payment_id (UNIQUE) WHERE payment_id IS NOT NULL`
- `index_residence_certificates_on_validation_code (UNIQUE) WHERE validation_code IS NOT NULL`
- `index_residence_certificates_on_validation_token (UNIQUE) WHERE validation_token IS NOT NULL`
- `index_users_on_confirmation_token (UNIQUE) WHERE confirmation_token IS NOT NULL`

SQLite soporta índices parciales desde 3.8, pero PostgreSQL requiere sintaxis ligeramente diferente (`CREATE UNIQUE INDEX ... WHERE` funciona en ambos, pero el `IS NOT NULL` en columnas que pueden ser NULL no es necesario en PostgreSQL para unicidad — permite múltiples NULLs por defecto). Esto no es bloqueante hoy con SQLite, pero indica que una migración a PostgreSQL requeriría refactor.

**Impacto:** Si en el futuro se migra a PostgreSQL, estos índices podrían no migrarse correctamente con `db:schema:load`.

**Fix:** Documentar en ADR que la app usa SQLite (ADR-005) y que estos índices deberían revisarse si se cambia de RDBMS.

---

### M6. `User#household_unit` usa `residency&.household_unit` sin verificar asociación correcta

**Archivo:** `app/models/user.rb:35-37`

```ruby
def household_unit
  residency&.household_unit
end
```

El método `residency` busca la residencia más reciente del `verified_identity`, pero no verifica que la residencia pertenezca a la asociación actual del usuario (`neighborhood_association`). Un usuario podría tener residencias de asociaciones anteriores (si se mudó) y `residency` devolvería la más reciente, que podría ser de otra asociación.

**Impacto:** En el panel, `current_user.household_unit` podría devolver un `HouseholdUnit` de una asociación anterior, causando que el usuario pueda ver residencias o certificados de otra junta.

**Fix:** Scopear por asociación actual:

```ruby
def household_unit
  residency&.household_unit
end

def residency
  verified_identity&.residencies
    &.approved
    &.joins(:household_unit)
    &.where(household_units: {neighborhood_delegation: {neighborhood_association_id: neighborhood_association_id}})
    &.order(created_at: :desc)
    &.first
end
```

---

### M7. `CertificatePricing#close_previous_pricing!` usa `update_all` sin touch de cache

**Archivo:** `app/models/certificate_pricing.rb:28-31`

```ruby
def close_previous_pricing!
  self.class
    .where(neighborhood_association: neighborhood_association)
    .active
    .update_all(effective_to: Time.current, updated_at: Time.current)
end
```

`update_all` no ejecuta callbacks ni actualiza `updated_at` vía Rails automáticamente (aunque aquí se pasa explícitamente). Esto puede dejar caches de ActiveRecord o de vista con datos stale (si alguien cacheó el pricing anterior).

**Impacto:** Stale data en caches de pricing. El `updated_at` se pasa manualmente, pero otros timestamps como `updated_by` (si existieran) quedarían incorrectos.

**Fix:** Usar `update_all` es intencional (performance), pero considerar `touch: true` en el callback o al menos verificar que `updated_at` se pase correctamente (ya se hace). Es más una advertencia que un bug.

---

## Severidad Baja

### L1. `IdentityVerificationRequest` duplica lógica de normalización con `VerifiedIdentity`

**Archivos:**
- `app/models/identity_verification_request.rb:69-83`
- `app/models/verified_identity.rb:35-49`

Ambos modelos tienen métodos casi idénticos: `normalize_run_field`, `normalize_names`, `capitalize_each_word`. Esto es código duplicado que puede divergir con el tiempo.

**Fix:** Extraer a un concern compartido `Normalizable` o a un service object `RunNormalizer`.

---

### L2. `panel/onboarding_controller.rb` — método `update_step2` elimina errores de campos no-enviados

**Archivo:** `app/controllers/panel/onboarding_controller.rb:231-236`

```ruby
@identity_request.errors.attribute_names.each do |attr|
  next if attr == :base
  unless attr.to_s == field_name.to_s
    @identity_request.errors.delete(attr)
  end
end
```

Se limpian errores de otros campos para mostrar solo el error del campo editado. Esto es una mitigación de UX que puede ocultar errores reales de validación (ej: formato inválido de RUN que se valida siempre, incluso en autosave).

**Impacto:** Bajo. Solo afecta UX durante el autosave parcial del onboarding. Errores completos se muestran al hacer "continuar".

---

### L3. `panel/onboarding_controller.rb` — método `build_cascading_data` carga todas las comunas/regiones en memoria

**Archivo:** `app/controllers/panel/onboarding_controller.rb:603-623`

```ruby
def build_cascading_data
  associations_by_commune = NeighborhoodAssociation.where.not(commune_id: nil).order(:name).group_by(&:commune_id)
  commune_ids = associations_by_commune.keys
  communes = Commune.where(id: commune_ids).order(:name).includes(:region)
  communes.group_by { |c| c.region }.map do |region, region_communes|
    ...
  end.sort_by { |r| r[:name] }
end
```

Todas las comunas y regiones de Chile se cargan en memoria y se serializan a JSON en cada request a `step1` del onboarding. Esto es ~300+ comunas y ~16 regiones, no es masivo pero es innecesario cargar siempre.

**Impacto:** Bajo. ~10KB de datos serializados en cada visita al paso 1. Podría optimizarse con fragment caching.

---

### L4. Controller `Admin::UsersController` usa interpolación directa en `order()` para sort

**Archivo:** `app/controllers/admin/users_controller.rb:89`

```ruby
@users = @users.order("#{params[:sort_column]} #{params[:sort_direction]}")
```

Mientras que todos los otros admin controllers usan `sort_scope(sort_params[:sort_column].to_s)`, este controller usa interpolación directa de SQL.

**Impacto:** Riesgo bajo (sort_column y sort_direction están permitidos en strong params), pero es una inconsistencia con el patrón del proyecto y un potencial SQL injection si se agregaran más columnas permitidas sin sanitizar.

**Fix:** Usar el mismo patrón `sort_scope` que el resto:

```ruby
@users = @users.send(sort_scope(sort_params[:sort_column].to_s), sort_params[:sort_direction]) if sort_params.present?
```

---

### L5. `Admin::ResidenceCertificatesController` hereda de `ApplicationController` en vez de `Admin::ApplicationController`

**Archivo:** `app/controllers/admin/residence_certificates_controller.rb:2`

```ruby
class ResidenceCertificatesController < ApplicationController
```

No hereda de `Admin::ApplicationController` sino de `ApplicationController`. Esto significa que no ejecuta `ensure_neighborhood_admin!` (BR-007/BR-052). Depende de `current_neighborhood_association` que no está definido aquí.

**Impacto:** El método `current_neighborhood_association` no está disponible. Sin embargo, el método `current_neighborhood_association` sí parece funcionar — examinando `ApplicationController`, no tiene este helper. Agregar la herencia correcta garantiza consistencia con el resto de controllers admin.

**Fix:** Cambiar a `Admin::ApplicationController`:

```ruby
class ResidenceCertificatesController < Admin::ApplicationController
```

Idem para `Admin::HouseholdUnitsController`, `Admin::NeighborhoodDelegationsController`, `Admin::BoardMembersController`, `Admin::ListingsController`, `Admin::UsersController`, `Admin::CertificatePricingsController`.

---

### L6. `residence_verification_request.rb` — validación `number` con `allow_blank: true` no protege contra nil en la práctica

**Archivo:** `app/models/residence_verification_request.rb:12-14`

```ruby
validates :number, presence: true, allow_blank: true
validates :neighborhood_delegation_id, presence: true, if: -> { street_name.blank? }, allow_blank: true
validates :street_name, presence: true, if: -> { neighborhood_delegation_id.blank? }, allow_blank: true
```

`presence: true` con `allow_blank: true` es contradictorio: el primero valida que no esté vacío, el segundo permite que esté vacío. El `allow_blank: true` prevalece en Rails. La intención probablemente es que `number` sea obligatorio, pero `street_name` o `neighborhood_delegation_id` sean mutuamente excluyentes.

**Impacto:** Se pueden guardar `ResidenceVerificationRequest` sin `number`, lo que contradice BR-020.

**Fix:**

```ruby
validates :number, presence: true
validates :neighborhood_delegation_id, presence: true, if: -> { street_name.blank? }
validates :street_name, presence: true, if: -> { neighborhood_delegation_id.blank? }
```

---

### L7. `residence_certificate.rb` — método `generate_folio!` no se usa en el flujo actual

**Archivo:** `app/models/residence_certificate.rb:81-84`

```ruby
def generate_folio!
  sequence = self.class.where(neighborhood_association_id: neighborhood_association_id).maximum(:id) || 0
  update!(folio: "CR-#{neighborhood_association_id}-#{sequence + 1}")
end
```

Este método es dead code — el folio se genera en `next_folio` usado por `issue!`. `generate_folio!` no es llamado desde ningún controller ni job. Conservarlo puede causar confusión.

**Fix:** Eliminar `generate_folio!` o marcar como deprecated.

---

## Resumen

| Severidad | Count | IDs |
|-----------|-------|-----|
| **Alta**  | 5     | H1-H5 |
| **Media** | 7     | M1-M7 |
| **Baja**  | 7     | L1-L7 |

## Orden recomendado de implementación

1. **H1 + H2 + L5** — La violación multi-tenant en search actions (H1) y en ListingsController (H2) es la más crítica. Corregir la herencia de controllers admin (L5) está relacionado. **Estimación: ~2-3h**
2. **H3 + M3** — Race conditions en IssueCertificateJob y generación de folio. Son bugs de producción latentes. **Estimación: ~2h**
3. **H4** — Validación de amount en webhook de MP. Seguridad de pagos. **Estimación: ~1h**
4. **H5** — Validación redundante en verificación pública. **Estimación: ~30min**
5. **M1 + M6** — N+1 en certificados y scope de household_unit. Performance y corrección de datos. **Estimación: ~1h**
6. **M2 + L6** — Robustez de `FamilyGroup` y validación de `ResidenceVerificationRequest`. **Estimación: ~30min**
7. **M7 + M4 + L1 + L2 + L3 + L4 + L7** — Code quality, normalización duplicada, SQL injection potencial en sort, dead code. **Estimación: ~2h**
