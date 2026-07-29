# Batch G — Manejo completo de estados de pago de MercadoPago (#125 + #127)

**Fecha:** 2026-07-29
**Origen:** auditoría MercadoPago Checkout Pro 2026-07-29 (issues #125, #127).
**Rama:** `worktree-fix-batch-g-mp-payment-states`

## Problema

El webhook solo transiciona en `status == "approved"`; cualquier otro estado de pago de MP
(`in_process`, `pending`, `rejected`, `cancelled`, `refunded`, `charged_back`) cae en un `else`
silencioso (log `info`). Consecuencias:
- **#125**: un pago legítimo en revisión antifraude (`in_process`) nunca emite el certificado y no deja
  rastro en la UI del socio.
- **#127**: un contracargo (`charged_back`, iniciado por el banco del comprador días/semanas después,
  fuera de nuestro control) sobre un certificado ya emitido lo deja mostrándose **Válido** — documento
  oficial cuyo pago desapareció.

Además, un gap técnico central: `process_payment_notification` hace short-circuit por
`payment_already_processed?(payment_id)`. Un refund/chargeback llega con el **mismo `payment_id`** ya
registrado, así que hoy **nunca se procesaría**. La idempotencia debe pasar de "¿vi este payment_id?" a
"¿cambió el estado del pago?".

## Alcance de la protección (decisión de negocio, 2026-07-29)

Un chargeback llega cuando el certificado ya fue emitido y **casi con certeza ya descargado**. El PDF ya
descargado es un archivo estático fuera de nuestro control (depende de MP y la honestidad del usuario).
Lo que SÍ controlamos y protege el valor real del certificado:
- **Verificación pública** → "No válido" (lo que ve el tercero que recibe el certificado; el valor del
  certificado está en su verificabilidad en vivo, UC-007, no en el papel).
- **Descarga futura bloqueada** desde el panel.

## Cambios

### 1. Modelo de datos

Migración: agregar columna **`payment_status`** (string, nullable) a `residence_certificates` y
`listings`. Registra el estado **crudo del último pago** reportado por MP. Sin backfill (existentes = `nil`).
El `status`/`publication_status` de negocio (BR-064) **no cambia de enum**.

Valores posibles de `payment_status`: `approved`, `in_process`, `pending`, `rejected`, `cancelled`,
`refunded`, `charged_back` (los que envía MP). No se valida por inclusión estricta (MP podría agregar
estados); se registra tal cual.

### 2. Idempotencia por estado (rediseño del webhook)

En `Webhooks::MercadopagoController`:
- `process_payment_notification` deja de hacer short-circuit por `payment_already_processed?`. Siempre
  `fetch_payment` para obtener el estado actual real.
- Tras resolver el payable (por `external_reference`) y validar el monto (BR-090 intacto), comparar el
  `payment_status` guardado con el estado crudo entrante:
  - **igual** → no-op (idempotente; cubre re-notificaciones del mismo estado).
  - **distinto** → procesar la transición (sección 3) y persistir el nuevo `payment_status`.
- Se conserva el índice único de `payment_id` (no se duplican registros). BR-071 se reformula: no se
  reprocesa el **mismo estado** del mismo pago, pero sí se atiende un **cambio de estado**.
- Este rediseño aplica al flujo de **pago único** (`topic=payment`/`merchant_order` → cert/listing). El
  flujo de **suscripción** (`subscription_authorized_payment`) conserva su idempotencia por `payment_id`
  vía `payment_already_processed?`, porque cada cobro recurrente es un `payment_id` distinto (no una
  transición de estado del mismo pago) — no se toca.

### 3. Reacciones por estado

| Estado crudo MP | Certificado | Listing |
|---|---|---|
| `approved` | `mark_as_paid!` → `paid` → emite (actual, BR-062) | `mark_as_paid!` → `published` (actual) |
| `in_process`, `pending` | registrar `payment_status`; `status` sigue `pending_payment`; UI "en revisión". Esperar re-notificación de MP | registrar; sigue `pending_payment` |
| `rejected`, `cancelled` | registrar; sigue `pending_payment` (BR-003/073); el socio puede reintentar | registrar; sigue `pending_payment` |
| `refunded`, `charged_back` | si `paid` (no emitido) → volver a `pending_payment` (BR-073); si `issued` → **invalidar** (verificación pública "No válido" + descarga bloqueada) + **notificar al staff** | si `published` → **despublicar** (volver a `pending_payment`, `published_until` = nil) |

