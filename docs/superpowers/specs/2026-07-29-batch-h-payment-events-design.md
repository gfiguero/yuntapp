# Batch H — Idempotencia histórica de pagos vía `payment_events` (#101)

**Fecha:** 2026-07-29
**Origen:** auditoría de correctitud 2026-07-26, issue #101 (Media).
**Rama:** `worktree-fix-batch-h-payment-events`

## Problema

La idempotencia del webhook usa un único campo `payment_id` por payable. `renew_from_subscription!`
(`app/models/listing.rb`) **sobrescribe** ese `payment_id` en cada cobro recurrente, así que el listing
solo recuerda el último. `payment_already_processed?` (usado hoy SOLO en
`process_subscription_authorized_payment`) consulta `Listing.exists?(payment_id:)`; un reintento tardío
del webhook de un cobro anterior ya no encuentra su `payment_id` → se re-procesa → doble renovación
(+30 días de más). No hay historial de cobros recurrentes.

## Reconciliación crítica con Batch G

Batch G quitó el short-circuit por `payment_id` del flujo de **pago único** (cert/listing) precisamente
para que los refunds —que reusan el `payment_id` del `approved` original— se procesen (idempotencia por
ESTADO vía `payment_status`). Por lo tanto, la nueva idempotencia NO puede ser por `payment_id` a secas:
sería re-romper los refunds. **La clave de idempotencia es `(payment_id, status)`.** Un mismo `payment_id`
con `approved` y luego `refunded` son dos eventos distintos, ambos procesables.

## Cambios

### 1. Tabla `payment_events`
Migración: crear `payment_events` con
- `payment_id` (string, null: false)
- `status` (string, null: false) — estado crudo de MP
- `payable_type` / `payable_id` (referencia polimórfica → `ResidenceCertificate` | `Listing`, null: false)
- `amount` (integer) — monto del cobro (historial / reportes de comisión)
- `processed_at` (datetime, null: false)
- `timestamps`
- Índice único `[payment_id, status]` (garantía de idempotencia a nivel BD).
- Índice `[payable_type, payable_id]` (el `references ... polymorphic: true` lo crea).

Sin backfill (el historial arranca desde ahora).

### 2. Modelo `PaymentEvent`
`app/models/payment_event.rb`: `belongs_to :payable, polymorphic: true`; validaciones de presencia de
`payment_id`/`status`/`processed_at`; validación de unicidad `payment_id` scoped a `status` (espejo del
índice). `ResidenceCertificate` y `Listing`: `has_many :payment_events, as: :payable, dependent: :restrict_with_error`
(BR-100: el historial de pagos no se destruye).

### 3. Idempotencia por `(payment_id, status)` en el webhook
`payment_already_processed?(payment_id, status)` → `PaymentEvent.exists?(payment_id:, status:)`.
(Cambia la firma: ahora recibe `status`.) Helper `record_payment_event(payable, payment_id:, status:, amount:)`
que hace `find_or_create_by(payment_id:, status:)` seteando `payable`, `amount`, `processed_at` — idempotente
por el índice único.

### 4. Uso por flujo

- **Suscripción** (`process_subscription_authorized_payment`) — el bug de #101:
  - El gate `payment_already_processed?(payment_id)` (línea ~163) se mueve DENTRO de la rama `approved`
    (tras validar monto) como `payment_already_processed?(payment_id, "approved")`; si ya existe → no-op.
  - Tras `renew_from_subscription!`, llamar `record_payment_event(listing, payment_id:, status: "approved", amount:)`.
  - Resultado: un reintento tardío del mismo cobro encuentra su evento → no re-renueva. Cada cobro queda como historial.

- **Pago único** (`mark_certificate_paid` / `mark_listing_paid`, Batch G): conserva su idempotencia POR
  ESTADO (`payment_status`, sin cambios). Además, tras procesar (`approved` o vía `handle_non_approved`),
  registrar el evento con `record_payment_event(...)` como **log histórico**. NO usa `payment_already_processed?`
  (no re-introduce el short-circuit). El índice único `(payment_id, status)` hace el registro idempotente
  ante re-notificaciones.

### 5. `renew_from_subscription!` y el `payment_id` del Listing
La idempotencia ya no depende del `payment_id` del listing (vive en `payment_events`). El `payment_id`/`paid_at`
del listing quedan como snapshot del último cobro (UI). Se conserva la guarda barata
`return self if self.payment_id == payment_id` como cortocircuito, pero el gate real es la tabla.

## Reglas de negocio

No introduce reglas nuevas. Refina la implementación de **BR-071/BR-087** (idempotencia): la idempotencia
histórica vive en `payment_events` con clave `(payment_id, status)`. Se anota en BR-087 en CLAUDE.md.

## Testing

- Suscripción: (a) reintento tardío del mismo `payment_id`+approved NO re-renueva (no doble +30 días);
  (b) dos cobros distintos acumulan vigencia y quedan 2 eventos; (c) N cobros → N eventos (historial).
- Pago único: (a) un `refunded` tras el `approved` (mismo payment_id, distinto status) SÍ se procesa
  (no bloqueado) y quedan 2 eventos; (b) re-notificación del mismo (payment_id, status) no duplica evento.
- BD: índice único `(payment_id, status)` rechaza duplicados; `find_or_create_by` no levanta.
- Regresión: suite completa + `bin/ci`.

## Fuera de alcance

- Idempotencia universal (unificar el gate del pago único en `payment_events`) — se mantiene el gate por
  estado de Batch G para no re-romper refunds.
- Reportes/UI sobre `payment_events` (la tabla queda lista para consultarse, pero no se construye vista).
