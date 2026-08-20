# Backlog

Este archivo contiene todas las tareas pendientes de implementar. El Arquitecto es responsable de priorizarlas y moverlas al sprint actual.

> **Saneado el 2026-08-20**: se verificó cada tarea contra el código en `master` (`093b84a`). Siete
> tareas estaban implementadas hace semanas sin marcarse. La evidencia de cada una queda anotada
> abajo para que no haya que volver a auditarlas.
>
> **Actualizado el 2026-08-20 (segunda pasada)**: se implementaron las cinco tareas de código
> pendientes — PRs #162 a #166, todos mergeados. TASK-017 queda **parcialmente** cerrada por
> decisión de alcance del owner: se remediaron los hallazgos con impacto real y el resto sigue
> listado. Dos hallazgos nuevos aparecieron durante ese trabajo: TASK-022 y TASK-023.

## Pendiente

> Origen: análisis BR/ADR del 2026-07-22 — detalle completo en `docs/2026-07-22-pendientes-br-adr.md`. Retomar en el orden listado.
>
> **Auditoría completa de las 99 reglas: `docs/2026-07-25-br-audit.md`** (2026-07-25). 82/99 OK. Los 17 hallazgos restantes ya están cubiertos por las tareas de abajo (mapeo BR→tarea en el informe). El grueso de los gaps de identidad se cierra con un único patrón: invocar `Member#deactivate!` sobre el `Member` anterior al detectar RUN duplicado (ver ADR-0014, TASK-004, TASK-018).

### Prioridad 1 — Seguridad multi-tenant (auditoría H1, H2, L5)
- [x] TASK-001: Scopear por `current_neighborhood_association` las acciones `search` de 7 controllers admin (H1, viola BR-007). **HECHO** — verificado 2026-08-20: las 8 acciones `search` de `admin/` scopean (`board_members`, `household_units`, `listings`, `members`, `neighborhood_delegations`, `residence_certificates`, `users`; `onboarding_requests` vía `base_scope`)
- [x] TASK-002: Agregar scope multi-tenant completo a `Admin::ListingsController` (H2). **HECHO** — `current_neighborhood_association.listings`
- [x] TASK-003: Corregir herencia de controllers admin a `Admin::ApplicationController` (L5). **FALSO POSITIVO** — verificado 2026-08-20: todos los controllers están dentro de `module Admin` y declaran `< ApplicationController`, que Ruby resuelve a `Admin::ApplicationController`. El hallazgo L5 nació de un grep textual por el nombre completo. No hay nada que corregir

### Prioridad 2 — Integridad de identidad (P3)
- [x] TASK-004: En `Admin::OnboardingReviewsController#approve_step3`, desactivar el `Member` activo anterior del mismo RUN antes de crear el nuevo. **HECHO 2026-07-25** vía `IdentityTransferService.deactivate_prior_memberships!` (ADR-0014), que usa `member.deactivate!(reason:)`. Cierra: BR-029, BR-034 (caso "se va a otra junta"), BR-057 (transferencia), BR-059, BR-069 y BR-099 (ruta onboarding). Tests en `onboarding_reviews_controller_test.rb` (deactivación + cascada)
- [x] TASK-018: Transición `household_admin` → dependiente (BR-095/096/097). **HECHO 2026-07-25** en `Admin::DependentReviewsController#approve` vía el mismo `IdentityTransferService` (ADR-0014): detecta el RUN duplicado y desactiva el `Member(household_admin)` anterior con `deactivate!` (cascada a dependientes por BR-096/099 + invalidación de certificados por BR-097). Sin flujo/UI nuevo. Tests en `dependent_reviews_controller_test.rb`

### Prioridad 3 — Robustez de pagos/emisión (H3, H4, M3)
- [x] TASK-005: `with_lock` en `IssueCertificateJob` para evitar doble emisión (H3). **HECHO** en Batch J — el lock quedó en el modelo, no en el job: `mark_as_paid!`, `apply_mp_payment_status!` e `issue!` corren dentro de `with_lock` (`residence_certificate.rb:121,137,172`), que recarga el registro antes de decidir. Ver BR-141
- [x] TASK-006: Validar `transaction_amount` del pago MP contra `certificate.amount` en el webhook (H4). **HECHO** — BR-090, `webhooks/mercadopago_controller.rb:233,303`
- [x] TASK-007: Eliminar race condition en generación de folio (M3) y borrar dead code `generate_folio!` (L7). **HECHO** — `generate_folio!` ya no existe en `app/`; la carrera la cubre el `with_lock` de TASK-005 (ver nota J7 en `reviews/`)

