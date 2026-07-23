# Análisis de pendientes — BRs y ADRs

**Fecha**: 2026-07-22
**Fuentes**: CLAUDE.md (BR-001 a BR-081), `.claude/team/architecture/decisions.md` (ADR-001 a ADR-005), `docs/2026-07-21-code-audit.md`, verificación directa del código en esta fecha.

Este documento lista lo que está **pendiente**, no lo que ya funciona. Estado verificado contra el código real (no solo contra la documentación).

---

## 1. Reglas de negocio NO implementadas

### P1 · BR-054/BR-055 — Disolución de juntas (marcar como `inactive` con cascada)
**Estado: NO IMPLEMENTADO.**
- No existe columna `active` en `neighborhood_associations` (falta migración).
- `NeighborhoodAssociation` no tiene método `deactivate!` ni cascada de `Member` a `inactive`.
- `Superadmin::NeighborhoodAssociationsController#destroy` **borra físicamente** la junta, lo que contradice BR-054 (debe marcarse `inactive`, nunca destruirse con historial).

**Trabajo**: migración `active:boolean`, `NeighborhoodAssociation#deactivate!` transaccional con cascada de members, UI en superadmin, y probablemente bloquear/retirar el `destroy` físico.

### P2 · BR-047/BR-048/BR-049 — Duplicar solicitud de onboarding rechazada
**Estado: NO IMPLEMENTADO** (solo hay comentarios que la mencionan en `onboarding_request.rb:62` y `panel/onboarding_controller.rb:21`).
- Falta acción `duplicate` en `Panel::OnboardingController`.
- Falta método de copia en `OnboardingRequest` (nueva solicitud en `draft` con datos precargados, original intacta).
- Falta UI ("duplicar" desde el historial de solicitudes rechazadas/canceladas).

---

## 2. Reglas de negocio PARCIALMENTE implementadas

### P3 · BR-057–060 + BR-029 — RUN duplicado: falta desactivar el `Member` anterior al aprobar
**Estado: PARCIAL — riesgo de integridad.**
- La detección y alerta al admin sí existe (`Admin::OnboardingReviewsController#step3`, líneas 14-44).
- **Falta** en `approve_step3`: al aprobar un onboarding cuyo RUN ya tiene un `Member` activo (en la misma u otra junta), ese `Member` anterior debe pasar a `inactive` (BR-059, BR-029). Hoy se crea el nuevo `Member` **sin tocar el anterior** → un usuario puede quedar activo en dos juntas a la vez, violando BR-029.
- Nota: BR-031 (cambio de dirección) sí se cubre vía `restart` del onboarding, pero la aprobación no refuerza la invariante.
- Efecto colateral: la "graduación" de dependientes (BR-069) depende de este mecanismo, así que hoy tampoco funciona.

**Trabajo**: en la transacción de `approve_step3`, buscar members `approved` de la `VerifiedIdentity` existente y llamar `deactivate!` antes de crear el nuevo.

### P4 · BR-042 — Vista de solo-lectura de otros `FamilyGroup` del mismo domicilio
**Estado: PARCIAL.** La restricción de gestión (BR-041) existe, pero no hay ninguna vista en el panel que muestre a los otros `FamilyGroup` del `HouseholdUnit` en modo lectura.

### P5 · BR-021 — `household_admin: true` se asigna siempre, sin verificar si es el primero
`approve_step3` crea la `Residency` con `household_admin: true` incondicionalmente. Si se aprueba un segundo residente en un domicilio existente (nuevo `FamilyGroup` en el mismo `HouseholdUnit`, BR-043), también queda como admin de su grupo — correcto bajo el modelo FamilyGroup, pero la regla BR-021 tal como está redactada ("el primero sí, los siguientes no") quedó desalineada con BR-041. **Pendiente documental**: reescribir BR-021 en términos de FamilyGroup (o marcarla `[RETIRADA]`).

---

## 3. Inconsistencias entre CLAUDE.md y el código

### P6 · BR-072 relajada en código sin actualizar la regla
Los commits recientes (`7d031d2`, `5039682`, `735327f`) cambiaron la política del webhook MP: ahora **solo se rechaza con 401 si `x-signature` viene presente y es inválida**; los webhooks de Feed v2.0 sin firma se aceptan (la consulta a la API de MP actúa como validación secundaria). BR-072 sigue diciendo "webhooks sin firma válida son descartados con 401".
**Trabajo**: actualizar BR-072 en CLAUDE.md para reflejar la política real (y evaluar si se quiere endurecer con validación de secret query param u otra mitigación).

