# Auditoría pre-go-live — El flujo del dinero, end-to-end

**Fecha:** 2026-08-21 · **Repo:** `/home/gfiguero/Proyectos/RubymineProjects/yuntapp` · **Rama:** `master` · **Commit:** `259e22c`
**Alcance:** credenciales MercadoPago, webhook (firma / idempotencia / monto / reversiones), comisión del 10%, suscripciones de publicaciones, emisión post-pago, estados crudos de MP.
**Modo:** solo lectura. Producción consultada vía `rails runner` de solo lectura sobre `143.198.120.175`.

**Documentos previos leídos** (no repito lo ya remediado): `docs/2026-07-29-mercadopago-checkout-pro-audit.md`, `docs/2026-07-30-auditoria-profunda.md` (anexo de Pagos MercadoPago).

**Resumen:** 1 Crítica · 8 Altas · 4 Medias · 4 Bajas.

> **Titular:** el `access_token` cargado en producción **no es una cuenta real de MercadoPago**: pertenece a un *test user* del sandbox (`nickname: TESTUSER1844981119760716579`, `tags: ["test_user"]`). Verificado contra `GET /users/me` con el token de producción. Nadie puede cobrar un peso real hoy. Todo lo demás es secundario a esto.

---

## Estado de los hallazgos previos (para no re-descubrir)

Verificados como **ya remediados** en el código actual, no los repito abajo:

- Firma HMAC obligatoria con secret configurado, 401 si falta (BR-072, #106) — `webhooks/mercadopago_controller.rb:32-40`.
- Idempotencia histórica por `(payment_id, status)` en `payment_events` con índice único (BR-087, #101) — `db/schema.rb`, `payment_event.rb:206`.
- Guarda anti-resurrección de pago revertido (`reverted_payment?`, BR-146) — `mercadopago_controller.rb:270-275`, con 3 tests dedicados.
- Snapshot del monto de suscripción en `listings.subscription_amount` (BR-145) — `mercadopago_controller.rb:232`, `listing.rb:137`.
- Re-cálculo del `platform_fee` en `renew_from_subscription!` (BR-149) — `listing.rb:141-164`.
- `with_lock` en las tres transiciones del certificado (BR-141) — `residence_certificate.rb:139/155/189`.
- `statement_descriptor`, `expires`/`expiration_date_to`, `payer` pre-llenado, `category_id`, `installments: 1`, `x-idempotency-key` estable (P3/P5/P6/P7/P9/P10 del audit del 29-07) — `mercadopago_service.rb:31-119`.
- Manejo de `in_process`/`pending` con aviso en el panel (P1/P2) — `panel/residence_certificates/show.html.erb:86`.
- Página `success` que ya no miente (muestra "procesando" si sigue `pending_payment`) — `panel/payments/success.html.erb:4-5`.
- Cancelación de suscripción idempotente ante error de MP (BR-088) — `listing_subscriptions_controller.rb:294-303`.
- Aviso al staff cuando `IssueCertificateJob` se rinde (BR-148) — `issue_certificate_job.rb:10-24`.
- Descarga del PDF autorizada en cada request con `send_data` (BR-147) — `panel/residence_certificates_controller.rb:32-43`.
- Guard `before_destroy` en `Listing` (BR-144) — `listing.rb:43,170-175`.
- Posible doble cobro del primer mes de suscripción (falta de `start_date`, hallazgo Baja del 30-07): **neutralizado de hecho** por `Listing#subscribable?`, que exige `payable?` (nunca pagada o vencida). Un listing vigente no puede suscribirse, así que el cobro inmediato de MP al autorizar nunca se superpone con una vigencia ya comprada.

Hallazgos previos que **siguen vigentes** y reaparecen abajo con su severidad actualizada: el `amount` mutable del listing como gate de BR-090 en el **pago único** (arreglado solo para la suscripción), y la ausencia de monitoreo/conciliación.

---

## Hallazgos

### [SEVERIDAD: Crítica] El access_token de producción pertenece a un usuario de prueba de MercadoPago: ningún cobro real es posible
- **Archivo:** `config/credentials.yml.enc` (clave `mercadopago.access_token`), consumida por `config/initializers/mercadopago.rb:214`
- **Regla:** BR-004 / BR-005 / BR-083 (todo el flujo de dinero)
- **Qué está mal:** El token tiene prefijo `APP_USR-` (no `TEST-`), lo que a primera vista parece producción. Pero `APP_USR-` es también el prefijo del token de producción **de una cuenta de prueba** creada con `/users/test_user`. Consultando la identidad real de la cuenta, el token resuelve a:
  ```
  id: 3554371693
  nickname: TESTUSER1844981119760716579
  email: test_user_1844981119760716579@testuser.com
  first_name: "Test"  last_name: "Test"
  site_id: MLC
  tags: ["user_product_seller", "test_user", "normal"]
  confirmed_email: false
  ```
  El tag `test_user` es concluyente. Todos los `init_point` generados apuntan al sandbox de esa cuenta ficticia; ningún medio de pago real la acepta, y ningún peso llegaría a una cuenta bancaria de Yuntapp. El `webhook_secret` (64 chars) está configurado y por BR-072 la firma es obligatoria — con lo cual, además, los webhooks que llegaran de una cuenta real **serían rechazados con 401** porque el secret está pareado a la cuenta de prueba.
- **Cómo lo verifiqué:**
  1. `Rails.application.config.mercadopago[:access_token]` en el contenedor de producción → `TOKEN_PREFIX=APP_USR-`, `TOKEN_LEN=75`, `IS_TEST=false` (no empieza con `TEST-`), `SECRET_PRESENT=true`, `SECRET_LEN=64`.
  2. `GET https://api.mercadopago.com/users/me` con ese mismo token desde el contenedor de producción → `200` y el JSON de arriba.
  3. `env | grep MERCADOPAGO` en el contenedor → vacío, así que el valor viene de `credentials.yml.enc`, no de una variable de entorno; localmente `bin/rails runner` sobre `Rails.application.credentials.mercadopago` devuelve el mismo prefijo `APP_USR-81`, confirmando que dev y prod comparten la credencial.
- **Impacto en go-live:** **Bloquea absolutamente.** Abrir al público hoy significa que cada vecino que intente pagar llega a un checkout de sandbox; los que "paguen" con tarjetas de prueba generarían certificados oficiales gratis, y ningún ingreso real ni comisión existiría. Es el único hallazgo que por sí solo impide operar.
- **Fix sugerido:** Crear/usar las credenciales de la cuenta **real** de MercadoPago de Yuntapp (Chile / MLC), regenerar el `webhook_secret` **de esa cuenta** en el panel de MP, y cargarlas en un `config/credentials/production.yml.enc` separado (ver hallazgo de credenciales compartidas). Antes de abrir, validar con un cobro real de $1.000 end-to-end: preference → pago → webhook firmado → `paid` → `issued` → PDF descargable → dinero visible en el balance de MP.

---

### [SEVERIDAD: Alta] Un error HTTP de la API de MercadoPago es indistinguible de "no hay nada que hacer": el webhook responde 200 y el pago se pierde para siempre
- **Archivo:** `app/services/mercadopago_service.rb:144-156` (`fetch_payment`/`fetch_merchant_order`/`fetch_preapproval`/`fetch_authorized_payment`) y `app/controllers/webhooks/mercadopago_controller.rb:105-109, 292-310`
- **Regla:** BR-071 / BR-002 ("no avanzar sin confirmación de MP") — el vacío es de **manejo de fallo**, no hay regla que lo cubra: **falta regla**
- **Qué está mal:** El SDK de MercadoPago **no levanta excepción ante status HTTP de error**. `HttpClient#build_result` devuelve `{status: code, response: body_parseado}` para cualquier código, y `MPResponse` (subclase de `Hash`) expone `status_code`/`success?` que nuestro wrapper **descarta**: `fetch_payment` retorna `response[:response]` a secas. Ante un 401 (token revocado/rotado), 403, 404, o un 5xx que sobreviva a los 3 reintentos internos del SDK, lo que vuelve es un Hash de error, p. ej.:
  ```ruby
  {"message" => "Must provide your access_token to proceed", "error" => "unauthorized", "status" => 401, "cause" => [...]}
  ```
  El controller hace `return unless payment.is_a?(Hash)` — y un Hash de error **es** un Hash. Sigue a `mark_payable_paid`, encuentra `external_reference` en blanco, loguea un `warn` y responde **200 OK**. MercadoPago interpreta 200 como "procesado" y **nunca reintenta**. El pago aprobado del vecino queda sin registrar, el certificado sigue en `pending_payment`, y no hay ninguna alerta.
  El caso de token expirado/rotado es el peor: **todos** los webhooks devuelven 401, **todos** se responden 200, y se pierde el 100% de los pagos de la ventana sin que nadie se entere. `process_merchant_order` tiene la misma forma (`order["payments"] || []` sobre un Hash de error → cero pagos → 200) y `process_subscription_authorized_payment` también (payment `{}` → `payment_id` en blanco → 200).
  Los tests confunden el caso: `test "still returns 200 for a deterministic no-op (payment not found)"` (`test/controllers/webhooks/mercadopago_controller_test.rb:756`) stubea `fetch_payment` con `nil`, que **no es** lo que devuelve el SDK real ante un 404.
- **Cómo lo verifiqué:**
  1. Leí `mercadopago-sdk-3.4.0/lib/mercadopago/http/http_client.rb:79-87` (`build_result` no discrimina el status) y `lib/mercadopago/core/mp_base.rb:78-92` (`_get` envuelve en `MPResponse` sin verificar), más `lib/mercadopago/errors/response.rb:12-29` (`MPResponse < Hash` con `success?` que nadie llama).
  2. Ejecuté en local: `MercadopagoService.new(access_token: "APP_USR-bogus-token-for-audit").fetch_payment("1234567890")` → llamada HTTP real a MP → `class=Hash`, `is_hash=true`, cuerpo el 401 citado arriba. **No levantó excepción.**
  3. Seguí la traza en el controller: `process_payment_notification:107` (`is_a?(Hash)` → true) → `mark_payable_paid:295-301` (`external_reference` en blanco → `Rails.logger.warn` → `return`) → `create:58` (`head :ok`).
- **Impacto en go-live:** **Bloquea.** Es la forma más probable de perder plata de un vecino real sin que nadie lo note: MP no reintenta, no hay alerta, y el vecino queda pagado-sin-certificado con BR-063 prohibiendo la devolución. El riesgo escala con la rotación de credenciales (que hay que hacer sí o sí para el hallazgo Crítico).
- **Fix sugerido:** Que `MercadopagoService` chequee el status: devolver el cuerpo solo si `2xx`; ante `5xx`, `429` o `401/403` levantar una excepción propia (`MercadopagoService::ApiError`) que caiga en el `rescue => e` genérico del controller y responda **500**, para que MP reintente. Un `404` genuino sí puede seguir siendo no-op determinista con 200, pero debe distinguirse explícitamente por status, no por la forma del Hash. Agregar el test con el Hash de error real, no con `nil`.

---

### [SEVERIDAD: Alta] El botón "Pagar" sigue visible con un pago en revisión y el segundo cobro se traga en silencio: doble cobro real, sin detección ni devolución
- **Archivo:** `app/views/panel/residence_certificates/show.html.erb:78-90`; `app/controllers/panel/payments_controller.rb:74-78` (`ensure_pending_payment!`); `app/controllers/webhooks/mercadopago_controller.rb:62-70`; `app/models/residence_certificate.rb:143-145`
- **Regla:** BR-003 / BR-061 / BR-063 (no hay devoluciones) — **falta regla** que cubra el pago duplicado
- **Qué está mal:** Cuando un pago queda en revisión antifraude, el webhook registra `payment_status = "in_process"` y el certificado permanece en `pending_payment` (correcto). La vista muestra entonces, **en este orden**: primero el botón grande "Pagar con MercadoPago" (línea 78, cuya única condición es `pending_payment? && amount.present?`), y recién debajo el aviso "tu pago está en revisión" (línea 86). `PaymentsController#new` tampoco discrimina: `ensure_pending_payment!` solo mira `status`, no `payment_status`. Un vecino impaciente hace clic y **paga por segunda vez**.
  Si el segundo pago se aprueba, el webhook llama `mark_as_paid!`, que levanta `AlreadyPaidError` (`residence_certificate.rb:143-145`). Esa excepción está en el `rescue` de "no-op determinista" del controller: se loguea un `warn` y se responde 200. **No hay alerta a nadie, no hay registro de que hubo un cobro duplicado, no hay flujo de devolución** — y BR-063 dice explícitamente que no hay devoluciones. El vecino pagó dos veces por un certificado y el sistema no lo sabe.
- **Cómo lo verifiqué:** Leí la vista completa (`sed -n '70,105p'`) y confirmé que el bloque del botón de pago está **antes** y sin excluir `in_process`/`pending`. Leí `ensure_pending_payment!` (solo consulta `@certificate.pending_payment?`). Leí el `rescue` del controller (líneas 62-70) y el test que lo formaliza: `test "returns 200 (not 500) when a second payment_id hits an already-paid certificate"` (línea 766) — el test verifica que el `payment_id` original no cambie, pero no que se registre ni notifique nada.
- **Impacto en go-live:** **Bloquea.** No es un escenario teórico: la UI invita al doble pago y el backend lo absorbe sin dejar rastro accionable. Con vecinos reales esto se traduce en reclamos que Yuntapp no puede ni siquiera detectar sin auditar la cuenta de MP a mano.
- **Fix sugerido:** (a) Ocultar/deshabilitar el botón de pago mientras `payment_status` sea `in_process`/`pending`, y bloquear también `PaymentsController#new` con el mismo criterio. (b) Ante `AlreadyPaidError`, registrar un `PaymentEvent` de pago duplicado y notificar al staff (mismo canal que `PaymentReversalMailer`), para que exista un procedimiento de devolución manual. (c) Documentar la regla: "un pago duplicado sobre el mismo certificado se registra y se devuelve manualmente; es la excepción a BR-063".

---

### [SEVERIDAD: Alta] Una reversión se aplica sin verificar que el `payment_id` sea el del pago del recurso: un contracargo de un pago duplicado invalida un certificado legítimamente pagado
- **Archivo:** `app/controllers/webhooks/mercadopago_controller.rb:367-388` (`handle_non_approved`), invocado desde `:334` y `:360`
- **Regla:** BR-141 / BR-146 / BR-091 / BR-008
- **Qué está mal:** `mark_certificate_paid`/`mark_listing_paid` resuelven el recurso por el `external_reference` **del pago**, y para cualquier estado no-`approved` delegan en `handle_non_approved(payable, status, payment_id, amount)`. Ese método **nunca compara `payment_id` con `payable.payment_id`**: aplica el estado crudo de MP al recurso venga del pago que venga. Como un mismo `external_reference` puede acumular varios `payment_id` (intento rechazado + reintento, o el doble cobro del hallazgo anterior), la consecuencia es directa:
  - Certificado pagado y emitido con el pago **A**. Existe un pago **B** duplicado sobre el mismo `external_reference`. El vecino reclama y MP reembolsa **B**.
  - Llega `topic=payment` con **B** en `refunded` → `handle_non_approved(cert, "refunded", B)` → `apply_mp_payment_status!("refunded")` → como el cert está `issued` (no `paid`), se escribe `payment_status = "refunded"`.
  - A partir de ahí `payment_reverted?` es `true`: `downloadable?` pasa a `false` (BR-141) y la verificación pública muestra **No válido** con precedencia sobre Vencido. **El certificado se invalida por la reversión del pago equivocado**, siendo que el pago A nunca se revirtió.
  Efecto simétrico más leve: una notificación tardía de un intento `rejected`/`cancelled` anterior sobreescribe el `payment_status = "approved"` de un certificado sano, dejando la columna cruda mintiendo. Y hay una inconsistencia adicional: `record_payment_event` solo corre `unless changed` es falso, así que si el estado ya era `refunded` por otro pago, la reversión del segundo **no queda registrada** en `payment_events` y la guarda `reverted_payment?` (BR-146) no la protege.
- **Cómo lo verifiqué:** Lectura línea a línea de `handle_non_approved` (367-388) — no hay ninguna referencia a `payable.payment_id`, ni en el llamador (`:319-335`, `:345-362`). Contrastado con `mark_as_paid!` (`residence_certificate.rb:139-150`), que **sí** compara `self.payment_id == payment_id` para la ruta de aprobación: la asimetría es evidente. Los tests de reversión (`:678`, `:698`, `:725`) todos usan el mismo `payment_id` que pagó el certificado, así que el caso no está cubierto.
- **Impacto en go-live:** **Bloquea si se abre el marketplace o si se acepta el riesgo de doble cobro.** Invalida un documento oficial que el vecino pagó y descargó, sin acción de nadie. Es la contracara del hallazgo de doble cobro y se agrava con él.
- **Fix sugerido:** En `handle_non_approved`, aplicar la reacción de negocio (revertir estado, despublicar, alertar) **solo** si `payment_id == payable.payment_id`; para cualquier otro `payment_id` registrar el `PaymentEvent` histórico y loguear, sin tocar `payment_status` del recurso. Y mover `record_payment_event` fuera del `unless changed`, para que el historial sea completo por pago aunque el estado agregado no cambie.

---

### [SEVERIDAD: Alta] No existe ninguna conciliación con MercadoPago: si un webhook se pierde, el dinero queda cobrado y el certificado nunca avanza, para siempre
- **Archivo:** `config/recurring.yml` (no hay job de conciliación); `app/services/mercadopago_service.rb` (existe `sdk.payment.search` en el SDK, no se usa)
- **Regla:** **falta regla** (BR-071/BR-073 cubren la idempotencia y el reintento, ninguna cubre el pago que nunca se notificó)
- **Qué está mal:** Todo el estado de pago depende exclusivamente de que llegue y se procese el webhook. No hay ningún proceso periódico que compare la realidad de MP con la base local. `config/recurring.yml` solo tiene la limpieza de Solid Queue y los dos digests de onboarding/administración. Concretamente, ninguna de estas situaciones se recupera sola:
  - Webhook perdido por el bug del 200-silencioso (hallazgo anterior), por una caída de la app más larga que la ventana de reintentos de MP, o por un webhook no registrado para alguno de los 4 topics: el certificado queda `pending_payment` con la plata cobrada.
  - Certificado que queda `paid` sin emitir porque `IssueCertificateJob` agotó sus 3 intentos: se avisa al staff (BR-148, bien), pero no hay reintento posterior ni una cola de revisión en el panel; solo un correo que se puede perder.
  - Publicación que no se habilita porque el cobro recurrente no llegó.
  No hay tampoco ninguna vista de admin/staff que liste "certificados pagados sin emitir" o "solicitudes con más de N horas en `pending_payment`".
- **Cómo lo verifiqué:** `cat config/recurring.yml` (tres entradas, ninguna de pagos). `grep -rn "payout\|liquidaci\|settlement\|conciliaci" app/ lib/ db/schema.rb` → sin resultados. Revisé `app/jobs/` — solo `IssueCertificateJob`, `OnboardingRemindersJob`, `AdministrationRemindersJob`. En producción: `SolidQueue::FailedExecution.count = 0`, `ReadyExecution = 0`, `ScheduledExecution = 0` (no hay nada atascado hoy porque no hay ni un certificado: `ResidenceCertificate.count = 0`).
- **Impacto en go-live:** **Bloquea.** Con cero clientes es invisible; con vecinos reales es la diferencia entre "un pago se perdió y lo detectamos al día siguiente" y "un pago se perdió y nos enteramos cuando el vecino reclama, si reclama". Es la red de seguridad de todos los demás hallazgos de este informe.
- **Fix sugerido:** Un job recurrente (cada 15-30 min) que: (a) para cada `ResidenceCertificate`/`Listing` en `pending_payment` con más de N minutos de antigüedad y con preference creada, consulte `sdk.payment.search(filters: {external_reference: ...})` y aplique el estado real por el mismo camino que el webhook; (b) re-encole `IssueCertificateJob` para los `paid` sin `issued` con antigüedad > 1h; (c) exponga ambos conjuntos en una vista de staff. La idempotencia por `(payment_id, status)` ya existente hace que esto sea seguro de correr en paralelo con el webhook.

---

### [SEVERIDAD: Alta] En el pago único de publicaciones, BR-090 sigue validando contra `listing.amount`, que se reescribe con el precio vigente mientras hay links de checkout activos
- **Archivo:** `app/controllers/panel/listing_payments_controller.rb:114`; `app/controllers/webhooks/mercadopago_controller.rb:351-354`
- **Regla:** BR-084 / BR-090 / BR-086 (BR-145 arregló **solo** la rama de suscripción)
- **Qué está mal:** BR-145 introdujo `subscription_amount` como snapshot inmutable para el cobro recurrente, y el webhook de suscripción ya valida contra él (`:232`). Pero el **pago único** sigue comparando `amount_matches?(amount, listing.amount)` (`:351`), y `listing.amount` se sobreescribe con `@pricing.price` en **cada** entrada a `ListingPaymentsController#new` (`:114`). La secuencia que rompe:
  1. El usuario abre "pagar" → `listing.amount = 1000`, se crea la preference con `unit_price: 1000` y `expiration_date_to` a 24 h.
  2. La junta sube el precio a 2000.
  3. El usuario vuelve a abrir "pagar" (o simplemente abre el link viejo que aún tiene en el navegador/correo) → `listing.amount` pasa a 2000.
  4. Paga el link de $1.000, que sigue vigente. Llega el webhook: `amount_matches?(1000, 2000)` → **false** → `Rails.logger.warn` y `return`. **200 OK.**
  Resultado: el usuario pagó $1.000 reales, la publicación **no se habilita**, no hay devolución y el único rastro es una línea de log. La ventana es de hasta 24 h (TTL de la preference y de la clave de idempotencia de MP), pero es exactamente la ventana en que la gente paga.
  Agravante: `create_listing_preference` usa la clave de idempotencia estable `pref-listing-#{id}` (`mercadopago_service.rb:93`). MercadoPago retiene las claves de idempotencia **24 h** y devuelve la respuesta original ante una repetición, así que el paso 3 puede devolver la preference vieja de $1.000 mientras `listing.amount` ya vale 2000 — es decir, el propio flujo "correcto" produce el desalineamiento, sin necesidad de que el usuario guarde un link.
  El certificado **no** tiene este problema: su `amount` se fija al crear y ninguna ruta lo reescribe (verificado).
- **Cómo lo verifiqué:** Leí `listing_payments_controller.rb:114` (`@listing.update!(amount: @pricing.price, platform_fee: nil, ...)`) y `mercadopago_controller.rb:351` (compara contra `listing.amount`, no contra un snapshot). Contrasté con la rama de suscripción (`:232`), que sí usa `listing.subscription_amount || listing.amount` — la asimetría confirma que el fix de BR-145 no cubrió esta ruta. La retención de 24 h de la clave de idempotencia de MP la verifiqué en la documentación oficial de MercadoPago sobre `X-Idempotency-Key`.
- **Impacto en go-live:** **Bloquea el marketplace** (no el certificado). Es una pérdida de dinero del usuario, silenciosa y sin recurso. Hoy es inerte en producción porque no hay ninguna `ListingPricing` cargada, pero se activa el día que una junta ponga precio.
- **Fix sugerido:** Persistir el monto de la preference en un snapshot propio por intento de pago (p. ej. `checkout_amount`, o directamente una tabla de intentos), y validar el webhook contra ese snapshot y no contra el `amount` vivo. Alternativa más barata: no reescribir `amount` si ya hay una preference vigente para ese listing, y aceptar en el webhook cualquiera de los montos con preference activa. Como mínimo, ante un mismatch de monto **notificar al staff** en vez de solo loguear un `warn`.

---

### [SEVERIDAD: Alta] No hay contabilidad del 90% que pertenece a las juntas: sin split en MP, sin ledger, sin reporte, sin proceso de pago
- **Archivo:** `app/services/mercadopago_service.rb:28-119` (preferences sin `marketplace_fee`/`application_fee`); `app/models/residence_certificate.rb:245-248` y `app/models/listing.rb:179-181` (`platform_fee` calculado y guardado, y nada más)
- **Regla:** BR-004 / BR-085 (el 10% es de Yuntapp; el 90% es de la junta) — **falta regla** sobre cómo y cuándo se le entrega ese 90%
- **Qué está mal:** El cálculo de la comisión es correcto — verifiqué que `(amount * 10 / 100.0).round` redondea al peso (no trunca, #99), que corre solo cuando `platform_fee` está `nil`, y que las rutas que reescriben `amount` lo resetean para forzar el recálculo (BR-149). El problema no es el número: es que **el número no lleva a ninguna parte**.
  - Las preferences se crean sin `marketplace_fee`: MercadoPago acredita el **100%** del pago en la cuenta de Yuntapp. No hay split payment ni cuentas conectadas por junta.
  - `platform_fee` **no aparece en ninguna vista**: `grep -rln "platform_fee" app/views` no devuelve nada. Ni el admin de la junta ni el staff pueden ver cuánto se recaudó, cuánto le corresponde a cada junta ni cuánto se le ha pagado.
  - No existe ningún modelo, tabla ni job de liquidación/payout: `grep -rni "payout|liquidaci|settlement|rendicion|transferencia|marketplace_fee|application_fee|collector"` sobre `app/`, `lib/` y `db/schema.rb` no devuelve una sola coincidencia relevante.
  Es decir: el 90% del dinero de cada certificado es **plata de un tercero** (la junta de vecinos, una organización con RUT) que queda en la cuenta de MercadoPago de Yuntapp, sin registro agregado ni obligación rastreable, y el único modo de saber cuánto se le debe a quién es sumar a mano filas de `residence_certificates`.
- **Cómo lo verifiqué:** Leí los tres payloads de preference/preapproval completos en `mercadopago_service.rb` (ningún campo de split). `grep -rln "platform_fee" app/views app/controllers app/helpers` → solo los dos controllers que lo ponen en `nil`, cero vistas. El grep de payout/settlement sobre todo el código → solo un falso positivo en un comentario de `identity_transfer_service.rb`. En producción: `ResidenceCertificate.count = 0`, `Listing.count = 0`, `PaymentEvent.count = 0` — nada que conciliar todavía, y ninguna diferencia de fee detectada (`fee_mismatch=[]`, `listing_fee_mismatch=[]`).
- **Impacto en go-live:** **Bloquea abrir a juntas reales**, aunque no bloquee técnicamente el cobro. Cobrarle a un vecino en nombre de una junta y no tener forma de decirle a esa junta cuánto se le debe ni cómo se le paga es un problema de confianza y probablemente contable/tributario, no solo de software. Con un único cliente demo es manejable; con la primera junta real es lo primero que van a preguntar.
- **Fix sugerido:** Corto plazo (suficiente para abrir con pocas juntas): una vista de staff con la recaudación por junta y período (`SUM(amount)`, `SUM(platform_fee)`, neto de la junta) y un modelo `Payout` que registre las transferencias manuales, más una BR que fije la periodicidad. Mediano plazo: evaluar Split Payments / Marketplace de MercadoPago (`marketplace_fee` + cuenta conectada por junta) para que MP acredite el 90% directamente a la junta y el 10% a Yuntapp, eliminando la custodia de fondos ajenos.

---

### [SEVERIDAD: Alta] Producción no tiene monitoreo de errores: todas las alertas del flujo de dinero son `Rails.logger` a stdout
- **Archivo:** `Gemfile`, `config/environments/production.rb:37-41`
- **Regla:** **falta regla** (soporte operacional de BR-071/BR-073/BR-090/BR-141/BR-148)
- **Qué está mal:** El código está lleno de avisos de dinero bien puestos: pago con monto distinto (`:326`, `:352`), notificación tardía de un pago revertido (`:273`), `AlreadyPaidError` (`:69`), `PAYMENT REVERTED` (`:383`), preference sin `init_point` (`payments_controller.rb:26`). Todos son `Rails.logger.warn`/`error`. Y el logger de producción es `ActiveSupport::TaggedLogging.logger(STDOUT)` con nivel `info`, sin ninguna gema de error tracking: `grep -rn "sentry\|Sentry" Gemfile config/ app/` no devuelve nada. Los únicos avisos que salen del servidor son dos correos (`PaymentReversalMailer`, `CertificateIssuanceFailureMailer`), y solo para dos casos concretos.
  En la práctica: cuando ocurra cualquiera de los hallazgos anteriores, la evidencia estará en `docker logs` de un contenedor que se recicla en cada deploy, y nadie va a estar mirando.
- **Cómo lo verifiqué:** `grep -rn "sentry\|Sentry" Gemfile config/ app/` → sin resultados. `grep -n "log_level\|logger" config/environments/production.rb` → `STDOUT`, nivel `info`. `docker ps` en el servidor → solo `yuntapp-web` y `kamal-proxy`, ningún agente de observabilidad. Confirmé que hay 2 superadmins con correo (`gfiguero@gmail.com`, `daniela.tobar.g@gmail.com`) y que la API key de Resend está presente, así que los dos mailers de alerta sí funcionarían.
- **Impacto en go-live:** **Bloquea.** Este informe encontró tres formas distintas de perder plata en silencio. Sin monitoreo, "en silencio" es literal. Es el hallazgo más barato de arreglar y el que más reduce el riesgo de los demás.
- **Fix sugerido:** Agregar Sentry (o equivalente) con captura de `Rails.logger.error` y de excepciones no manejadas, más una alerta específica sobre el endpoint del webhook (tasa de 4xx/5xx y de no-ops). Complementariamente, subir a `error` los `warn` que representan dinero (mismatch de monto, `AlreadyPaidError`, pago revertido de otro `payment_id`) para que crucen el umbral de alerta.

---

### [SEVERIDAD: Alta] El panel de certificados scopea por domicilio y no por núcleo familiar: un jefe de hogar ve y descarga el PDF pagado por otra familia conviviente
- **Archivo:** `app/controllers/panel/residence_certificates_controller.rb:12-14, 97`; `app/controllers/panel/payments_controller.rb:60-72`
- **Regla:** BR-041 / BR-098 / BR-007
- **Qué está mal:** *(Adyacente al foco de dinero, pero es el producto pagado y lo verifiqué, así que lo dejo asentado.)* La creación de certificados fue endurecida en 2026-08-19 para filtrar por `family_group` (`selectable_residencies`, con un comentario explícito de que el filtro "es de seguridad, no cosmético"). Pero la **lectura** no se corrigió: `index` hace `.where(household_unit: current_user.household_unit)` y `set_residence_certificate` (usado por `show` **y por `download`**) hace exactamente lo mismo. Un `HouseholdUnit` es una dirección física que por BR-040/BR-043 aloja varios `FamilyGroup` sin relación entre sí, cada uno con su propio `household_admin` con cuenta (BR-151). Por lo tanto el jefe del núcleo B lista, abre y **descarga el PDF** del certificado de residencia oficial del núcleo A — con nombre completo, RUN sin enmascarar, domicilio y código de validación. `Panel::PaymentsController#set_certificate` tiene el mismo scope, así que además puede iniciar el pago de un certificado ajeno.
- **Cómo lo verifiqué:** Leí los tres métodos y contrasté con `selectable_residencies` (`:144-152`), que sí filtra por `residency.family_group_id == family_group.id`. Confirmé el modelo de datos en `app/models/user.rb:53-67`: `household_unit` y `family_group` derivan ambos de `residency`, y son niveles distintos — `household_unit` es el más grueso. El `download` pasa por `set_residence_certificate`, no por ningún filtro adicional (`:32-43` solo valida `downloadable?`).
- **Impacto en go-live:** **Bloquea** si algún domicilio real llega a tener dos núcleos, que es precisamente el escenario que BR-040/BR-041 existen para modelar. Es la misma clase de fuga que motivó el fix de `create`, en la ruta que expone el documento completo.
- **Fix sugerido:** Scopear `index`, `show`, `download` y `PaymentsController#set_certificate` por `family_group` (vía la `Residency` del titular) en vez de por `household_unit`, reusando el mismo criterio que `selectable_residencies`. Agregar un test de controller con dos `FamilyGroup` en un mismo `HouseholdUnit`.

---

### [SEVERIDAD: Media] Las credenciales de MercadoPago son las mismas en desarrollo, test y producción
- **Archivo:** `config/credentials.yml.enc` (único, sin `config/credentials/production.yml.enc`); `config/initializers/mercadopago.rb:213-216`; `config/deploy.yml` (env `secret: [RAILS_MASTER_KEY]`)
- **Regla:** BR-072 (precondición operacional del `webhook_secret`) — **falta regla** sobre separación de entornos
- **Qué está mal:** Hay un solo archivo de credenciales para todos los entornos. Hoy eso es inocuo porque el token es de una cuenta de prueba; el día que se cargue el token **real** (fix del hallazgo Crítico), cualquier desarrollador corriendo `bin/rails` en su máquina estará operando contra la cuenta de producción de MercadoPago: creando preferences reales, y con `cancel_preapproval` pudiendo cancelar suscripciones de usuarios reales. Simétricamente, el `webhook_secret` de producción queda en el `credentials.yml.enc` de cada checkout de desarrollo. El initializer sí permite override por `ENV`, pero el deploy no lo usa (`config/deploy.yml` solo pasa `RAILS_MASTER_KEY`).
- **Cómo lo verifiqué:** `ls config/credentials*` → solo `credentials.yml.enc` y `master.key`; no existe el directorio `config/credentials/`. `bin/rails runner` local sobre `Rails.application.credentials.mercadopago` → mismas claves y mismo prefijo `APP_USR-81` que produce el contenedor de producción. `env | grep MERCADOPAGO` dentro del contenedor → vacío (no viene de ENV). `sed -n '/env:/,/^[a-z]/p' config/deploy.yml` → solo `RAILS_MASTER_KEY` como secreto.
- **Impacto en go-live:** No bloquea por sí solo, **pero debe resolverse en el mismo cambio que el hallazgo Crítico**: es el momento exacto en que el riesgo aparece.
- **Fix sugerido:** Mover las credenciales de MP a `config/credentials/production.yml.enc` (con su `production.key` fuera del repo, entregada por Kamal), y dejar en el `credentials.yml.enc` compartido únicamente credenciales de sandbox para desarrollo. Alternativa equivalente: pasarlas por `env.secret` en `config/deploy.yml` desde el gestor de secretos, aprovechando el override por `ENV` que el initializer ya soporta.

---

### [SEVERIDAD: Media] Un cobro recurrente notificado por `topic=payment` entra por el camino del pago único: valida contra el monto equivocado y renueva perdiendo días de vigencia
- **Archivo:** `app/controllers/webhooks/mercadopago_controller.rb:305-310, 338-362` vs. `:186-251`
- **Regla:** BR-089 / BR-090 / BR-145 / BR-149
- **Qué está mal:** MercadoPago notifica los cobros de una preapproval por dos canales: `subscription_authorized_payment` **y** `payment` (el pago generado lleva el `external_reference` heredado de la preapproval, o sea `listing-<id>`). El handler de suscripción está bien (valida contra `subscription_amount`, usa `renew_from_subscription!`, re-sincroniza el fee). El handler de `payment` **no distingue** que se trata de un cobro recurrente:
  - Valida contra `listing.amount` en vez de `subscription_amount` (`:351`). Si divergieron —posible cuando la publicación alcanzó a vencer y el usuario abrió la pantalla de pago, que reescribe `amount` con el precio vigente— el cobro legítimo se descarta con un `warn`.
  - Si los montos sí coinciden y entra primero, usa `mark_as_paid!` en vez de `renew_from_subscription!`: la vigencia se calcula como `paid_at + 30.days` en vez de `published_until + 30.days`, así que el usuario **pierde los días que le quedaban** (contradice BR-089 explícitamente), y no se re-sincroniza `amount`/`platform_fee` con `charged_subscription_amount` (BR-149).
  El daño está acotado porque el otro canal suele llegar y la idempotencia por `(payment_id, "approved")` evita la doble renovación en cualquier orden — verificado: si `mark_listing_paid` corre primero registra el evento `approved`, y `process_subscription_authorized_payment` lo detecta con `payment_already_processed?` y no re-renueva.
- **Cómo lo verifiqué:** Comparé los dos caminos línea a línea. `mark_payable_paid:305` enruta por prefijo `listing-` sin mirar si el pago proviene de una preapproval (el campo `payment["metadata"]`/`payment_type` de MP no se consulta en ningún lado del controller — lo confirmé con `grep`). El uso de `subscription_amount` aparece **solo** en la línea 232.
- **Impacto en go-live:** No bloquea. Afecta al marketplace, que hoy está inerte en producción (0 `ListingPricing`).
- **Fix sugerido:** En `mark_listing_paid`, si el pago viene de una suscripción (por ejemplo `listing.preapproval_id.present? && listing.subscription_active?`, o inspeccionando el campo de MP que identifica el origen recurrente), delegar en la misma lógica que `process_subscription_authorized_payment`: validar contra `charged_subscription_amount` y renovar con `renew_from_subscription!`.

---

### [SEVERIDAD: Media] `Listing` no serializa sus transiciones de pago con `with_lock`, a diferencia de `ResidenceCertificate`
- **Archivo:** `app/models/listing.rb:66-82` (`mark_as_paid!`), `:106-118` (`apply_mp_payment_status!`), `:141-164` (`renew_from_subscription!`)
- **Regla:** BR-141 (el endurecimiento de 2026-08-02 se aplicó solo al certificado)
- **Qué está mal:** BR-141 documenta que las tres transiciones del certificado se envolvieron en `with_lock` porque el patrón leer-estado-y-después-escribir permitía que un webhook de reversión y otro proceso decidieran sobre la misma lectura. El espejo en `Listing` **no** recibió ese tratamiento: los tres métodos hacen `return if <condición sobre el estado en memoria>` seguido de `update!`, sin recargar. El propio `handle_non_approved` deja constancia del hueco en un comentario (`mercadopago_controller.rb:368-371`: "read-then-write sin lock"). En SQLite las escrituras serializan y el riesgo real es bajo, pero la protección de BR-146 (`reverted_payment?`) depende de que el `PaymentEvent` ya esté commiteado, lo que no está garantizado ante dos notificaciones concurrentes.
- **Cómo lo verifiqué:** `grep -n "with_lock" app/models/listing.rb` → sin resultados; el mismo grep sobre `residence_certificate.rb` devuelve las tres transiciones (`:140`, `:156`, `:193`).
- **Impacto en go-live:** No bloquea (motor SQLite, un solo servidor, marketplace inactivo). Sí bloquearía una migración a Postgres o a varios servidores web.
- **Fix sugerido:** Envolver los tres métodos de `Listing` en `with_lock`, replicando literalmente lo que ya se hizo en `ResidenceCertificate`.

---

### [SEVERIDAD: Media] El único cliente en producción es una junta demo y el marketplace no tiene precio: el flujo de dinero real nunca se ha ejercitado
- **Archivo:** datos de producción (no es un defecto de código)
- **Regla:** BR-135 (junta nueva arranca sin precios) / BR-121
- **Qué está mal:** El entorno de producción está esencialmente vacío y no permite afirmar que nada de esto funcione end-to-end con dinero real:
  - `NeighborhoodAssociation`: **1**, `[DEMO] Junta de Vecinos Los Aromos` (RUT `60000002-0`).
  - `CertificatePricing`: **1** ($2.000, de la junta demo). `ListingPricing`: **0** → hoy ninguna publicación puede pagarse (`ensure_priced_association!` corta con un flash, correctamente).
  - `ResidenceCertificate`: **0** · `Listing`: **0** · `PaymentEvent`: **0**.
  - 26 usuarios, 20 `Member`, 2 superadmins.
  No hay ni un solo pago histórico contra el cual validar la comisión, la emisión o las reversiones.
- **Cómo lo verifiqué:** `rails runner` de solo lectura contra el contenedor de producción, contando y agrupando `ResidenceCertificate`, `Listing`, `PaymentEvent`, `CertificatePricing`, `ListingPricing`, `NeighborhoodAssociation`, `User`, `Member` y las colas de Solid Queue. Adicionalmente comprobé que no hay desvíos de comisión (`fee_mismatch=[]` y `listing_fee_mismatch=[]` sobre el universo completo — vacío, así que el chequeo es trivialmente verdadero).
- **Impacto en go-live:** No es un defecto, pero sí una **precondición de salida**: hay que ejercitar el circuito completo con un cobro real antes de abrir.
- **Fix sugerido:** Tras cargar las credenciales reales, hacer un cobro de prueba real de $1.000 sobre una junta real con RUT válido, verificando: preference creada, pago acreditado en el balance de MP, webhook firmado recibido y con 200, `paid` → `issued`, PDF descargable, verificación pública OK, y `platform_fee` = 100. Repetir con un reembolso desde el panel de MP para validar BR-141 punta a punta.

---

### [SEVERIDAD: Baja] La firma del webhook no verifica la frescura del `ts`: una notificación válida capturada puede reproducirse indefinidamente
- **Archivo:** `app/services/mercadopago_service.rb:166-184`
- **Regla:** BR-072
- **Qué está mal:** `verify_signature` extrae `ts` del header solo para construir el manifest; nunca comprueba que esté dentro de una ventana razonable. Una notificación firmada legítima, capturada por cualquier intermediario, sigue validando meses después. El daño concreto es muy limitado porque la idempotencia por `(payment_id, status)` y la guarda `reverted_payment?` (BR-146) convierten casi cualquier reproducción en un no-op, y el estado real siempre se re-consulta a la API de MP.
- **Cómo lo verifiqué:** Lectura del método completo; `ts` solo aparece en la interpolación del manifest (`:177-179`), nunca en una comparación temporal.
- **Impacto en go-live:** No bloquea.
- **Fix sugerido:** Rechazar firmas con `ts` desviado más de ~5 minutos del reloj del servidor, con margen para el skew.

---

### [SEVERIDAD: Baja] El webhook no valida `currency_id` del pago
- **Archivo:** `app/controllers/webhooks/mercadopago_controller.rb:396-399` (`amount_matches?`)
- **Regla:** BR-090
- **Qué está mal:** La validación de monto compara solo el valor numérico de `transaction_amount`. Un pago en otra moneda con el mismo número pasaría el control. En la práctica es inalcanzable: la cuenta es `site_id: MLC` (Chile) y las preferences fijan `currency_id: "CLP"`.
- **Cómo lo verifiqué:** `amount_matches?` no referencia moneda; `grep -n "currency_id" app/` solo aparece en los payloads de `mercadopago_service.rb`. El `site_id: MLC` lo obtuve de `GET /users/me` en producción.
- **Impacto en go-live:** No bloquea.
- **Fix sugerido:** Exigir `payment["currency_id"] == "CLP"` junto con el monto, como defensa en profundidad.

---

### [SEVERIDAD: Baja] Un `household_admin` puede pagar el certificado de otra familia conviviente
- **Archivo:** `app/controllers/panel/payments_controller.rb:60-64`
- **Regla:** BR-041
- **Qué está mal:** Corolario del hallazgo Alta de scoping: `set_certificate` filtra por `household_unit`, así que el jefe del núcleo B puede iniciar el checkout de un certificado del núcleo A. Financieramente es inofensivo (paga de más por algo ajeno), pero completa la superficie del mismo defecto de aislamiento.
- **Cómo lo verifiqué:** Lectura de `set_certificate` y de `find_certificate_by_external_reference`, ambos con el mismo scope grueso.
- **Impacto en go-live:** No bloquea de forma independiente; se cierra con el fix del hallazgo Alta correspondiente.
- **Fix sugerido:** El mismo: scopear por `family_group`.

---

### [SEVERIDAD: Baja] La recepción de notificaciones depende por completo de la configuración manual del webhook en el panel de MercadoPago, sin verificación posible desde el código
- **Archivo:** `app/services/mercadopago_service.rb:23-27` (decisión consciente de no enviar `notification_url`)
- **Regla:** BR-071 / BR-072 — precondición operacional
- **Qué está mal:** Las preferences se crean deliberadamente **sin** `notification_url`, para que las notificaciones lleguen solo por el webhook del panel (cuya firma sí es verificable). La decisión es correcta, pero traslada un punto único de falla a una configuración externa: si el webhook no está registrado —o no está registrado para los cuatro topics `payment`, `merchant_order`, `subscription_preapproval`, `subscription_authorized_payment`— **nada** del flujo de dinero avanza y no hay señal alguna en la aplicación. Es el mismo P8 del audit del 29-07, que quedó como verificación operacional pendiente. No es verificable desde el repositorio ni desde el servidor: hay que mirarlo en el panel de MP, y hay que volver a hacerlo cuando se cambie a la cuenta real (el webhook se configura por cuenta).
- **Cómo lo verifiqué:** Confirmé la ausencia de `notification_url` en los tres payloads de `mercadopago_service.rb` y el comentario que lo justifica (`:25-27`). Confirmé que los cuatro topics están manejados en el `case` del controller (`:42-56`).
- **Impacto en go-live:** No es un defecto de código, pero **debe quedar en el checklist de salida** junto al cambio de credenciales.
- **Fix sugerido:** Incluir en el runbook de go-live: registrar el webhook de la cuenta real apuntando a `https://yuntapp.cl/webhooks/mercadopago` con los cuatro topics, copiar la clave secreta a las credenciales de producción, y validar con la herramienta de notificación de prueba del panel de MP que llega firmada y responde 200.

---

## Áreas revisadas sin hallazgos

- **Cálculo de la comisión (BR-004/BR-085/BR-149).** `(amount * PLATFORM_FEE_PERCENTAGE / 100.0).round` en ambos modelos: redondea al peso en vez de truncar, corre solo con `platform_fee` nulo, y las tres rutas que reescriben `amount` (`ListingPaymentsController#new`, `ListingSubscriptionsController#create`, `renew_from_subscription!`) lo resetean a `nil` para forzar el recálculo. El `amount` del certificado no lo reescribe nadie. Verificado en producción: cero desvíos entre `platform_fee` y el 10% del `amount` en todo el universo de registros.
- **Firma HMAC (BR-072).** Manifest correcto con y sin `request-id`, soporte `v1`/`v2`, `secure_compare` con chequeo previo de `bytesize`, y 401 obligatorio cuando hay secret. Secret presente en producción (64 chars).
- **Idempotencia (BR-071/BR-087/BR-146).** Índice único `(payment_id, status)` en `payment_events`, más índices únicos parciales en `residence_certificates.payment_id` y `listings.payment_id`/`preapproval_id`. La guarda `reverted_payment?` cierra la resurrección por `merchant_order` tardío, con tres tests dedicados. La renovación por suscripción y el registro del evento commitean en una sola transacción.
- **Reversiones sobre el certificado (BR-141).** `apply_mp_payment_status!` con `with_lock`, precedencia de "No válido" sobre "Vencido" en la verificación pública, `downloadable?` bloqueado, alerta al staff por correo. Correcto — salvo el problema de identidad del `payment_id` reportado arriba.
- **Emisión tras el pago (BR-062/BR-076/BR-148).** `issue!` exige `paid?` y RUT de la junta, es idempotente, resuelve colisiones de folio con reintento acotado, y el job re-adjunta el PDF si quedó `issued` sin archivo. Tres reintentos con backoff y aviso al staff al rendirse. Los guards de RUT están en `new`, `create` y en `PaymentsController#new`.
- **Suscripciones — `payer_email` (BR-142).** El formulario precarga `mercadopago_email` o el correo de login, valida el formato, lo persiste y lo usa como `payer_email` de la preapproval. No toca el correo de la cuenta (BR-093 intacto).
- **Suscripciones — cancelación (BR-088).** Idempotente ante un estado terminal en MP: el error del SDK se rescata y loguea, y el estado local se marca `cancelled` igual. La vigencia ya pagada no se corta.
- **Precios (BR-005/BR-070/BR-084/BR-135).** Mínimo $1.000 validado en ambos modelos de pricing, `effective_from` fijado por el servidor (no manipulable, no hay precios futuros que rompan `current_for`), y la creación de un precio cierra la vigencia anterior en un `before_create`.
- **Códigos HTTP del webhook.** La clasificación determinista (200) vs. transitorio (500) está bien razonada y bien testeada — el problema no es la clasificación sino que los errores de la API de MP nunca llegan a clasificarse (hallazgo Alta correspondiente).
- **Infraestructura de jobs.** `SOLID_QUEUE_IN_PUMA=true` en el contenedor web; sin ejecuciones fallidas, listas ni programadas pendientes en producción. Resend configurado y 2 superadmins con correo, así que los mailers de alerta tienen destinatario.