### Prioridad 4 — Operación producción (O1–O7)
> Todas bloqueadas por acceso al servidor, no por código.
- [ ] TASK-008: `kamal deploy` con fixes del webhook MP + confirmar webhook en panel MP + pago de prueba end-to-end
- [ ] TASK-009: Seeds en prod: `db:seed` (geografía) y `demo:seed` (junta demo)
- [ ] TASK-010: Prueba de humo Resend en producción
- [ ] TASK-011: Sandbox → producción en credenciales MP (tras validar flujo)
- [ ] TASK-019: **Verificar en producción si existió algún domicilio con más de un `FamilyGroup`** antes del fix de aislamiento (PR #159, BR-041). Requiere las llaves SSH del servidor —no estaban en el equipo donde salió el hallazgo—, así que quedó pendiente para correrlo desde la máquina que las tiene. Es una consulta de **solo lectura**:

  ```
  bin/kamal app exec -i -r web "bin/rails console"
  ```
  ```ruby
  multi = HouseholdUnit.joins(:family_groups)
    .group("household_units.id").having("COUNT(family_groups.id) > 1").count.keys
  puts "Domicilios con más de un núcleo familiar: #{multi.size}"
  multi.each do |hu_id|
    ResidenceCertificate.where(household_unit_id: hu_id).find_each do |c|
      fg = Residency.find_by(verified_identity_id: c.member.verified_identity_id,
        household_unit_id: hu_id, status: "approved")&.family_group_id
      puts "#{c.folio} | #{c.status} | titular: #{c.member.name} | núcleo ##{fg}"
    end
  end
  ```

  **Si el primer número es 0, el tema queda cerrado**: sin dos núcleos en una dirección, ninguna emisión pudo cruzarse. Es el resultado esperado (producción tiene ~20 socios en una junta, y hace falta que dos personas distintas completen onboarding en la misma dirección).

  **Límite conocido**: si da distinto de 0, el listado **no prueba** que hubo emisión cruzada. `ResidenceCertificate` no guarda quién solicitó —solo `member`, `household_unit` y `neighborhood_association`— y ambos jefes de hogar tienen cuenta, así que cada uno pudo pedir el suyo legítimamente. Habría que revisarlo caso por caso con contexto humano. Ver TASK-020.

### Prioridad 5 — Features faltantes (P1, P2, P4)
- [x] TASK-020: **Registrar quién solicita cada certificado**. **HECHO 2026-08-20** (PR #166, `7b72f5a`) tras aprobación del owner — nueva **BR-152**. `residence_certificates.requested_by_id` (FK a `users`, con índice) se puebla en `Panel::ResidenceCertificatesController#create` **desde la sesión, nunca desde el formulario**; la vista del admin lo muestra solo cuando el solicitante difiere del titular (`requested_by_other?`). La columna es **nullable a propósito**: los certificados anteriores no tienen solicitante registrable y no se les inventa uno — un backfill con el titular sería una afirmación falsa justo en los casos que interesa distinguir. **No cierra TASK-019 retroactivamente**: los certificados ya emitidos siguen sin ese dato
- [x] TASK-012: Disolución de juntas: campo `active`, `NeighborhoodAssociation#deactivate!` con cascada, UI superadmin, retirar destroy físico (BR-054/055). **HECHO 2026-07-26** — `neighborhood_association.rb` tiene la columna `active`, el scope `:active`, `deactivate!` transaccional con cascada y `Superadmin::NeighborhoodAssociationsController#confirm_deactivate`; no existe `destroy`
- [x] TASK-013: Duplicar solicitud de onboarding rechazada/cancelada. **HECHO 2026-08-20** (PR #164, `34b0e1b`). La nota decía "BR-047 ya OK" y **era falso**: el panel solo consulta `current_onboarding_request` (`draft|pending`), así que una solicitud rechazada desaparecía de la vista del usuario junto con su motivo. Sin poder verla no había desde dónde duplicarla, así que el PR implementa las dos: historial en `/panel/onboarding/history` y `OnboardingRequest#duplicate!` transaccional. **Los documentos no se copian** (decisión de producto) y no se hereda `terms_accepted_at` (BR-015)
- [x] TASK-014: Vista solo-lectura de otros `FamilyGroup` del mismo `HouseholdUnit` (BR-042). **HECHO 2026-08-20** (PR #165, `fb3bcf3`) en `Panel::HouseholdNeighboursController`. **Alcance decidido por el owner**: la vista muestra únicamente **recuentos** —cuántos núcleos y cuántas personas cada uno—, nunca nombres ni RUN, porque la redacción de BR-042 ("quiénes conviven") chocaba con BR-041. Mismo criterio del PR #159: gana el aislamiento

### Prioridad 6 — Documentación y calidad restante
- [x] TASK-015: Reconciliar texto de reglas superadas por el diseño actual en CLAUDE.md. **CERRADA 2026-08-20** con el PR #164: BR-026 describía un re-envío "cambiando el estado de vuelta a `pending`" que nunca existió y contradecía a BR-047; queda marcada como corregida, apuntando a la duplicación real (BR-048/049). Las otras tres ya estaban cerradas: BR-056 (2026-07-25), BR-072 (#106) y BR-021 (retirada en el PR #159, reemplazada por BR-150)
- [ ] TASK-016: Escribir ADRs faltantes para **MercadoPago, Resend, FamilyGroup, emisión automática y seeds de geografía**. Ninguno de los cinco existe en `doc/adr/` (hoy van 0001–0015). Nota: la transferencia de identidad por RUN duplicado, que este backlog llamaba "ADR-006", quedó numerada como **ADR-0014** al unificarse los ADRs en `doc/adr/` el 2026-08-02
- [ ] TASK-017: Resto de hallazgos de auditoría. **Parcialmente cerrada el 2026-08-20** (PR #163, `60e1b35`): por decisión de alcance del owner se remediaron solo los de impacto real.
  - **Hechos**: `masked_run` hacía `return raw` ante un RUN sin guión y publicaba el RUN **completo** en `/verify/:identifier`, que es pública y sin login — ahora falla cerrado (BR-078); y se eliminó `Admin::UsersController` con sus 11 vistas e i18n, código muerto que permitía `:email` y el toggle `:admin` en sus params (BR-093/BR-122). De paso, `User` gana el guard `email_is_immutable`, que saca a BR-093 de depender de que cada controller recuerde descartar el parámetro.
  - **Descartado como falso positivo**: el "posible doble cobro del primer mes" de las suscripciones. La auditoría asumía que un usuario podía suscribirse teniendo vigencia pagada, y `Listing#subscribable?` lo impide desde el 2026-07-22 (`payable?` = nunca pagada o vencida), con el guard en la vista, en `new` y en `create`. En el único escenario alcanzable el cobro inmediato es correcto: **agregar `start_date` habría regalado 30 días**.
  - **Sigue pendiente**: los 9 hallazgos restantes de las 12 Baja (normalización de direcciones —que es BR nueva y toca datos existentes—, RUN normalizado copiado en 4 sitios, `external_reference` malformado sin log, redacción de BR-136, TOCTOU de BR-134 sin índice único, `resolve_identity!` sin `IdentityTransferService`, estados `cancelled` y `generate_folio!` mal documentados, y los gaps de test) más la auditoría 2026-07-22 (H5, M1, M2, M6, M7, L1-L4, L6)
- [x] TASK-021: **`normalize_phone` tragaba teléfonos basura.** **HECHO 2026-08-20** (PR #162, `278e006`). La normalización solo reescribe el valor cuando reconoce una de las tres formas válidas; cualquier otra entrada se conserva tal como se escribió para que la validación la rechace. La lógica estaba **triplicada** en `VerifiedIdentity`, `IdentityVerificationRequest` y `AdministrationRequest` y pasó al concern `PhoneNormalization`. **Hallazgo de paso**: `AdministrationRequest` normalizaba el teléfono pero nunca validaba su formato pese a BR-127 — el propio defecto lo ocultaba, porque la basura quedaba vacía y fallaba por presencia

- [ ] TASK-022: **`admin/household_units/search.json.jbuilder` invoca `household_unit.name`, que no existe.** `HouseholdUnit` no tiene columna `name` ni método que la supla (verificado 2026-08-20: el modelo solo define `current_residencies`). Esa vista reventaría con `NoMethodError` al usarse. Detectado escribiendo la vista de TASK-014, que al principio cometía el mismo error. Fix probable: componer la dirección con `street_name`/`neighborhood_delegation` + `number`, como hace `panel/household_neighbours`
- [ ] TASK-023: **Flake no diagnosticado en el system test contra la imagen de producción.** Durante el CI del PR #166 ese paso falló una vez con 1 error y 55 asserts (lo normal son 75). No se capturó el detalle antes de reintentar y **no volvió a reproducirse** en tres corridas posteriores, incluida una ejecución aislada de `bin/system-tests-docker`. Queda sin causa conocida. El PR #157 ya advertía que las esperas de estos tests son el primer lugar donde mirar; si reaparece, capturar la salida completa **antes** de reintentar

## En Analisis

<!-- Tareas siendo analizadas por el Arquitecto -->

## Rechazado

<!-- Tareas que no se implementaran con la razon -->
