# Backlog

Este archivo contiene todas las tareas pendientes de implementar. El Arquitecto es responsable de priorizarlas y moverlas al sprint actual.

## Pendiente

> Origen: análisis BR/ADR del 2026-07-22 — detalle completo en `docs/2026-07-22-pendientes-br-adr.md`. Retomar en el orden listado.

### Prioridad 1 — Seguridad multi-tenant (auditoría H1, H2, L5)
- [ ] TASK-001: Scopear por `current_neighborhood_association` las acciones `search` de 7 controllers admin (H1, viola BR-007)
- [ ] TASK-002: Agregar scope multi-tenant completo a `Admin::ListingsController` (H2)
- [ ] TASK-003: Corregir herencia de controllers admin a `Admin::ApplicationController` (L5)

### Prioridad 2 — Integridad de identidad (P3)
- [ ] TASK-004: En `Admin::OnboardingReviewsController#approve_step3`, desactivar el `Member` activo anterior del mismo RUN antes de crear el nuevo (BR-029/BR-059; desbloquea graduación de dependientes BR-069)

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
- [ ] TASK-013: Duplicar solicitud de onboarding rechazada/cancelada (BR-047-049)
- [ ] TASK-014: Vista solo-lectura de otros `FamilyGroup` del mismo `HouseholdUnit` (BR-042)

### Prioridad 6 — Documentación y calidad restante
- [ ] TASK-015: Actualizar CLAUDE.md: BR-056 (FamilyGroup ya existe), BR-072 (política real de firma webhook), BR-021 (redactar en términos de FamilyGroup)
- [ ] TASK-016: Escribir ADR-006+ para MercadoPago, Resend, FamilyGroup, emisión automática, seeds geografía
- [ ] TASK-017: Resto de hallazgos de auditoría (H5, M1, M2, M6, M7, L1-L4, L6)

## En Analisis

<!-- Tareas siendo analizadas por el Arquitecto -->

## Rechazado

<!-- Tareas que no se implementaran con la razon -->