Persistir `payment_status` en todos los casos (incluido `approved`).

### 4. Verificación pública (nueva precedencia)

Agregar `ResidenceCertificate#payment_reverted?` → `%w[refunded charged_back].include?(payment_status)`.
En `app/views/verifications/show.html.erb`, la precedencia pasa a:
1. `payment_reverted?` **O** `holder_deactivated?` → "No válido" (revoked).
2. `expired?` → "Vencido".
3. válido.

Cumple BR-009/BR-080: responde 200 OK (no 404) también para revertidos/vencidos. El scope
`findable_publicly` (status `issued`) no cambia.

### 5. Descarga bloqueada (panel)

`ResidenceCertificate#downloadable?` pasa a
`issued? && !expired? && !holder_deactivated? && !payment_reverted?`. Un pago revertido bloquea la
re-descarga desde `panel/residence_certificates/:id/download`, consistente con BR-091/BR-092.

### 6. UI del socio

En `panel/residence_certificates/show`, cuando `payment_status ∈ {in_process, pending}` y el `status`
sigue `pending_payment`, mostrar un aviso "Pago en revisión" (i18n nuevo `en`/`es`). El resto de la UI
sigue guiándose por `status`.

### 7. Notificación al staff

Ante `refunded`/`charged_back` sobre un certificado (cualquier estado) o un listing published, además de
la reacción de estado: log `error` + **notificar a los superadmin** (`User.where(superadmin: true)`) por
mail. Nuevo mailer/acción, p. ej. `PaymentReversalMailer#staff_alert(staff, payable)` siguiendo el
patrón de `AdministrationRequestMailer#staff_digest`. `deliver_later`.

### 8. Regla de negocio nueva — BR-141

**BR-141 · Certificados · Pagos:** Un pago revertido por MercadoPago (`refunded`/`charged_back`, típicamente
un contracargo iniciado por el banco del comprador) invalida el certificado. Si el certificado ya fue
emitido, la verificación pública lo muestra **No válido** (precedencia sobre Vencido, junto con BR-091) y
la descarga desde el panel queda bloqueada; el PDF ya descargado queda fuera de nuestro alcance pero sin
valor de verificación. Si el certificado aún no fue emitido (`paid`), vuelve a `pending_payment` (BR-073).
Esta es la **primera vía de invalidación individual** de un certificado — matiza BR-008/BR-064/BR-097 (que
describen la no-revocación individual): la invalidación no reescribe el certificado (sigue `issued`,
inmutable), sino que deriva de `payment_status`. El staff es notificado para investigar posible fraude
(un chargeback puede ameritar desactivar al socio, BR-091, invalidando todos sus certificados).

Se agrega la fila a la tabla de reglas de CLAUDE.md.

### 9. Testing

- **Webhook**: (a) approved→charged_back sobre cert `issued` → `payment_status=charged_back`, invalida,
  notifica staff; (b) refund sobre cert `paid` → vuelve a `pending_payment`; (c) `in_process` → registra,
  no emite, status sigue `pending_payment`; (d) re-notificación del mismo estado → no-op (idempotente);
  (e) charged_back sobre listing `published` → despublica; (f) `rejected` → registra, sigue
  `pending_payment`.
- **Verificación pública**: cert emitido con `payment_status=charged_back` → "No válido" (200 OK).
- **Descarga**: cert revertido → `downloadable?` false; download bloqueado.
- **Modelo**: `payment_reverted?` para cada estado.
- **Regresión**: suite completa + `bin/ci`.

## Fuera de alcance

- Iniciar refunds desde la app (BR-063: no hay devoluciones).
- Recuperar PDFs ya descargados (imposible; depende de MP/usuario).
- Desactivación automática del socio ante chargeback (queda a criterio del staff, BR-091).
