# Backlog

Este archivo contiene todas las tareas pendientes de implementar. El Arquitecto es responsable de priorizarlas y moverlas al sprint actual.

## Pendiente

> Origen: análisis BR/ADR del 2026-07-22 — detalle completo en `docs/2026-07-22-pendientes-br-adr.md`. Retomar en el orden listado.
>
> **Auditoría completa de las 99 reglas: `docs/2026-07-25-br-audit.md`** (2026-07-25). 82/99 OK. Los 17 hallazgos restantes ya están cubiertos por las tareas de abajo (mapeo BR→tarea en el informe). El grueso de los gaps de identidad se cierra con un único patrón: invocar `Member#deactivate!` sobre el `Member` anterior al detectar RUN duplicado (ver ADR-006, TASK-004, TASK-018).

### Prioridad 1 — Seguridad multi-tenant (auditoría H1, H2, L5)
- [ ] TASK-001: Scopear por `current_neighborhood_association` las acciones `search` de 7 controllers admin (H1, viola BR-007)
- [ ] TASK-002: Agregar scope multi-tenant completo a `Admin::ListingsController` (H2)
- [ ] TASK-003: Corregir herencia de controllers admin a `Admin::ApplicationController` (L5)

### Prioridad 2 — Integridad de identidad (P3)
- [x] TASK-004: En `Admin::OnboardingReviewsController#approve_step3`, desactivar el `Member` activo anterior del mismo RUN antes de crear el nuevo. **HECHO 2026-07-25** vía `IdentityTransferService.deactivate_prior_memberships!` (ADR-006), que usa `member.deactivate!(reason:)`. Cierra: BR-029, BR-034 (caso "se va a otra junta"), BR-057 (transferencia), BR-059, BR-069 y BR-099 (ruta onboarding). Tests en `onboarding_reviews_controller_test.rb` (deactivación + cascada)
- [x] TASK-018: Transición `household_admin` → dependiente (BR-095/096/097). **HECHO 2026-07-25** en `Admin::DependentReviewsController#approve` vía el mismo `IdentityTransferService` (ADR-006): detecta el RUN duplicado y desactiva el `Member(household_admin)` anterior con `deactivate!` (cascada a dependientes por BR-096/099 + invalidación de certificados por BR-097). Sin flujo/UI nuevo. Tests en `dependent_reviews_controller_test.rb`

### Prioridad 3 — Robustez de pagos/emisión (H3, H4, M3)
- [ ] TASK-005: `with_lock` en `IssueCertificateJob` para evitar doble emisión (H3)
- [ ] TASK-006: Validar `transaction_amount` del pago MP contra `certificate.amount` en el webhook (H4)
- [ ] TASK-007: Eliminar race condition en generación de folio (M3) y borrar dead code `generate_folio!` (L7)

### Prioridad 4 — Operación producción (O1–O7)
- [ ] TASK-008: `kamal deploy` con fixes del webhook MP + confirmar webhook en panel MP + pago de prueba end-to-end
- [ ] TASK-009: Seeds en prod: `db:seed` (geografía) y `demo:seed` (junta demo)
- [ ] TASK-010: Prueba de humo Resend en producción
- [ ] TASK-011: Sandbox → producción en credenciales MP (tras validar flujo)

### Prioridad 5 — Features faltantes (P1, P2, P4)
- [ ] TASK-012: Disolución de juntas: campo `active`, `NeighborhoodAssociation#deactivate!` con cascada, UI superadmin, retirar destroy físico (BR-054/055)
- [ ] TASK-013: Duplicar solicitud de onboarding rechazada/cancelada — acción/ruta `duplicate` que clona OR/IVR/RVR a un nuevo `draft` (BR-048/BR-049; BR-047 ya OK)
- [ ] TASK-014: Vista solo-lectura de otros `FamilyGroup` del mismo `HouseholdUnit` (BR-042)

### Prioridad 6 — Documentación y calidad restante
- [ ] TASK-015: Reconciliar texto de reglas superadas por el diseño actual en CLAUDE.md: BR-021 (redactar en términos de FamilyGroup: "primero vs. siguientes" ya no aplica), BR-026 (el re-envío real es vía duplicación BR-048/049, no cambiando el estado del rechazo), BR-072 (documentar la política real: los webhooks MP sin `x-signature` se procesan apoyándose en la re-consulta a la API, no se descartan con 401). BR-056 ya corregido en esta sesión (2026-07-25)
- [ ] TASK-016: Escribir ADR-007+ para MercadoPago, Resend, FamilyGroup, emisión automática, seeds geografía (ADR-006 ya usado 2026-07-25: servicio compartido de transferencia de identidad por RUN duplicado)
- [ ] TASK-017: Resto de hallazgos de auditoría (H5, M1, M2, M6, M7, L1-L4, L6)

## En Analisis

<!-- Tareas siendo analizadas por el Arquitecto -->

## Rechazado

<!-- Tareas que no se implementaran con la razon -->
