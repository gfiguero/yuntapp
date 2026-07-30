# Auditoría de la integración MercadoPago Checkout Pro — 2026-07-29

Comparación de nuestra implementación contra la documentación oficial de MercadoPago
(colección Postman oficial "Mercado Pago Developers" + docs de developers.mercadopago.com).
Usamos **Checkout Pro** (preferences + pago hosteado por MP + webhook).

## Lo que hacemos bien (confirmado contra la doc)

- **Re-consulta a la API en vez de confiar en el payload del webhook**: el webhook solo trae
  `data.id`; consultamos el estado real con `fetch_payment`/`fetch_merchant_order`. Patrón recomendado
  por MP. (`webhooks/mercadopago_controller.rb`)
- **Reconciliación vía merchant_order**: manejamos `topic=merchant_order`/`topic_merchant_order_wh` e
  iteramos `order["payments"]`.
- **Firma HMAC `x-signature`**: nuestro manifest `id:{data_id};request-id:{request_id};ts:{ts};`
  coincide EXACTAMENTE con la fórmula oficial (confirmado contra el SDK PHP `buildManifest()`), incluido
  el `;` final y la omisión de `request-id` cuando falta. `secure_compare` en tiempo constante. (BR-072)
- **Idempotencia por `payment_id`** compartida cert/listing + índice único (BR-071/BR-087).
- **Validación de monto** exacta con `to_d` antes de marcar pagado (BR-090).
- **Códigos HTTP del webhook**: 200 en no-op determinista, 500 solo en fallo transitorio (Batch E, #100).
- **Topics de suscripción**: `subscription_preapproval` + `subscription_authorized_payment`.

## Requisitos oficiales de referencia

- **Estados de payment** (`/v1/payments`): `pending`, `approved` (terminal, acredita), `authorized`,
  `in_process` (revisión antifraude — NO acreditar), `in_mediation`, `rejected` (terminal),
  `cancelled` (terminal), `refunded` (terminal), `charged_back` (terminal — contracargo del banco, no lo
  controlamos). MP **re-notifica** cuando el pago cambia de estado.
- **Webhook**: responder 200/201 en ≤22s; si no, MP reintenta cada 15 min. El body no trae el estado,
  solo `data.id`; hay que hacer GET al recurso.
- **`X-Idempotency-Key`**: header soportado en operaciones de escritura. El SDK Ruby genera uno
  **aleatorio (UUID) por request** (`request_options.rb`), así que NO da idempotencia entre reintentos
  salvo que pasemos una clave estable propia.
- Doc oficial recomienda **rechazar notificaciones sin firma con 401** (nosotros procesamos sin firma
  apoyándonos en la re-consulta a la API — decisión consciente, ya registrada como issue #106).

## Hallazgos (priorizados)

### ALTA

- **P1 · Pagos en revisión (`in_process`/`pending`) sin manejo.** El webhook solo transiciona en
  `status == "approved"`; cualquier otro estado cae en no-op silencioso. Un pago legítimo en revisión
  antifraude nunca emite el certificado y no deja rastro en la UI. **DECISIÓN 2026-07-29: manejar
  `pending`/`in_process` explícitamente** (no `binary_mode`, para no perder pagos legítimos). Implica un
  estado local nuevo (p. ej. `payment_in_review`) o un flag, mostrarlo en la UI del socio, y esperar la
  re-notificación de MP (approved→emite / rejected→libera). Requiere brainstorm de diseño.
  `MercadopagoService#create_preference`/`#create_listing_preference` + `webhooks/mercadopago_controller.rb`
  + modelos + UI.

- **P2 · Estados `in_process`/`pending` sin manejo explícito.** Complemento de P1. Como mínimo subir el
  log del `else` de `info` a `warn` para visibilidad de pagos atascados. `#mark_certificate_paid`/`#mark_listing_paid`.

- **P3 · Idempotencia de escritura: `x-idempotency-key` aleatorio por request → doble click crea
  preferences y preapprovals DUPLICADOS.** Riesgo de dinero en **suscripciones**: un doble submit en
  `ListingSubscriptionsController#new` crea dos preapprovals; guardamos solo el segundo `preapproval_id`
  y el primero podría quedar **cobrando mensualmente** sin registro ni forma de cancelarlo. **Fix:** pasar
  `Mercadopago::RequestOptions` con `x-idempotency-key` estable derivada del recurso
  (`"preapproval-listing-#{id}"`, `"pref-cert-#{id}"`), y/o reutilizar preapproval `pending` existente.
  `mercadopago_service.rb` (create_preference/create_listing_preference/create_listing_subscription).

### MEDIA

- **P4 · Notificaciones `refunded`/`charged_back`/`cancelled` sin manejar → certificado emitido sigue
  "Válido" tras un contracargo.** BR-063 dice "no hay devoluciones", pero un `charged_back` lo inicia el
  banco del comprador y MP lo notifica igual; hoy cae en no-op silencioso. Riesgo dinero/legal: documento
  oficial con pago revertido sigue válido. **Fix:** para cert `paid` (no emitido) revertir a
  `pending_payment` (BR-073); para cert `issued` no reescribir (BR-008) pero **alertar al staff** (log
  `error` + notificación) y evaluar una BR de invalidación análoga a BR-091. Para listings `published`,
  evaluar despublicar. Documentar como BR nueva.

- **P5 · `statement_descriptor` ausente → cargo genérico en el resumen de tarjeta → contracargos por
  desconocimiento.** `statement_descriptor: "YUNTAPP"` en ambas preferences.

- **P6 · `payer` no prellenado → peor conversión y menos señales antifraude.** Tenemos email
  (`current_user`), nombre/RUN/teléfono (`certificate.member.verified_identity`). El RUN mapea a
  `identification {type: "RUT", number: ...}`. Ojo BR-098: el email de contacto es el del `household_admin`,
  no el del dependiente titular.

- **P7 · Preferences sin expiración (`expires`/`expiration_date_to`) → links de pago "eternos".** El
  precio es snapshot (BR-070/084); una preference que caduca es defensa en profundidad contra pagos
  obsoletos (el escenario de BR-090). `expires: true, expiration_date_to: 24.hours.from_now.iso8601(3)`.

- **P8 · (Operacional) Verificar en el panel de MP que el webhook está registrado para los 4 topics:**
  `payment`, `merchant_order`, `subscription_preapproval`, `subscription_authorized_payment`.

### BAJA

- **P9 · `items[].category_id`/`description` ausentes** (afinan antifraude y claridad del checkout):
  `category_id: "services"` para certificados, la categoría del marketplace para listings.
- **P10 · `payment_methods.installments` no configurado** → para micropagos, `installments: 1`.
- **P11 · Firma sin `x-signature` se procesa (no 401).** Ya registrado como issue #106 (Baja/Seguridad);
  la doc oficial recomienda 401. Nuestra postura (re-consulta a la API) es defendible pero divergente.

## Secuenciación sugerida

1. **P3 (suscripciones)** + **P1/P2 (binary_mode o manejo de pending)** — riesgos de dinero/robustez.
2. **P4** — al menos alertar ante refund/chargeback (hoy silencioso).
3. **P5 + P6 + P7** — un PR sobre `create_preference`/`create_listing_preference`.
4. **P8** — verificación operacional.
5. **P9/P10** — pulido de conversión/antifraude.
