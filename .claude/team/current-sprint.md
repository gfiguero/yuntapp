# Sprint Actual

Este archivo contiene las tareas del sprint en curso. Solo el Arquitecto puede mover tareas desde el backlog.

## En Progreso

### Batch C — Issues Alta acotados (rama `worktree-fix-batch-c-issues-alta`)
Como [DESARROLLADOR]: 4 fixes de prioridad Alta de la auditoría de correctitud 2026-07-26.
- [x] #91 (BR-090) — validar `transaction_amount` en el webhook de suscripción MP antes de renovar
- [x] #92 (BR-075/076) — `IssueCertificateJob` re-adjunta el PDF si quedó `issued` sin él (guard `issued? && pdf attached?`)
- [x] #93 (BR-019/020) — `ResidenceVerificationRequest`: quitar `allow_blank`, validar desde `pending` (excluir draft)
- [ ] #115 (BR-007) — controllers top-level (categories/tags/listings/neighborhood_associations) a solo lectura (index/show/search)

Fuera de batch (Batch D, requieren brainstorm de diseño): #94, #97.

## En Review

<!-- Tareas con PR abierto esperando revision -->

## Completado

<!-- Tareas completadas en este sprint -->
