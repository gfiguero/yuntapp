# Backlog

Este archivo contiene todas las tareas pendientes de implementar. El Arquitecto es responsable de priorizarlas y moverlas al sprint actual.

> **Saneado el 2026-08-20**: se verificó cada tarea contra el código en `master` (`093b84a`). Siete
> tareas estaban implementadas hace semanas sin marcarse. La evidencia de cada una queda anotada
> abajo para que no haya que volver a auditarlas.

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
- [ ] TASK-020: **Registrar quién solicita cada certificado** (`requested_by_id` en `residence_certificates`, poblado en `Panel::ResidenceCertificatesController#create`). Hoy el certificado solo guarda al **titular**, así que no hay forma de auditar quién lo pidió. Con BR-098 permitiendo solicitar a nombre de terceros, esa trazabilidad tiene valor propio: es lo que impidió responder TASK-019 de forma concluyente. Migración pequeña; el patrón ya existe en `members` e `identity_verification_requests`, que sí tienen `requested_by_id`. **Propuesta abierta, sin decisión del owner todavía**
- [x] TASK-012: Disolución de juntas: campo `active`, `NeighborhoodAssociation#deactivate!` con cascada, UI superadmin, retirar destroy físico (BR-054/055). **HECHO 2026-07-26** — `neighborhood_association.rb` tiene la columna `active`, el scope `:active`, `deactivate!` transaccional con cascada y `Superadmin::NeighborhoodAssociationsController#confirm_deactivate`; no existe `destroy`
- [ ] TASK-013: Duplicar solicitud de onboarding rechazada/cancelada — acción/ruta `duplicate` que clona OR/IVR/RVR a un nuevo `draft` (BR-048/BR-049; BR-047 ya OK). **Verificado 2026-08-20: sigue sin implementar** — no hay ruta ni acción `duplicate` en `config/routes.rb` ni en `panel/`
- [ ] TASK-014: Vista solo-lectura de otros `FamilyGroup` del mismo `HouseholdUnit` (BR-042). **Verificado 2026-08-20: sigue sin implementar** — no hay rutas de `family_group` en el panel

### Prioridad 6 — Documentación y calidad restante
- [ ] TASK-015: Reconciliar texto de reglas superadas por el diseño actual en CLAUDE.md. **Queda solo BR-026** (el re-envío real es vía duplicación BR-048/049, no cambiando el estado del rechazo — depende de TASK-013). Cerradas: BR-056 (2026-07-25), BR-072 (documenta la política real del 401 desde #106) y BR-021 (retirada en PR #159, reemplazada por BR-150)
- [ ] TASK-016: Escribir ADRs faltantes para **MercadoPago, Resend, FamilyGroup, emisión automática y seeds de geografía**. Ninguno de los cinco existe en `doc/adr/` (hoy van 0001–0015). Nota: la transferencia de identidad por RUN duplicado, que este backlog llamaba "ADR-006", quedó numerada como **ADR-0014** al unificarse los ADRs en `doc/adr/` el 2026-08-02
- [ ] TASK-017: Resto de hallazgos de auditoría. Son **dos lotes distintos**:
  - Auditoría 2026-07-22: H5, M1, M2, M6, M7, L1-L4, L6
  - Auditoría profunda 2026-07-30: las **12 severidades Baja** de `docs/2026-07-30-auditoria-profunda.md` (Alta = Batch I y Media = Batch J, ambos desplegados)
- [ ] TASK-021: **`VerifiedIdentity#normalize_phone` traga teléfonos basura.** `gsub(/[^0-9+]/, "")` deja `""` ante una entrada como `"no-es-un-telefono"`, y como la validación es `phone: true, if: -> { phone.present? }`, no llega a correr: el usuario cree que registró un teléfono y se guarda vacío. Detectado el 2026-08-02 escribiendo los tests de J4, fuera de la auditoría; **confirmado vigente el 2026-08-20** en `app/models/verified_identity.rb:19-25`

## En Analisis

<!-- Tareas siendo analizadas por el Arquitecto -->

## Rechazado

<!-- Tareas que no se implementaran con la razon -->