### P7 · CLAUDE.md dice que `FamilyGroup` está "Pendiente de implementar" (BR-056)
Falso: el modelo, la tabla y su creación en la aprobación de onboarding existen (`app/models/family_group.rb`, `db/schema.rb:91-94`, `admin/onboarding_reviews_controller.rb:122`). **Trabajo**: actualizar la sección del modelo de datos y BR-056 en CLAUDE.md.

---

## 4. Hallazgos de la auditoría 2026-07-21 aún sin corregir

Ningún commit posterior a la auditoría corrigió sus hallazgos (verificado 2026-07-22). Siguen abiertos los 19; los críticos:

| ID | Hallazgo | Nota |
|----|----------|------|
| H1 | Acciones `search` de 7 controllers admin sin scope multi-tenant (viola BR-007) | Crítico |
| H2 | `Admin::ListingsController` sin ningún scope multi-tenant | Crítico |
| H3 | Race condition en `IssueCertificateJob` (doble emisión) | Falta `with_lock` |
| H4 | Webhook MP no valida `transaction_amount` vs `certificate.amount` | Verificado: sigue sin validar |
| H5 | Verificación pública sin guard redundante de `issued?` en el controller | Defensa en profundidad |
| M1–M7 | N+1, `FamilyGroup#household_admin` nil-unsafe, race de folio, scope de `User#household_unit` por asociación, etc. | Ver auditoría |
| L1–L7 | Normalización duplicada, `allow_blank` contradictorio en `number` (contradice BR-020 — L6), herencia incorrecta de controllers admin (L5), dead code `generate_folio!` (L7), etc. | Ver auditoría |

**Orden recomendado** (de la propia auditoría): H1+H2+L5 → H3+M3 → H4 → H5 → M1+M6 → M2+L6 → resto.

---

## 5. Pendientes operativos (producción)

| # | Tarea | Fuente |
|---|-------|--------|
| O1 | `kamal deploy` con los últimos fixes del webhook MP (commits `3fc40f4`…`735327f` posteriores al último deploy conocido) | memoria MP |
| O2 | Confirmar webhook en el panel de MercadoPago → `https://yuntapp.cl/webhooks/mercadopago` y probar pago con tarjeta de test end-to-end | memoria MP |
| O3 | Pasar credenciales MP de sandbox → producción cuando se valide el flujo | memoria MP |
| O4 | Ejecutar en prod: `kamal app exec 'bin/rails db:seed'` (geografía de Chile, PR #87) | memoria seeds |
| O5 | Ejecutar en prod: `kamal app exec 'bin/rails demo:seed'` (junta demo, PR #88) y luego `demo:reset` al terminar las pruebas | memoria demo |
| O6 | Prueba de humo de correo (Resend) en producción: registrar usuario real o enviar desde consola | memoria Resend |
| O7 | Recordar re-firmar master tras cada squash merge (`bin/ci` en master) o el deploy se rechaza | memoria CI |

---

## 6. ADRs — estado y pendientes

Los 5 ADRs (Devise, Hotwire, SQLite3, Propshaft+Importmap, Kamal) están **Aceptados** y vigentes; ninguno tiene acciones bloqueantes. Pendientes menores:

- **ADR-001 (Devise)**: la dependencia sigue en rama `main` de GitHub (sin release estable). Pendiente de bajo riesgo: fijar a un release cuando exista uno compatible con Rails 8.1.
- **ADR-003 (SQLite3)**: la auditoría (M5) detectó índices únicos parciales no portables a PostgreSQL. Pendiente documental: anotar en el ADR que una eventual migración a PostgreSQL requiere revisar esos índices.
- **ADRs faltantes**: decisiones importantes tomadas después no tienen ADR: integración MercadoPago (Checkout Pro + webhook), emisión automática vía `IssueCertificateJob`, correo vía Resend (API HTTP por bloqueo SMTP de DigitalOcean), modelo `FamilyGroup`, seeds idempotentes de geografía. Pendiente: escribir ADR-006+ para dejar registro.

---

## 7. Priorización sugerida

1. **Seguridad multi-tenant** (H1, H2, L5) — fuga de datos entre juntas, viola BR-007.
2. **Integridad de identidad** (P3) — desactivar Member anterior en `approve_step3`; desbloquea BR-029/057-060/069.
3. **Robustez de pagos/emisión** (H3, H4, M3) — race conditions y validación de monto.
4. **Operación** (O1–O7) — go-live de MP, seeds y prueba de correo en producción.
5. **Features faltantes** (P1 disolución de juntas, P2 duplicar solicitud, P4 vista de FamilyGroups).
6. **Documentación** (P5, P6, P7, ADRs faltantes, resto de hallazgos M/L).
