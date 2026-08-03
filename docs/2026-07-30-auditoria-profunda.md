# Auditoría profunda de código — 2026-07-30

> **Recuperada desde el transcript de la sesión** (`2fe1aa36`), interrumpida por un corte de energía
> el 2026-07-30 ~23:00 antes de poder versionarse. La auditoría se completó íntegra: 6 agentes
> especializados en paralelo + verificación cruzada inline de los hallazgos de severidad Alta.
>
> **Estado del código auditado:** `master` en `e261ed5` (sin cambios desde entonces — los hallazgos siguen vigentes).
>
> Excluye todo lo ya remediado en los batches A–H y en las auditorías previas
> (`docs/2026-07-21-code-audit.md`, `docs/2026-07-25-br-audit.md`, `docs/2026-07-29-mercadopago-checkout-pro-audit.md`).

# 🔍 Informe de investigación profunda — yuntapp

**Alcance:** 6 dimensiones (certificados, onboarding/identidad, pagos MP, multi-tenant/autorización, admin de juntas/marketplace, consistencia doc↔código). Todos los hallazgos son **nuevos** — se excluyó lo ya remediado en auditorías previas. Los ✅ los verifiqué yo mismo en el código.

## 🔴 Severidad ALTA (8)

**1. ✅ El marketplace público expone publicaciones NO pagadas** · BR-083
`app/controllers/listings_controller.rb:21,41` usa `Listing.all` en vez del scope `Listing.published` (que existe, línea 33). Como todo `Listing` nace en `pending_payment` (default), **cualquiera publica gratis y aparece de inmediato en `/listings` sin pagar la habilitación** — también muestra vencidos. Anula el modelo de negocio del marketplace (BR-083/084).
→ Fix: `set_listings`/`set_listing` sobre `Listing.published`.

**2. ✅ "Reiniciar onboarding" DESTRUYE físicamente una solicitud `pending`** · BR-018 / BR-100
`panel/onboarding_controller.rb:14` hace `current_onboarding_request&.destroy`, y esa asociación **incluye `pending`** (`user.rb:33`). Con `dependent: :destroy` en IVR/RVR, un usuario con solicitud en revisión que pulsa "Reiniciar" borra el `OnboardingRequest` + identidad + residencia. BR-018 dice "se **cancela**" (existe `cancel!` sin usar). Es exactamente el patrón de borrado destructivo que BR-100 prohíbe.
→ Fix: usar `cancel!` si está `pending`; permitir `destroy` solo en `draft`.

**3. ✅ La geografía se borra en cascada y arrastra juntas** · BR-100
`country.rb:4` y `region.rb:3` tienen `dependent: :destroy`; `commune.rb:3` tiene `has_many :neighborhood_associations` **sin protección**. Los 3 controllers superadmin hacen `destroy!`. Borrar un país cascadea región→comuna y **rompe la FK de juntas o las orfana**. La rama geográfica quedó fuera del blindaje BR-100 que sí tiene `NeighborhoodAssociation`.
→ Fix: `:restrict_with_error` en las cascadas geográficas + `restrict` en `Commune→neighborhood_associations`, o quitar los `destroy`.

**4. ✅ Borrado físico de publicaciones** · BR-100
`panel/listings_controller.rb:71` y `admin/listings_controller.rb:54` hacen `@listing.destroy!`. `payment_events` (`restrict_with_error`) protege los que ya pagaron, pero un listing published sin evento asociado o con historial revertido desaparece con su snapshot financiero (`amount`, `platform_fee`, junta beneficiaria BR-085). No hay guard `before_destroy` como en `Member`/`User`.
→ Fix: despublicar/`active: false` o guard `before_destroy`.

**5. ✅ Edición directa del RUN de una identidad aprobada** · BR-046
`admin/members_controller.rb:70` (`update`) hace `verified_identity.update!(verified_identity_params)` y los params permiten `:run` (línea 123). `create` sí hace `.except(:run)`, pero `update` **no** → un admin puede reescribir el RUN de una identidad ya verificada, saltándose toda verificación documental y desincronizando certificados ya emitidos. BR-046 lo prohíbe explícitamente.
→ Fix: excluir `:run` en `update` (o `attr_readonly` una vez hay Member aprobado).

**6. ✅ El monto de la suscripción no está congelado: `listing.amount` es mutable** · BR-088 / BR-090
`listing_subscriptions_controller.rb:43` y `listing_payments_controller.rb:18` reescriben `listing.amount` con el precio **vigente** cada vez que el usuario entra. El webhook de cobro recurrente compara contra `listing.amount`. Si la junta sube el precio y el usuario re-abre pagar/renovar, MP sigue cobrando el monto viejo → `amount_matches?` falso → **la renovación legítima se rechaza y la publicación vence pese al pago**. (El guard #109 mitiga solo mientras está `published` vigente; el hueco queda si venció.)
→ Fix: columna dedicada `subscription_amount` inmutable, o validar contra `auto_recurring.transaction_amount` de MP.

**7. Una reversión (refund/chargeback) que llega vía `merchant_order` tardío puede resucitar un pago revertido** · BR-141
`webhooks/mercadopago_controller.rb` — un `merchant_order` `closed` reprocesa `mark_as_paid!` sobre un cert/listing que un refund previo ya dejó en `pending_payment`, revirtiendo la reversión. (No lo verifiqué a fondo; requiere revisar la ventana exacta.)
→ Fix: antes de `mark_as_paid!`, chequear que no exista `PaymentEvent` revertido / `payment_status` en `REVERTED_PAYMENT_STATUSES`.

**8. ✅ La descarga del PDF evade `downloadable?` vía URL firmada sin expiración** · BR-091 / BR-092 / BR-141
`panel/residence_certificates_controller.rb:30` hace `redirect_to rails_blob_path(...)`. Con `active_storage.service = :local` y sin `urls_expire_in`, la URL del blob depende solo del `signed_id` (no de `current_user` ni de `downloadable?`) y **no expira**. Un socio guarda la URL y sigue re-descargando aunque luego sea desactivado (BR-091), el cert venza (BR-092) o el pago se revierta (BR-141).
→ Fix: servir con `send_data` tras `downloadable?`, o modo `:proxy` + `urls_expire_in = 5.minutes`.

## 🟡 Severidad MEDIA (11 — resumen)

- **Cert pagado en junta sin RUT queda atascado en `paid` para siempre** (sin emisión, sin refund por BR-063, sin alerta al staff). `create`/`payments#new` no chequean RUT; solo `issue!` aborta. → bloquear solicitud/pago si la junta no tiene RUT. *(BR-120)*
- **IDOR de directiva**: `board_members_controller.rb:82` permite `:member_id` sin validar que el Member sea de la junta → un admin agrega a la directiva (y filtra datos de) un socio ajeno. *(BR-007)*
- **Socio desactivado sigue registrando dependientes**: `panel/dependents_controller` no exige Member activo (a diferencia de certificados); tras BR-036 la `Residency` no cambia, así que `household_admin?` sigue `true`. Al aprobarlos se recrea un `Member(approved)`. *(BR-091/099)*
- **`admin/members#create` no es transaccional**: persiste `VerifiedIdentity` aunque falle el `Member`; crea socio sin `requested_by`/`status`/residencia. *(BR-024/044)*
- **La aprobación de administración no exige junta `active`** → puede dejar a un admin operando una junta disuelta. *(BR-054)*
- **Faltan advertencias al staff**: BR-137 (desactivará al socio en otra junta), BR-139 (junta duplicada), BR-140 (cargo ocupado) — la ejecución existe, el aviso previo no.
- **Carrera revert↔issue sin `with_lock`** en el borde reversión/emisión. *(BR-141)*
- **`platform_fee` no se recalcula tras reversión** (queda con el fee del monto viejo si se re-paga con otro precio). *(BR-004/085)*
- **Cancelar suscripción no es idempotente**: error del SDK MP no rescatado → 500 si MP ya la canceló. *(BR-088)*
- **Página `success` de pago** no refleja el estado real (puede decir "éxito" con cert aún `pending_payment`).
- **Doc "Modelo de Datos" desalineada**: `VerifiedIdentity` documenta `verification_status` (columna inexistente); `approved_by_id` en cert es vestigial y contradice BR-062/077.

## 🟢 Severidad BAJA (12 — deuda, doc, tests)

Normalización de direcciones ausente → `HouseholdUnit` duplicados (BR-040); normalización de RUN copiada en 4 sitios; `masked_run` devuelve el RUN completo sin guión (BR-078); `external_reference` malformado sin log; posible doble cobro del primer mes de suscripción (sin `start_date`); redacción engañosa de BR-136 ("FK único"); TOCTOU en solicitud de administración sin índice único (BR-134); `resolve_identity!` sobrescribe identidad sin usar `IdentityTransferService`; `Admin::UsersController` es código muerto con violación latente de BR-093; estados `cancelled` y método `generate_folio!` mal documentados; **gaps de tests** del invariante de RUN duplicado (`IdentityTransferService`) y del cert en junta sin RUT.

## 📋 Reglas de negocio faltantes (candidatas a nueva BR)

1. **No permitir solicitar/pagar un certificado si la junta no tiene RUT** (precondición de BR-120 — evita cobros sin emisión posible).
2. **Normalización de direcciones** análoga a BR-014 (evita `HouseholdUnit` duplicados).
3. **La vitrina pública solo muestra `published` vigentes** (formalizar el enforcement de BR-083).
4. **Recálculo de `platform_fee` tras reversión** (garantiza el 10% exacto, BR-004).

---

## Resumen

**8 Alta · 11 Media · 12 Baja · 4 reglas faltantes.** El patrón dominante y más preocupante son **borrados/exposiciones que contradicen invariantes ya establecidos**: BR-100 (no destruir) se viola por 3 vías nuevas (restart, geografía, listings), y el marketplace público filtra publicaciones impagas. Los hallazgos Alta 1–5 y 8 son de bajo esfuerzo y alto impacto.

---

# Anexos — informes completos por dimensión

## Anexo — Pagos MercadoPago

_Agente `a814be22f292393a2`_

I have enough evidence for a complete audit. Here are my findings.

---

### Auditoría MercadoPago — Hallazgos nuevos

#### [SEVERIDAD: Alta] El monto snapshot de la suscripción no está congelado: `listing.amount` se muta y rompe la validación de monto del cobro recurrente (BR-088/BR-090)

- **Archivo:** `app/controllers/panel/listing_payments_controller.rb:18`, `app/controllers/panel/listing_subscriptions_controller.rb:43`, `app/controllers/webhooks/mercadopago_controller.rb:226`
- **BR:** BR-088, BR-090
- **Qué está mal:** BR-088 dice que el monto de la suscripción queda fijo al autorizar y que "si la junta cambia su precio, las suscripciones vigentes mantienen el monto antiguo". Pero el monto de la suscripción vive en MP (`preapproval.auto_recurring.transaction_amount`), y localmente el gate de cobro recurrente compara contra `listing.amount` (línea 226: `amount_matches?(amount, listing.amount)`). `listing.amount` es mutable: se sobreescribe cada vez que el usuario entra a `ListingPaymentsController#new` (línea 18) o a `ListingSubscriptionsController#create` (línea 43) con `@pricing.price` (el precio VIGENTE de la junta). Secuencia real que rompe:
  1. Usuario se suscribe con precio $1.000 → MP cobra $1.000/mes fijo; `listing.amount = 1000`.
  2. La junta sube el precio a $2.000.
  3. El usuario abre "renovar/pagar" (`ListingPaymentsController#new`) o intenta re-suscribirse → `listing.amount` pasa a $2.000 (líneas 18/43). *Nota:* `pricing_snapshot_immutable_while_published` solo bloquea si el listing está `published` vigente; si venció, o si el guard no dispara, el update pasa.
  4. Llega el siguiente cobro recurrente de MP por $1.000 (el fijo original) → `amount_matches?(1000, 2000)` es **false** → el webhook rechaza la renovación legítima (línea 227) y la publicación **vence indebidamente** pese a que el usuario pagó.
- **Impacto:** Cobros recurrentes legítimos rechazados silenciosamente; el usuario paga en MP pero su publicación vence. Inversamente, si el precio baja, se aceptaría un cobro mayor. El snapshot de suscripción debería vivir en un campo inmutable propio (p. ej. `subscription_amount`), no en `listing.amount`.
- **Fix sugerido:** Persistir el monto de la suscripción en una columna dedicada al crear la preapproval (`subscription_amount`, inmutable mientras `subscription_status == authorized`) y comparar el cobro recurrente contra ella, no contra `listing.amount`. Alternativamente, re-consultar `fetch_preapproval` y validar contra `auto_recurring.transaction_amount` de MP.

---

#### [SEVERIDAD: Alta] La reversión (refund/chargeback) que llega vía `merchant_order` nunca degrada el certificado/listing

- **Archivo:** `app/controllers/webhooks/mercadopago_controller.rb:114-128`
- **BR:** BR-073, BR-141
- **Qué está mal:** `process_merchant_order` itera los payments del order y llama `mark_payable_paid(payment, pid)`. `mark_payable_paid` → `mark_certificate_paid`/`mark_listing_paid` maneja `approved` y despacha lo demás a `handle_non_approved`. Eso parece correcto, PERO: cuando MP procesa un refund/chargeback, la notificación llega típicamente por `topic=payment` con el payment ya en `refunded`. El problema real está en el **orden y la re-consulta**: `process_merchant_order` re-consulta cada payment (`fetch_payment(pid)`), y si el `merchant_order` conserva el payment original en estado `approved` en su listado interno mientras el payment individual ya fue reembolsado, el flujo aplica `approved` de nuevo. Más concretamente: un merchant_order `closed` con un pago aprobado dispara `record_order_closed` y re-marca `mark_as_paid!` — y como `apply_mp_payment_status!` ya dejó el cert en `pending_payment` tras un refund previo, un merchant_order tardío lo **re-marca como paid** (línea 303/327), revirtiendo la reversión.
- **Impacto:** Un merchant_order que llega después de un refund puede resucitar un certificado/listing revertido a `paid`/`published`, contradiciendo BR-141. Ventana estrecha pero real dado que MP reenvía merchant_orders.
- **Fix sugerido:** En `mark_certificate_paid`/`mark_listing_paid`, antes de `mark_as_paid!`, verificar que no exista un `PaymentEvent` con status revertido para ese `payment_id` (o que `payment_status` actual no esté en `REVERTED_PAYMENT_STATUSES`); si el pago fue revertido, no re-marcar como pagado.

---

#### [SEVERIDAD: Media] `external_reference` malformado tipo `listing-` sin id, o `listing-abc`, se resuelve silenciosamente a nil sin log de rechazo explícito

- **Archivo:** `app/controllers/webhooks/mercadopago_controller.rb:150-155, 281-285`
- **BR:** BR-087
- **Qué está mal:** `resolve_payable` y `mark_payable_paid` hacen `delete_prefix("listing-")` y `find_by(id: ...)`. Si el `external_reference` es exactamente `"listing-"` (sin id) o `"listing-xyz"` (id no numérico), `find_by(id: "")`/`find_by(id: "xyz")` devuelve nil y solo se loguea "listing not found" con un id vacío. Peor: un `external_reference` numérico que casualmente empiece con la subcadena no es problema (se exige prefijo exacto), pero un `external_reference` de un certificado cuyo id fuese, hipotéticamente, alfanumérico no aplica aquí (ids son enteros). El caso real: `external_reference` nulo se maneja (línea 274), pero un `listing-` vacío cae al branch de listing y busca `Listing` con id blank — comportamiento benigno pero sin distinción clara en logs para diagnóstico.
- **Impacto:** Bajo riesgo funcional, pero dificulta el diagnóstico y un `external_reference` corrupto se traga silenciosamente. No hay validación de que el sufijo sea un id entero válido.
- **Fix sugerido:** Validar `external_reference.match?(/\Alisting-\d+\z/)` / `/\A\d+\z/` antes de enrutar; loguear `warn` explícito para formatos no reconocidos.

---

#### [SEVERIDAD: Media] `platform_fee` no se recalcula al re-pagar tras una reversión (queda con el fee del monto viejo)

- **Archivo:** `app/models/residence_certificate.rb:26,191`, `app/models/listing.rb:21,127`
- **BR:** BR-004, BR-085 / FALTA BR explícita para recálculo tras reversión
- **Qué está mal:** `compute_platform_fee` corre solo `if: -&gt; { amount.present? &amp;&amp; platform_fee.nil? }`. Tras un refund, `apply_mp_payment_status!` deja el cert en `pending_payment` pero **no limpia `platform_fee`**. Si el usuario re-paga con un `amount` distinto (p. ej. la junta cambió el precio y se recreó el certificado — o para listings donde `amount` sí se re-captura al renovar en `mark_listing_paid`), el `platform_fee` conserva el valor calculado del monto anterior porque `platform_fee` ya no es nil. Para listings el flujo de renovación en `ListingPaymentsController#new` sí hace `platform_fee: nil` (línea 18), pero el flujo de **suscripción** (`renew_from_subscription!`) actualiza `payment_id`/`published_until` sin tocar `amount`/`platform_fee`, y el webhook de pago único (`mark_as_paid!`) tampoco recalcula si el amount cambió entre el snapshot y el pago.
- **Impacto:** La comisión de Yuntapp puede quedar desincronizada del monto realmente cobrado si hay un ciclo reversión→re-pago con precio distinto. Viola BR-004/BR-085 (10% exacto del monto pagado).
- **Fix sugerido:** En `apply_mp_payment_status!` al revertir, resetear `platform_fee: nil` para forzar recálculo en el próximo pago; o recalcular `platform_fee` explícitamente en `mark_as_paid!` cuando `amount` cambie.

---

#### [SEVERIDAD: Media] La cancelación de suscripción es no-idempotente y puede fallar duro si MP ya la canceló

- **Archivo:** `app/controllers/panel/listing_subscriptions_controller.rb:77-92`
- **BR:** BR-088
- **Qué está mal:** `cancel` llama `mercadopago.cancel_preapproval` que hace `sdk.preapproval.update(id, {status: "cancelled"})`. Si MP ya canceló la preapproval (p. ej. por fallos de cobro repetidos, o el usuario canceló desde la app de MP y el webhook `subscription_preapproval` ya sincronizó a `cancelled`) el guard local (`subscription_status == "cancelled"`) protege ese caso, pero si el estado local es `authorized` y MP ya la tiene en un estado terminal distinto, la llamada `update` a MP puede devolver error, que **no se rescata** (solo se rescata `ConfigurationError`). Un error de MP no manejado propaga 500 al usuario.
- **Impacto:** UX rota (500) al cancelar en escenarios de desincronización; el estado local no se actualiza.
- **Fix sugerido:** Rescatar errores del SDK de MP en `cancel` y, ante fallo, degradar con flash; considerar re-consultar el estado real antes de intentar el update.

---

#### [SEVERIDAD: Media] La página `success` de pago único no confirma el pago ni informa estado real; puede mostrar "éxito" con el certificado aún `pending_payment`

- **Archivo:** `app/controllers/panel/payments_controller.rb:39-46`, `app/controllers/panel/listing_payments_controller.rb:45-51`
- **BR:** BR-002, BR-003
- **Qué está mal:** `success` solo hace `find_certificate_by_external_reference` y renderiza. El pago real se confirma vía webhook (correcto), pero `success` no valida el estado; MP redirige a `success_url` con `auto_return: "approved"` incluso en la ventana donde el webhook aún no llegó. Si la vista de `success` afirma "pago confirmado / certificado emitido" mientras el estado sigue `pending_payment`, engaña al usuario. No hay lógica que reconcilie ni muestre "procesando".
- **Impacto:** Mensaje potencialmente falso de éxito; el usuario cree que pagó y no ve el certificado emitido. (Depende de la vista `.erb`, no revisada — pero el controller no aporta el estado, así que la vista no puede diferenciar.)
- **Fix sugerido:** En `success` mostrar el `status`/`publication_status` real y un estado "procesando" si aún no está `paid`/`published`; opcionalmente `fetch_payment` para reconciliar sincrónicamente.

---

#### [SEVERIDAD: Baja] `record_order_closed` puede lanzar `RecordNotUnique` benigno tratado como no-op, pero comparte el `rescue` con casos reales

- **Archivo:** `app/controllers/webhooks/mercadopago_controller.rb:134-145, 62-70`
- **BR:** BR-071
- **Qué está mal:** `record_order_closed` usa `record_payment_event` con `find_or_create_by`, que ya es idempotente; sin embargo el `rescue ActiveRecord::RecordNotUnique` de nivel controller (línea 62) responde 200 tratándolo como no-op determinista. Es correcto para idempotencia, pero mezcla el caso "otro webhook ya lo procesó" con posibles `RecordNotUnique` de otras columnas (p. ej. `validation_code` en emisión), haciendo que MP no reintente un fallo que sí podría ser transitorio-resoluble. Riesgo bajo porque la emisión ocurre en job aparte, no en el webhook.
- **Impacto:** Muy bajo; principalmente robustez de clasificación de errores.
- **Fix sugerido:** Restringir el rescue de `RecordNotUnique` a colisiones esperadas (payment_id/order key) para no enmascarar otras.

---

#### [SEVERIDAD: Baja] La preapproval no fija `start_date`/`end_date` ni `notification_url`; depende íntegramente de la config del panel MP

- **Archivo:** `app/services/mercadopago_service.rb:100-119`
- **BR:** BR-088, BR-089 / FALTA BR
- **Qué está mal:** El payload de `create_listing_subscription` no incluye `start_date` (primer cobro) ni límites. MP por defecto cobra inmediatamente al autorizar; combinado con `renew_from_subscription!` que extiende desde `published_until` si está al día, un usuario que se suscribe **el mismo día que paga el pago único** recibe un cobro recurrente inmediato de MP, duplicando efectivamente el gasto del primer mes (aunque la vigencia se extiende correctamente, el usuario paga dos veces por el primer período). No hay `start_date` para diferir el primer cobro al vencimiento.
- **Impacto:** Posible doble cobro del primer período (pago único + primer cobro recurrente inmediato). Molestia de negocio, no rotura técnica.
- **Fix sugerido:** Pasar `auto_recurring.start_date` = `published_until` (o pago+30d) cuando el listing ya está pagado, para que el primer cobro recurrente caiga al vencer la vigencia ya pagada.

---

#### Puntos verificados y limpios

- **Idempotencia por `(payment_id, status)`** (BR-071/BR-087): correcta vía índice único en `payment_events` + `PaymentEvent.exists?`. La clave incluye `status`. `x-idempotency-key` es estable por recurso (`pref-cert-#{id}`, `preapproval-listing-#{id}`).
- **Firma obligatoria con secret** (BR-072): correcta — `webhook_secret_configured?` fuerza 401 si falta/invalida firma. `secure_compare` con chequeo de bytesize previo, bien.
- **Validación de monto antes de marcar pagado** (BR-090): presente en los tres flujos de `approved` (cert, listing, suscripción) con `amount_matches?` usando `to_d` (evita el bug de `==` entre Integer/Float/String).
- **Clasificación transitorio (500) vs determinista (200)** en el webhook: bien razonada.
- **Snapshot inmutable de `amount` del certificado** mientras `issued` (`immutable_once_issued`) y del listing mientras vigente: correcto (excepto el hueco de `platform_fee` reportado arriba).
- **`payment_reverted?` con precedencia sobre vencido** en `downloadable?`: correcto (BR-141).

**Prioridad de remediación:** los dos hallazgos de severidad Alta (snapshot de suscripción vía `listing.amount` mutable, y resurrección de pago revertido vía merchant_order tardío) son los que pueden causar pérdida de dinero o publicaciones que vencen pese al pago — recomiendo abordarlos primero.

## Anexo — Onboarding e identidad

_Agente `a5ebd89c1d2812b25`_

Normalizations are fine (RUN &lt;7 digits is caught by RunValidator format). Now checking one last real concern: the `dependents#create` does NOT block a RUN that already belongs to an active member of the SAME family group / association — but that's handled at admin approval (BR-057/069). That's by design.

Let me verify the `admin/members#update` RUN-edit concern definitively and whether there's a validation error masking in `admin/members#create` (VerifiedIdentity errors merged but `email` not set → possible). I have what I need.

Based on my complete read of the code, here are my findings.

---

### Hallazgos — Onboarding, identidad, residencia, RUN duplicado, dependientes, cascadas

**[SEVERIDAD: Alta]** Edición directa del RUN de una identidad aprobada viola BR-046
- `app/controllers/admin/members_controller.rb:69-70` (`update`) y `:122-124` (`verified_identity_params`)
- BR-046 (No existe edición directa del RUN post-aprobación)
- `verified_identity_params` permite `:run`, y `update` hace `@member.verified_identity.update!(verified_identity_params)`. Es decir, un admin puede editar el formulario "Editar socio" y **cambiar el RUN de una `VerifiedIdentity` ya aprobada** directamente. BR-046 dice explícitamente: "Para corregir un RUN erróneo... el admin desactiva al socio y el socio realiza un nuevo onboarding con el RUN correcto. **No existe edición directa del RUN post-aprobación**."
- Impacto: rompe el invariante de identidad. Un RUN editado a mano salta toda la verificación documental de la nueva persona, puede colisionar con el `uniqueness` (fallando con 500 en vez de mensaje limpio) y desincroniza el `VerifiedIdentity` de los certificados ya emitidos a su nombre (folio/validación quedan atados a un titular cuyo RUN cambió).
- Fix sugerido: excluir `:run` de los params editables en `update` (permitir solo `first_name`, `last_name`, `phone`, `email`), o rechazar en el modelo cualquier cambio de `run` cuando la identidad ya tiene un `Member` aprobado. Mantener el RUN editable solo en `create` (donde `find_or_initialize_by(run:)` sí tiene sentido).

**[SEVERIDAD: Alta]** El guard de `dependent_reviews#approve` hace un early-return DENTRO de la transacción efectiva pero deja el request en estado inconsistente si falla la herencia de residencia
- `app/controllers/admin/dependent_reviews_controller.rb:21-30` y `:58-59`
- BR-067 (aprobación transaccional del dependiente)
- El guard `household_admin_residency` se evalúa **antes** de abrir la transacción (bien), pero `verified_residence = household_admin_residency.verified_residence` en `:59` puede ser `nil` si esa `Residency` del admin no tiene `verified_residence` asociada (columna existe pero el dato podría faltar en registros legados / cambios de #94). Si es `nil`, `Residency.create!(verified_residence: nil ...)` lanza `RecordInvalid` (belongs_to obligatorio) y la transacción revierte — pero el `@dependent_request` ya fue marcado `approved` en `:33` dentro de la misma transacción, así que revierte correctamente. **Sin embargo no hay `rescue`**: el admin recibe un 500 sin contexto, a diferencia del guard de `household_admin` que sí redirige con aviso.
- Impacto: 500 no manejado en la ruta de aprobación de dependientes ante datos legados; UX degradada, sin log de negocio.
- Fix sugerido: validar `verified_residence.present?` junto al guard de `household_admin_residency` (mismo `redirect ... alert` antes de la transacción), replicando el patrón defensivo que ya existe para el admin faltante.

**[SEVERIDAD: Media]** `admin/members#create` puede crear un `Member` sin `neighborhood_association` verificable y sin `requested_by`/`approved_by`, y persiste `VerifiedIdentity` aunque falle el Member
- `app/controllers/admin/members_controller.rb:45-66`
- FALTA BR (creación manual de socios por admin no está cubierta por ninguna BR de onboarding)
- El flujo `create` guarda la `VerifiedIdentity` (`:51`) y **luego** intenta el `Member` (`:61`). Si `@member.save` falla, la `VerifiedIdentity` ya quedó persistida (no está en transacción). Además el `Member` se crea sin `status` explícito (queda el default de columna), sin `requested_by` ni `approved_by`, y sin `Residency`/`HouseholdUnit`. Esto crea un socio "huérfano" sin residencia por una vía que **no** es el onboarding revisado ni el flujo de administración (BR-132 sí contempla admin sin residencia, pero este es un alta manual arbitraria de cualquier RUN).
- Impacto: se pueden materializar identidades verificadas sin verificación documental real ni trazabilidad de quién las creó, contradiciendo el espíritu de BR-044 (cada junta verifica siempre) y BR-024 (transaccionalidad). Basura persistida si el Member falla.
- Fix sugerido: envolver `create`/`update` en `transaction do`; setear `requested_by`/`approved_by: current_user` y `status` explícito; y evaluar si esta ruta de alta manual debe existir o restringirse. Como mínimo, no dejar `VerifiedIdentity` colgada si el `Member` no se guarda.

**[SEVERIDAD: Media]** No hay tests del punto único de transferencia de identidad (`IdentityTransferService`) ni cobertura de la cascada por RUN duplicado en las dos rutas de aprobación
- `app/services/identity_transfer_service.rb` (sin `test/services/identity_transfer_service_test.rb`); `test/models/member_deactivation_test.rb` solo cubre `deactivate!` directo (líneas 33-50), no la desactivación del Member anterior al **aprobar** un onboarding/dependiente con RUN duplicado
- BR-057/058/059/069/095/096/099 (el invariante crítico de este dominio)
- La lógica de RUN duplicado **sí está implementada** correctamente en ambas rutas (`approve_step3:77-80` y `dependent_reviews#approve:53-56`, ambas antes de crear la nueva Residency, como exige el comentario del servicio). Pero es el invariante más delicado del área y no tiene ni un test que verifique: (a) que el `Member` anterior pasa a `inactive`, (b) que sus dependientes cascadan, (c) que ocurre dentro de la transacción de aprobación.
- Impacto: una regresión futura (p. ej. mover la llamada después de crear la Residency, que el propio comentario advierte que rompería la resolución del `household_admin`) pasaría inadvertida y reintroduciría el gap histórico de RUN duplicado.
- Fix sugerido: agregar tests de servicio + de controlador que aprueben un onboarding/dependiente cuyo RUN ya tenía un `Member(approved)` con dependientes, y asserten la cascada completa y su atomicidad.

**[SEVERIDAD: Media]** `VerifiedIdentity` no vuelve a normalizar/validar el RUN cuando `admin/members#create` lo asigna crudo
- `app/controllers/admin/members_controller.rb:46-49` vs `app/models/verified_identity.rb:35-40`
- BR-010/BR-012
- El controlador normaliza el RUN a mano (`normalize_run`, `:113-120`) y luego hace `verified_identity.run = run` **después** de `assign_attributes(...except(:run))`. El `before_validation :normalize_run_field` del modelo lo re-normaliza (idempotente, ok), pero la duplicación de la lógica de normalización de RUN existe en **cuatro** lugares (`VerifiedIdentity`, `IdentityVerificationRequest`, `Panel::OnboardingController#normalize_run`, `Admin::MembersController#normalize_run`) con implementaciones idénticas copiadas. No es un bug funcional hoy, pero cualquier ajuste (p. ej. manejar RUN de 6 dígitos) debe tocarse en 4 sitios y ya hay divergencia latente.
- Impacto: riesgo de inconsistencia de normalización entre modelos/controladores (BR-010 exige consistencia). Deuda que puede convertirse en bug de identidad.
- Fix sugerido: extraer la normalización de RUN a un único punto (concern `RunNormalizable` o método de clase en `RunValidator`) y usarlo en los cuatro lugares.

**[SEVERIDAD: Baja]** El teléfono se normaliza en `IdentityVerificationRequest`/`VerifiedIdentity` pero **no** se copia normalizado consistentemente, y `ResidenceVerificationRequest` no normaliza ningún campo de dirección
- `app/models/residence_verification_request.rb` (sin callbacks de normalización); `app/models/verified_identity.rb:19-29`
- BR-014 (normalización de nombres) — no hay regla equivalente para direcciones, pero sí un vacío
- `street_name`/`address_detail`/`number` se guardan tal cual los tipea el usuario (mayúsculas inconsistentes, espacios). Al aprobar, `approve_step3` copia estos valores crudos a `VerifiedResidence` y a `HouseholdUnit`, y el matching de domicilios existentes en `step3` (`:26-33`) compara `number` por igualdad exacta — `"12 "` vs `"12"` no matchea, creando `HouseholdUnit` duplicados para la misma dirección física (rompe la premisa 1:1 de `HouseholdUnit`).
- Impacto: domicilios físicos duplicados; el admin no ve el "domicilio existente" y crea uno nuevo, fragmentando `FamilyGroup` que deberían convivir (BR-040/BR-043).
- Fix sugerido: normalizar (`strip`, colapsar espacios, capitalizar `street_name`) en `ResidenceVerificationRequest`/`HouseholdUnit` y comparar `number` normalizado en el matching de `step3`. FALTA BR: agregar una regla de normalización de direcciones análoga a BR-014.

**[SEVERIDAD: Baja]** `Panel::DependentsController#index` y `Member#dependent_members` duplican una query frágil (SQL crudo de join) en lugar de un scope compartido
- `app/controllers/panel/dependents_controller.rb:21-27` y `app/models/member.rb:55-65`
- FALTA BR (calidad/mantenibilidad)
- Ambos construyen el mismo `INNER JOIN residencies ON residencies.verified_identity_id = verified_identities.id ... family_group_id ... neighborhood_association_id` a mano. Divergen sutilmente: el controlador filtra `neighborhood_association: current_user.neighborhood_association` mientras el modelo usa `neighborhood_association_id: neighborhood_association_id` del propio member — si el household_admin fuese admin de otra junta distinta de su residencia, darían resultados diferentes.
- Impacto: riesgo de que la lista de dependientes que ve el usuario difiera de la que el modelo considera para cascadas de desactivación (BR-099), dejando dependientes sin desactivar o mostrando dependientes ajenos.
- Fix sugerido: unificar en un solo scope de `Member` (p. ej. `Member.dependents_of_family_group(fg, association)`) usado por ambos.

---

#### Categorías limpias
- **Transaccionalidad de aprobaciones/envíos** (BR-017/024/067): `OnboardingRequest#submit!`/`cancel!`, `approve_step3` y `dependent_reviews#approve` están correctamente envueltos en `transaction do`. `reject` de onboarding también cascadea IVR/RVR transaccionalmente.
- **Cascada de desactivación por todas las rutas** (BR-034/037/096/099): `Member#deactivate!` centraliza la cascada a dependientes, y **todas** las rutas la invocan: `restart` (onboarding_controller:15), desactivación manual (`members#confirm_deactivate`), unirse a otra junta / transición a dependiente (vía `IdentityTransferService`), y desactivación de cuenta (`User#cascade_account_deactivation!`). No encontré ninguna ruta que ponga un Member en `inactive` saltándose `deactivate!`.
- **RUN duplicado en ambas rutas** (BR-057/059/069/095): el gap histórico **quedó cerrado** — `IdentityTransferService.deactivate_prior_memberships!` se llama en `approve_step3` y en `dependent_reviews#approve`, en ambos casos *antes* de crear la nueva `Residency`, con el reason correcto. Solo falta cobertura de tests (hallazgo arriba).
- **Validación RUN/teléfono** (BR-010/011/013): `RunValidator` (formato + DV módulo 11) y `PhoneValidator` correctos; verifiqué los edge cases de normalización de RUN y capitalización de nombres compuestos y funcionan.
- **`allow_blank` en validaciones de formato**: correcto en IVR (run/phone) y RVR ya no lo usa junto a presence (fix #93 confirmado).

Archivos relevantes: `/home/gfiguero/Proyectos/RubymineProjects/yuntapp/app/controllers/admin/members_controller.rb`, `/home/gfiguero/Proyectos/RubymineProjects/yuntapp/app/controllers/admin/dependent_reviews_controller.rb`, `/home/gfiguero/Proyectos/RubymineProjects/yuntapp/app/services/identity_transfer_service.rb`, `/home/gfiguero/Proyectos/RubymineProjects/yuntapp/app/models/residence_verification_request.rb`, `/home/gfiguero/Proyectos/RubymineProjects/yuntapp/app/controllers/panel/dependents_controller.rb`, `/home/gfiguero/Proyectos/RubymineProjects/yuntapp/app/models/member.rb`.

## Anexo — Ciclo de vida del certificado

_Agente `a96b87a5d6c21fd49`_

Interesting — `masked_run` for a RUN with a dash but non-standard body (e.g. a 6-digit or 5-digit RUN) always outputs `X.XXX.XXX-DV` regardless of the actual body length. For a legitimate short RUN (e.g. `123456-7`, some old RUNs), it would show `1.XXX.XXX-7` — masking is fine, but it's cosmetic. Not a real leak. The malformed test shows it returns the RAW run when there's no dash — that's a minor leak (returns full run) but only for malformed data that shouldn't exist post-validation. Low severity at most.

I have enough. Let me compile the findings.

### Hallazgos — Auditoría del ciclo de vida de ResidenceCertificate

He leído el código real (modelos, job, service PDF, los 4 controllers, webhook MP, vistas de verificación/panel, rutas y tests). El núcleo del flujo está sólido y bien cubierto por tests. Los hallazgos nuevos (excluyendo lo ya remediado #90–#127) son:

---

- **[SEVERIDAD: Alta]** La descarga del PDF se hace vía URL firmada de Active Storage sin expiración, evadible tras desactivación/vencimiento/reversión
  - `app/controllers/panel/residence_certificates_controller.rb:30`
  - BR-091 / BR-092 / BR-141
  - `download` valida `downloadable?` y luego hace `redirect_to rails_blob_path(pdf_document, disposition: "attachment")`. El storage es `:local` en producción (`config/environments/production.rb:27`) en modo **redirect**, y no hay `config.active_storage.urls_expire_in` configurado (default: nunca expira). La URL de blob resultante solo depende del `signed_id`, no de `current_user` ni de `downloadable?`. Un socio activo obtiene la URL, la guarda, y luego la reusa indefinidamente aunque después sea desactivado (BR-091), su certificado venza (BR-092) o el pago sea revertido (BR-141).
  - Impacto: se puede seguir descargando desde el backend un certificado que el sistema declara no descargable; rompe el enforcement de BR-091/092/141 en el canal de descarga (no solo el PDF ya guardado en disco del usuario, sino re-descargas frescas del servidor).
  - Fix sugerido: servir el PDF con `send_data`/streaming desde la propia acción `download` (tras `downloadable?`), o usar modo `:proxy` con expiración corta (`config.active_storage.urls_expire_in = 5.minutes`) — no exponer el blob redirect público.

---

- **[SEVERIDAD: Media]** Un certificado pagado en una junta sin RUT queda atascado en `paid` para siempre, sin emisión, sin refund y sin alerta al staff
  - `app/models/residence_certificate.rb:156` (guard en `issue!`) + `app/controllers/panel/residence_certificates_controller.rb` (sin guard) + `app/controllers/panel/payments_controller.rb` (sin guard) + `app/jobs/issue_certificate_job.rb`
  - BR-120 ("la emisión exige junta con RUT válido")
  - `issue!` correctamente aborta si `neighborhood_association.rut.blank?`, pero **nada impide crear la solicitud ni pagarla** cuando la junta no tiene RUT. No hay chequeo de RUT en `ResidenceCertificatesController#create/new` ni en `PaymentsController#new`, ni en el webhook `mark_certificate_paid`. Resultado: el webhook marca `paid`, se encola `IssueCertificateJob`, `issue!` lanza `"junta sin RUT"`, el job reintenta 3x (`retry_on StandardError, attempts: 3`) y se rinde. El cert queda `paid` permanentemente; BR-063 prohíbe devoluciones. `application_job.rb` no tiene `after_discard`/notificación, así que el staff ni se entera.
  - Impacto: el usuario paga y nunca recibe el certificado, sin refund y sin nadie notificado. Escenario real dado que existen juntas heredadas regularizándose (BR-121).
  - Fix sugerido: bloquear `create`/`payments#new` cuando `CertificatePricing.current_for` exista pero la junta no tenga RUT (o exigir RUT como precondición de definir precio); y añadir notificación al staff en la exhaustión del `IssueCertificateJob`.

---

- **[SEVERIDAD: Media]** `apply_mp_payment_status!` puede degradar a `pending_payment` un certificado que `IssueCertificateJob` está emitiendo concurrentemente (carrera revert vs. issue)
  - `app/models/residence_certificate.rb:128-140` y `app/jobs/issue_certificate_job.rb:16-18`
  - BR-141 / BR-073 / BR-008
  - `apply_mp_payment_status!` revierte a `pending_payment` solo si `paid?` (línea 131), sin lock. Pero entre el `mark_as_paid!` y el `issue!` del job hay una ventana: si un webhook de `refunded`/`charged_back` (contracargo, que puede llegar minutos después, no necesariamente tras `issued`) se procesa mientras el job aún ve el cert como `paid`, ambos operan sobre estado `paid` sin `with_lock`. `handle_non_approved` documenta explícitamente "read-then-write sin lock" (`mercadopago_controller.rb:341`). En SQLite las escrituras serializan, pero el orden no está garantizado: podría quedar `issued` con `payment_status=refunded` (comportamiento deseado, cubierto por `downloadable?`), o volver a `pending_payment` justo cuando el job hace `issue!` → el job relanza `RecordInvalid`/estado inconsistente.
  - Impacto: estado inconsistente en el borde reversión↔emisión; principalmente ruido/errores en logs, pero BR-141 asume transiciones limpias.
  - Fix sugerido: envolver `mark_as_paid!`/`issue!`/`apply_mp_payment_status!` en `with_lock` sobre el certificado para serializar las transiciones de estado.

---

- **[SEVERIDAD: Baja]** No existe BR que documente el bloqueo de solicitud/pago de certificado en juntas sin RUT (BR-120 solo cubre la emisión)
  - FALTA BR (o ampliar BR-120)
  - BR-120 dice "la emisión exige junta con RUT", pero el flujo permite solicitar y pagar antes de emitir. El comportamiento correcto (no cobrar por algo que no se podrá emitir) no está documentado como regla, lo que explica en parte el gap del hallazgo #2.
  - Impacto: ambigüedad de diseño; la precondición operacional queda implícita.
  - Fix sugerido: agregar una BR-14X ("No se puede iniciar la solicitud/pago de un certificado si la junta no tiene RUT válido — precondición de BR-120, evita cobros sin emisión posible").

---

- **[SEVERIDAD: Baja]** `masked_run` devuelve el RUN **completo sin enmascarar** cuando el `run` no contiene guión
  - `app/models/residence_certificate.rb:96-102`
  - BR-078 ("RUN parcialmente oculto en verificación pública")
  - Si `raw.split("-")` no produce `dv` (RUN sin guión), `return raw` en la línea 98 expone el valor completo. El propio test lo confirma: `"masked_run returns nil when run is malformed"` en realidad afirma `assert_kind_of String` y comenta "retorna el raw". Post-normalización (BR-010) el RUN siempre lleva guión, así que en la práctica no debería ocurrir; pero es un fallback que viola BR-078 ante datos legacy/malformados en vez de fallar cerrado.
  - Impacto: fuga potencial del RUN completo en la página pública para registros con RUN mal formado.
  - Fix sugerido: en lugar de `return raw`, devolver un placeholder enmascarado o `nil` cuando el formato no permita enmascarar.

---

- **[SEVERIDAD: Baja]** Gap de test: no se cubre el escenario "certificado pagado en junta sin RUT queda atascado en `paid`"
  - `test/jobs/issue_certificate_job_test.rb` / `test/models/residence_certificate_test.rb`
  - BR-120
  - Existe el test de modelo `"issue! falla si la junta no tiene rut (BR-120)"` (línea 505), pero no hay test a nivel de job/controller que verifique el comportamiento end-to-end (job se rinde, cert permanece `paid`, no se emite) ni que exista mitigación. Es el invariante crítico detrás del hallazgo #2.
  - Impacto: la regresión de "cobro sin emisión posible" pasaría desapercibida.
  - Fix sugerido: agregar test de `IssueCertificateJob` con junta sin RUT que asegure que el cert queda `paid` sin PDF y (tras el fix) que se notifica al staff.

---

Categorías sin hallazgos nuevos:
- **Folios/tokens/códigos duplicables**: correcto — retry con índice único (#98), `generate_validation_code` con reintentos y unicidad DB, `validation_token` UUID único. Bien cubierto.
- **Cálculo de fee/vencimiento**: correcto — `platform_fee` redondeado (#99), `VALIDITY_PERIOD = 30.days` (BR-023).
- **Emisión sin pago / PDF regenerado**: correcto — `issue!` exige `paid?`, job idempotente re-adjunta PDF solo si falta, `immutable_once_issued` protege campos.
- **Fugas de verificación pública** (más allá del masked_run legacy): correcto — `findable_publicly` filtra a `issued`, precedencia revoked &gt; reverted &gt; expired en la vista, 200 para vencidos, 404 solo para inexistentes/no-issued, rate limiting presente. Bien cubierto.

Los archivos clave revisados (rutas absolutas): `/home/gfiguero/Proyectos/RubymineProjects/yuntapp/app/models/residence_certificate.rb`, `/app/jobs/issue_certificate_job.rb`, `/app/services/certificate_pdf_service.rb`, `/app/controllers/panel/residence_certificates_controller.rb`, `/app/controllers/panel/payments_controller.rb`, `/app/controllers/webhooks/mercadopago_controller.rb`, `/app/controllers/verifications_controller.rb`, `/app/views/verifications/show.html.erb`, `/app/views/panel/residence_certificates/show.html.erb`.

## Anexo — Administración de juntas y marketplace

_Agente `a9e524d77bfcd2814`_

Confirmed. The public marketplace index shows all listings regardless of `publication_status`, leaking unpaid `pending_payment` listings publicly. This is my highest-severity finding for the marketplace.

I have thorough evidence across all areas. Here is my audit report.

---

## Auditoría: Onboarding de Administración (AdministrationRequest) + Marketplace (Listing)

### Hallazgos ordenados por severidad

---

#### [SEVERIDAD: Alta] La vitrina pública del marketplace expone publicaciones no pagadas (`pending_payment`)
- **Archivo:** `app/controllers/listings_controller.rb:41-43` (`set_listings` → `Listing.all`); vista `app/views/listings/index.html.erb:13`; ruta pública `config/routes.rb:21` (`resources :listings, only: [:index, :show]`)
- **BR relacionada:** BR-083 (solo `published` con pago aprobado es visible; `pending_payment → published`)
- **Qué está mal:** El controller público arma `@listings = Listing.all` sin aplicar el scope `published` (`Listing.published`, definido en `listing.rb:33`). No filtra por `publication_status` ni por `published_until`. Un usuario crea un listing (`Panel::ListingsController#create`) que nace en `pending_payment` (default de columna, `schema.rb:189`) y aparece de inmediato en `/listings` sin haber pagado. `#show` también permite ver cualquier listing por id sin restringir estado.
- **Impacto:** Se anula el modelo de negocio del marketplace: cualquiera publica gratis y su aviso es visible sin pagar la habilitación (BR-083/BR-084). Además muestra publicaciones vencidas (`published_until &lt; today`).
- **Fix sugerido:** En `set_listings` usar `Listing.published` como base (y en `set_listing`/`show` validar `published?` o usar `Listing.published.find`). El scope ya existe: `scope :published, -&gt; { where(publication_status: "published").where("published_until &gt;= ?", Date.current) }`.

---

#### [SEVERIDAD: Alta] Borrado físico de publicaciones viola BR-100 (panel y admin)
- **Archivo:** `app/controllers/panel/listings_controller.rb:70-73` (`@listing.destroy!`); `app/controllers/admin/listings_controller.rb:53-56` (`@listing.destroy!`)
- **BR relacionada:** BR-100 (ningún dato consolidado se destruye; publicaciones incluidas explícitamente en la lista)
- **Qué está mal:** Ambos controllers exponen `DELETE` con `destroy!` real. BR-100 nombra "publicaciones" como dato que "debe sobrevivir a … 'borrados'". `Listing` sí tiene `has_many :payment_events, dependent: :restrict_with_error` (`listing.rb:19`), lo que bloquea el destroy de un listing que ya pagó (bueno), pero un listing con historial de pagos revertidos o uno `published` sin `payment_events` correspondientes igual desaparece con su snapshot de junta, `amount`, `platform_fee`, `paid_at`. No hay guard `before_destroy` en `Listing` (a diferencia de `Member`/`User` que sí lo tienen para BR-100/BR-101).
- **Impacto:** Se pierde historial financiero (comisión retenida, junta beneficiaria snapshot BR-085) de forma irreversible. Inconsistente con el patrón de desactivación (`active: false`) usado en el resto del sistema.
- **Fix sugerido:** Reemplazar `destroy!` por desactivación (`update!(active: false)` o despublicación), o agregar guard `before_destroy` en `Listing` que aborte, alineado con `Member`/`User`. Como mínimo, el `dependent: :restrict_with_error` debería cubrir todo listing con historial de pago.

---

#### [SEVERIDAD: Media] La aprobación de administración no exige junta `active`; puede aprobar hacia una junta disuelta
- **Archivo:** `app/services/administration_approval_service.rb:40-48` (`resolve_association!`), `26-34` (`approve!`)
- **BR relacionada:** BR-054/BR-055 (junta disuelta = `active: false`), BR-120 (junta debe estar constituida para operar)
- **Qué está mal:** `resolve_association!` devuelve `@req.neighborhood_association` sin validar `active?`. El formulario del panel (`build_cascading_data`, `panel/administration_requests_controller.rb:70`) sí filtra con `.active`, pero un `neighborhood_association_id` de una junta inactiva puede llegar por param manipulado o por una junta que se disolvió entre el `submit!` y el `approve` del staff. Al aprobar, el `User` queda `admin: true` de una junta `inactive`, se crea `Member(approved)` y `BoardMember(active)` sobre una junta disuelta, sin reactivarla ni advertir.
- **Impacto:** Admin operando una junta que el superadmin marcó como disuelta (contradice BR-054). El nuevo `Member(approved)` en una junta inactiva rompe la premisa de que la disolución cascadea todos los members a `inactive`.
- **Fix sugerido:** En `approve!` (o `resolve_association!`), `raise` si `junta&amp;.inactive?`. Añadir test.

---

#### [SEVERIDAD: Media] Faltan las advertencias al staff exigidas por BR-139 (nombre duplicado) y BR-140 (cargo ocupado)
- **Archivo:** `app/views/superadmin/administration_requests/show.html.erb:14-23` (solo hay `warn_existing_admin` BR-130 y `warn_duplicate_run` BR-129)
- **BR relacionada:** BR-139 (junta nueva con nombre+comuna igual a existente → advertencia), BR-140 (cargo ya ocupado por `BoardMember` activo → advertencia)
- **Qué está mal:** La vista de decisión del staff no calcula ni muestra:
  - BR-139: si `new_association?` y existe otra `NeighborhoodAssociation` con mismo `name`+`commune_id`.
  - BR-140: si ya existe `BoardMember` activo con ese `position` en la junta objetivo.
  No hay `helper_method` ni lógica en el controller para estos dos casos (solo `requires_run_confirmation?`).
- **Impacto:** El staff aprueba a ciegas: puede crear una junta duplicada (dos "Junta X" en la misma comuna) o duplicar un presidente activo, ambos escenarios que las BR piden señalar. La aprobación de `BoardMember` usa `find_or_create_by!` por `(junta, member, position, active:true)` (`administration_approval_service.rb:88-93`), así que **sí** se crearía un segundo presidente activo sin desplazar al vigente (consistente con BR-140 "no desplaza"), pero sin la advertencia previa.
- **Fix sugerido:** Agregar `helper_method`s `possible_duplicate_association?` y `position_already_taken?` en el controller y renderizar alerts en la show, espejando el patrón de `warn_existing_admin`.

---

#### [SEVERIDAD: Media] No se advierte al solicitante ni al staff la consecuencia del acoplamiento (BR-137) antes de aprobar
- **Archivo:** `app/views/superadmin/administration_requests/show.html.erb` (sin alerta BR-137); `app/views/panel/administration_requests/*` (grep sin resultados de "desactiv"/"consecuencia"); ejecución sí ocurre en `administration_approval_service.rb:69-73`
- **BR relacionada:** BR-137 ("El sistema **advierte** al solicitante y al staff de esta consecuencia antes de aprobar")
- **Qué está mal:** La *ejecución* de la cascada existe y es correcta: `deactivate_prior_memberships!` desactiva los `Member.approved` en OTRAS juntas (`administration_approval_service.rb:70`). Pero BR-137 exige **advertir** antes de aprobar cuando el dirigente ya es socio activo de otra junta (invalida certificados BR-091, cascadea dependientes BR-099). Ni la show del staff ni la vista/summary del panel muestran este aviso. Solo se advierte el caso RUN duplicado (BR-129), que es distinto.
- **Impacto:** El staff aprueba sin saber que desactivará al socio en su junta original e invalidará sus certificados; el solicitante tampoco es advertido. Efecto irreversible-para-el-usuario ejecutado en silencio.
- **Fix sugerido:** Calcular `applicant_active_elsewhere?` (existe `identity.members.approved.where.not(association: junta)`) y mostrar alerta en la show del staff y en el summary del panel antes de enviar/aprobar.

---

#### [SEVERIDAD: Baja] BR-136 dice "FK único `User.neighborhood_association_id`" pero el índice NO es único
- **Archivo:** `db/schema.rb:380` — `index_users_on_neighborhood_association_id` **sin** `unique: true`
- **BR relacionada:** BR-136 (texto CLAUDE.md: "FK único `User.neighborhood_association_id`")
- **Qué está mal:** El invariante real "un usuario administra a lo más una junta" **sí** se cumple porque `neighborhood_association_id` es una columna escalar (un usuario apunta a una sola junta). Pero la BR describe un "FK único", lo que sugeriría "un admin por junta" — eso no está enforced y **de hecho no debe estarlo** (BR-052/BR-130 permiten co-admins). La redacción de la BR es engañosa; no hay bug de datos, sino inconsistencia doc↔schema.
- **Impacto:** Bajo. Ninguna violación de datos; solo confusión: alguien podría intentar añadir un índice único (rompería co-admins BR-052).
- **Fix sugerido:** Corregir la redacción de BR-136 en CLAUDE.md: el enforcement de "una junta por usuario" es por columna escalar + guard de aplicación (`redirect_if_admin` + `only_one_active_per_user`), NO por índice único. No agregar índice único.

---

#### [SEVERIDAD: Baja] `only_one_active_per_user` tiene un TOCTOU sin índice único que lo respalde (BR-134)
- **Archivo:** `app/models/administration_request.rb:86-91`; enforcement de UI en `panel/administration_requests_controller.rb:54-55`
- **BR relacionada:** BR-134 (a lo más una solicitud `draft`/`pending` por usuario)
- **Qué está mal:** La unicidad de "una solicitud activa" se valida solo a nivel de modelo (`only_one_active_per_user`) y con un `redirect_if_active_request` en el controller. No hay índice único parcial en BD (`where status IN ('draft','pending')`) como sí lo tienen `certificate_pricings`/`listing_pricings` (`schema.rb:98,172`). Dos requests concurrentes (doble submit) podrían crear dos solicitudes `pending`.
- **Impacto:** Bajo (ventana de carrera estrecha, requiere doble POST casi simultáneo). Duplica solicitudes activas del mismo usuario.
- **Fix sugerido:** Índice único parcial en `administration_requests(user_id) WHERE status IN ('draft','pending')`, espejando `index_..._one_current_per_association`.

---

#### [SEVERIDAD: Baja] `resolve_identity!` sobrescribe nombre/apellido/teléfono/email de una identidad verificada existente sin resguardo (BR-129/ADR-006)
- **Archivo:** `app/services/administration_approval_service.rb:50-65`
- **BR relacionada:** BR-129/ADR-006 (transferencia por RUN duplicado con confirmación del staff)
- **Qué está mal:** `find_or_initialize_by(run:)` + `assign_attributes(first_name/last_name/phone/email)` + `save!` machaca los datos de una `VerifiedIdentity` **ya verificada** con los del formulario del solicitante, incluso cuando el checkbox `confirm_duplicate_run` fue marcado. El checkbox (BR-129) gatea la *aprobación*, pero una vez confirmado, se pisan first/last/phone/email de la identidad original y su `email` pasa a ser el del `@req.user`. La confirmación es correcta como gate; el efecto de sobrescritura total es agresivo y no reutiliza `IdentityTransferService` (que existe: `app/services/identity_transfer_service.rb`).
- **Impacto:** Datos de la identidad histórica alterados con lo que declaró el solicitante (podría ser distinto). Aceptable si BR-129 lo intenta ("transfiere/sobrescribe" según comentario línea 18), pero conviene verificar que sea el comportamiento deseado y no divergir de `IdentityTransferService`.
- **Fix sugerido:** Confirmar la intención con el owner; considerar delegar la transferencia a `IdentityTransferService` para un único punto de verdad del reemplazo de identidad por RUN duplicado.

---

### Áreas limpias verificadas

- **Transaccionalidad BR-128 (Alta prioridad, OK):** `AdministrationApprovalService#approve!` envuelve *todo* (crear/enlazar junta + identidad + member + board_member + `User.admin`) en `ActiveRecord::Base.transaction` (`administration_approval_service.rb:26-34`). El controller captura `RecordInvalid` y revierte (`superadmin/administration_requests_controller.rb:30-32`). Atómico y correcto.
- **RUT BR-119/BR-121 (OK):** normalización (`normalize_rut`) + DV módulo 11 (`run:` validator) + `presence` + `uniqueness` en modelo (`neighborhood_association.rb:6-10`), respaldados por `rut null: false` + índice único en schema (`schema.rb`). `resolve_association!` siempre pasa `rut: @req.organization_rut` al crear, que a su vez fue validado `on: pending` en `AdministrationRequest`. No encontré ruta que cree junta sin RUT.
- **Confirmación RUN duplicado BR-129 (OK):** el guard `requires_run_confirmation?` + chequeo `params[:confirm_duplicate_run] != "1"` bloquea la aprobación con redirect antes de llamar al service (`superadmin/administration_requests_controller.rb:20-24`); el checkbox es `required: true` en la vista.
- **BR-130 (OK):** `notify_existing_admin` a todos los admins vigentes de la junta objetivo en `#create` (`panel/administration_requests_controller.rb:59-66`) + alerta `warn_existing_admin` en la show del staff.
- **BR-133 (OK):** `AdministrationRemindersJob` (recurrente `every day at 8am` en `recurring.yml`) → `staff_digest` a todos los superadmins con las `pending`.
- **BR-137 ejecución de cascada (OK):** desactivación *selectiva* correcta — solo `Member.approved` en OTRAS juntas (`where.not(neighborhood_association_id: junta.id)`), reutilizando la de la misma junta vía `find_or_initialize_by` (`administration_approval_service.rb:69-85`). (La *advertencia* es lo que falta — ver hallazgo Media arriba.)
- **Snapshot de precio inmutable Listing #109/BR-085 (OK):** `pricing_snapshot_immutable_while_published` mira el estado persistido y permite re-captura solo si vencida (`listing.rb:31,134-141`). Correcto.
- **Category/Tag BR-100 (OK):** `Category has_many :listings, dependent: :nullify` (no destruye avisos al borrar taxonomía). `Tag` sin asociaciones destructivas.
- **Admin listings multi-tenant BR-007 (OK):** `set_listing`/`set_listings` scopeados a `current_neighborhood_association.listings`; params sin `:user_id` (no reasigna dueño).

**Resumen ejecutivo:** dos hallazgos Alta en el marketplace (vitrina pública filtra sin `published` → BR-083, y `destroy!` físico → BR-100). En administración, la maquinaria transaccional (BR-128/129) es sólida; los gaps son de **advertencias faltantes al staff** (BR-137/139/140) y falta de chequeo de junta `active` al aprobar (BR-054).

## Anexo — Multi-tenant y autorización

_Agente `ae08e9413a2492bf4`_

Pricing controllers force `neighborhood_association: current_neighborhood_association` and only permit `:price`. Safe. 

I have enough to finalize. Let me confirm the dependents deactivation gap once more against the `member` method: `current_user.neighborhood_association` is the raw FK, not derived from active Member — so it stays set after Member deactivation. Confirmed earlier. Here is my audit.

---

### Auditoría de aislamiento multi-tenant, autorización y control de acceso

Revisé los tres namespaces (`admin`, `panel`, `superadmin`), los controllers top-level, la impersonation y los strong params. El scoping por `current_neighborhood_association` en admin y por `current_user` en panel es sólido y consistente en la gran mayoría de recursos. Encontré 3 hallazgos nuevos (ninguno de los ya remediados en batches previos).

---

#### [SEVERIDAD: Media] IDOR / mass-assignment de `member_id` ajeno en la directiva
- **Archivo**: `app/controllers/admin/board_members_controller.rb:82-85` + `app/models/board_member.rb:6-10`
- **BR**: BR-007 (aislamiento multi-tenant), BR-100/BR-138 (integridad de directiva)
- **Qué está mal**: `board_member_params` permite `:member_id` y hace `.merge(neighborhood_association_id: current_neighborhood_association.id)`, pero ni el controller ni el modelo `BoardMember` validan que el `member` pertenezca a esa junta. El `&lt;select&gt;` del form (`_form.html.erb:5`) sí está acotado a `current_neighborhood_association.members`, pero es solo defensa en el cliente. Un POST manipulado con un `member_id` de otra junta se guarda sin error (el modelo solo valida `position`/`start_date`).
- **Impacto**: Un admin autenticado puede crear un `BoardMember` en su propia junta apuntando al `Member` de otra junta. Los datos de identidad del socio ajeno (`member.name`/`run` vía `verified_identity`) se filtran y renderizan en las vistas de directiva de esta junta e incluso en la vista pública del socio (`panel/neighborhood_association#show`, línea 17-19, que lista `board_members.active` con `member: :verified_identity`). Viola BR-007.
- **Fix sugerido**: Validar pertenencia en el modelo — `validate` que `member.neighborhood_association_id == neighborhood_association_id`; o en el controller resolver `@member = current_neighborhood_association.members.find(params.dig(:board_member, :member_id))` y asignarlo, quitando `:member_id` de los params permitidos.

---

#### [SEVERIDAD: Media] Socio desactivado (BR-036) sigue registrando dependientes
- **Archivo**: `app/controllers/panel/dependents_controller.rb:4-9, 36-44, 62-66`
- **BR**: BR-091 / BR-099 (la desactivación del `Member` debe cortar el acceso operativo)
- **Qué está mal**: El único guard de escritura es `ensure_household_admin!`, que se apoya en `current_user.household_admin?` → `residency&amp;.household_admin?` (`app/models/user.rb:60-62`). Tras `Member#deactivate!` (BR-036) la `Residency` **no** cambia de estado (BR-038: no existe `inactive` en `Residency`), así que `household_admin?` sigue devolviendo `true`, y `current_user.neighborhood_association` (FK cruda en `users`, no derivada del Member activo) permanece seteada. A diferencia de `Panel::ResidenceCertificatesController` (que sí exige Member aprobado vía `ensure_active_member!`) y de `Panel::NeighborhoodAssociationController` (que usa `current_user.member`, solo activo), `dependents` no verifica Member activo.
- **Impacto**: Un socio que el admin desactivó (BR-036) puede seguir accediendo a `panel/dependents` y **crear nuevas `IdentityVerificationRequest(dependent: true)`** en la junta que lo dio de baja. Peor: al aprobarlas el admin, `DependentReviewsController#approve` crea un `Member(approved)` nuevo, reestableciendo presencia activa de un socio desactivado. El corte de acceso de BR-091/BR-099 se elude por esta ruta. (Nota relacionada: el `User` sigue pudiendo iniciar sesión porque `Member#deactivate!` no toca `User.deactivated_at`; esto es correcto por diseño, pero hace que el gate por Member activo sea imprescindible en cada acción de escritura del panel.)
- **Fix sugerido**: Añadir `before_action :ensure_active_member!` en `DependentsController` (mismo patrón que `residence_certificates`): exigir `current_user.verified_identity&amp;.members&amp;.approved&amp;.exists?(neighborhood_association: current_user.neighborhood_association)` antes de `index`/`new`/`create`.

---

#### [SEVERIDAD: Baja] Controller `Admin::UsersController` sin ruta pero con violación latente de BR-093 y toggle `admin`
- **Archivo**: `app/controllers/admin/users_controller.rb:59, 75` + `config/routes.rb:207-281` (no hay `resources :users` en el namespace `admin`)
- **BR**: BR-093 (email inmutable), BR-052/BR-122 (gobernanza de admins)
- **Qué está mal**: El controller implementa `create`/`update` con `user_params` que permite `:email` y `:admin`, hace `@user.update(user_params)` y tiene vista `edit` con campo de email editable y checkbox `admin` (`app/views/admin/users/_form.html.erb:19, 43`). BR-093 solo se hace cumplir en `Users::RegistrationsController#discard_email_param`; **no existe guard a nivel de modelo** que impida cambiar el email (verificado en `app/models/user.rb`: sin `readonly`/`before_update`). Si estuviera ruteado, un admin podría cambiar el email de cualquier usuario de su junta (viola BR-093) y otorgar/quitar el flag `admin` (parte de la gobernanza que UC-008/BR-122 reservan al staff).
- **Impacto**: Actualmente **no explotable**: no hay ruta que apunte a `Admin::UsersController` (el `resources :users` de la línea 185 está dentro del namespace `superadmin`, no `admin`). Es código muerto con una violación latente que se activaría si alguien agrega `resources :users` al bloque `namespace :admin`.
- **Fix sugerido**: Eliminar el controller y sus vistas (`app/controllers/admin/users_controller.rb`, `app/views/admin/users/*`) si no se usan; o, si se piensa exponer, quitar `:email` de `user_params` y, defensivamente, agregar en el modelo `User` un guard server-side de inmutabilidad del email (`attr_readonly :email` o revertir en `before_update`) para no depender de que cada controller recuerde descartarlo.

---

#### Áreas revisadas y limpias
- **Impersonation**: solo se setea en `Superadmin::NeighborhoodAssociationsController#impersonate` (tras `ensure_superadmin!`) y solo se consume si `current_user.superadmin?` (`admin/application_controller.rb:20`). Un no-superadmin que fuerce la sesión es ignorado. Sin abuso.
- **Herencia de guards**: todos los `admin/*` y `superadmin/*` (incluidos los declarados como `&lt; ApplicationController` a secas, ej. `admin/users`, `admin/listings`, `superadmin/dashboard`) resuelven por lookup de constante al `ApplicationController` hermano del módulo, heredando `ensure_neighborhood_admin!`/`ensure_superadmin!`. Verificado.
- **Scoping IDOR en admin**: `members`, `residence_certificates`, `household_units`, `neighborhood_delegations`, `listings`, `onboarding_requests`, `onboarding_reviews`, `dependent_reviews`, `verifications`, `certificate_pricings`, `listing_pricings` — todos `find` a través de `current_neighborhood_association.*` o joins por `neighborhood_association_id`. Sin fugas entre juntas.
- **Panel**: `listings`, `payments`, `listing_payments`, `listing_subscriptions`, `residence_certificates`, `neighborhood_association`, `profile`, `onboarding` — scopeados por `current_user`; los que hacen pagos/certificados exigen Member activo. `profile` es solo lectura (BR-093/094 OK).
- **Top-level**: `listings`/`categories`/`tags`/`neighborhood_associations` son solo `index/show/search` (públicos read-only, #115); `reactivations` gatea `deactivated? &amp;&amp; !blocked?`; `verifications` usa el scope `find_for_public_verification` (BR-081). Sin escritura indebida.
- **Pricing controllers**: fuerzan `neighborhood_association: current_neighborhood_association` y solo permiten `:price`. Sin mass-assignment.

Los dos hallazgos accionables reales son el **#1 (board_members member_id ajeno)** y el **#2 (dependientes por socio desactivado)**. El #3 es latente (sin ruta) pero conviene limpiarlo.

## Anexo — Consistencia documentación ↔ código

_Agente `a8cfd566246ee9b98`_

The subagent confirmed all i18n keys and UC routes are present — no findings there. My audit is complete. Here are the desalineaciones found, ordered by severity.

---

### Auditoría de coherencia documentación↔código — hallazgos

#### [SEVERIDAD: Alta] `restart` de onboarding destruye físicamente una solicitud `pending` (viola BR-018/BR-047/BR-100)
- CLAUDE.md BR-018 ("se **cancela** la solicitud pendiente") / BR-047 / BR-100 ↔ `app/controllers/panel/onboarding_controller.rb:14` + `app/models/onboarding_request.rb:7-8` + `app/models/user.rb:33`
- Evidencia: `restart` ejecuta `current_user.current_onboarding_request&amp;.destroy`. La asociación `current_onboarding_request` está definida como `-&gt; { where(status: ["draft", "pending"]) }` (user.rb:33), es decir **incluye solicitudes `pending`**. `OnboardingRequest` declara `has_one :identity_verification_request, dependent: :destroy` y `has_one :residence_verification_request, dependent: :destroy`. Por tanto, si un usuario con una solicitud ya enviada (`pending`, en revisión del admin) pulsa "Reiniciar Onboarding" (`app/views/layouts/panel.html.erb:90`, expuesto en el panel), se **borran físicamente** el `OnboardingRequest` + su `IdentityVerificationRequest` + su `ResidenceVerificationRequest`. BR-018 dice explícitamente "se cancela" (no "se elimina"), y el modelo ya tiene un método `cancel!` (onboarding_request.rb) hecho exactamente para esto. BR-100 exige que ningún dato consolidado se destruya.
- Impacto: pérdida de datos en vuelo y de auditoría; contradice el invariante central BR-100 y la letra de BR-018. Es el mismo patrón de "borrado destructivo" que la auditoría #90/BR-100 buscaba erradicar.
- Fix sugerido (código): en `restart`, si la solicitud está `pending`, invocar `cancel!` en lugar de `destroy`; solo permitir `destroy` cuando esté en `draft`. Alternativamente cambiar `current_onboarding_request` para no incluir `pending` en el path de restart. Además revisar si `dependent: :destroy` en OnboardingRequest debe pasar a `:restrict_with_error`/`:nullify` para requests no-draft.

#### [SEVERIDAD: Alta] Geografía se destruye en cascada — `Country/Region/Commune#destroy` viola BR-100
- CLAUDE.md BR-100 ("Ningún dato consolidado se destruye", enumera juntas como dato a preservar) ↔ `app/models/country.rb:4`, `app/models/region.rb:3`, `app/controllers/superadmin/{countries,regions,communes}_controller.rb:69`
- Evidencia: `Country has_many :regions, dependent: :destroy` y `Region has_many :communes, dependent: :destroy`. Los tres controllers superadmin tienen `@region.destroy!` / `@commune.destroy!` / `@country.destroy!` sin guard. `Commune` (commune.rb:3-4) tiene `has_many :neighborhood_associations` y `has_many :household_units` **sin `dependent:` alguno**. Consecuencia: destruir un país cascadea a regiones → comunas, y una comuna con juntas asociadas rompe la FK (`neighborhood_associations.commune_id`) o deja huérfanos datos consolidados (juntas, domicilios). A diferencia de `NeighborhoodAssociation` (que sí usa `dependent: :restrict_with_error` en toda su historia), la rama geográfica no está protegida.
- Impacto: un superadmin puede borrar en cascada regiones/comunas y con ellas arrastrar/orfanar juntas, delegaciones y domicilios — exactamente lo que BR-100 prohíbe.
- Fix sugerido (código): cambiar `dependent: :destroy` por `:restrict_with_error` en `Country→regions` y `Region→communes`; agregar `has_many :neighborhood_associations, dependent: :restrict_with_error` (y `:household_units`) en `Commune`; o eliminar las acciones `destroy` de los tres controllers superadmin (patrón `except: [:destroy]` como en `members`). Considerar documentar como nueva BR el enforcement de no-borrado geográfico.

#### [SEVERIDAD: Media] Modelo de Datos: `VerifiedIdentity` documenta campos/estados que no existen
- CLAUDE.md sección "Modelo de Datos → VerifiedIdentity" ("Campos: `first_name`, `last_name`, `run`, `phone`, `email`, `verification_status`. Status: pending | verified | rejected. Callbacks: `normalize_run_field`…") ↔ `db/schema.rb:385-396` + `app/models/verified_identity.rb`
- Evidencia: la tabla `verified_identities` **no tiene columna `verification_status`** (columnas reales: `first_name`, `last_name`, `run`, `phone`, `email`, `identity_verification_request_id`). El modelo no define ningún estado ni `verification_status`; el estado de verificación vive en `Member.status` (pending/approved/rejected/inactive). La doc describe un modelo de estados obsoleto.
- Impacto: confunde a cualquier desarrollador/agente que asuma un `verification_status` en `VerifiedIdentity` (código muerto imaginario, queries que fallarían).
- Fix sugerido (doc): eliminar `verification_status` y la línea "Status: pending | verified | rejected" de la descripción de `VerifiedIdentity`; aclarar que el ciclo de verificación se refleja en `Member`.

#### [SEVERIDAD: Media] Columna/asociación `approved_by` en `ResidenceCertificate` es vestigial y contradice BR-062/BR-077
- CLAUDE.md BR-062/BR-064/BR-077 (emisión automática, sin aprobación de admin, sin estados approved/rejected) ↔ `db/schema.rb:284` (`approved_by_id`), `app/models/residence_certificate.rb:18`, `app/models/user.rb:36`, `app/views/admin/residence_certificates/_residence_certificate.html.erb:32-33`
- Evidencia: persiste la columna `residence_certificates.approved_by_id` + `belongs_to :approved_by` + `User#approved_certificates` + se muestra en la vista admin (`approved_by&amp;.email`). Un `grep` confirma que **nunca se asigna** en ningún flujo (el certificado se emite automáticamente vía `issue!`/`IssueCertificateJob`). Es un residuo del flujo con aprobación de admin ya eliminado.
- Impacto: columna muerta que sugiere una semántica de "aprobador" inexistente; la vista admin muestra siempre "—". Riesgo de confusión y de UI engañosa.
- Fix sugerido: eliminar la asociación/columna (migración drop_column con expand-contract) y la fila de la vista; o, si se conserva por historia, documentarlo explícitamente como campo sin uso en el flujo actual.

#### [SEVERIDAD: Baja] Modelo de Datos: estados de `IdentityVerificationRequest`/`OnboardingRequest` omiten `cancelled`
- CLAUDE.md "Modelo de Datos → IdentityVerificationRequest" ("Status: draft | pending | approved | rejected") y "OnboardingRequest" ("Status: draft | pending | approved | rejected") ↔ `app/models/identity_verification_request.rb:10` y `app/models/onboarding_request.rb` (STATUSES)
- Evidencia: ambos modelos incluyen `cancelled` en `STATUSES` (`%w[draft pending approved rejected cancelled]`), añadido por BR-051. La sección Modelo de Datos no lo lista (aunque BR-051/BR-126 sí lo mencionan).
- Impacto: menor; inconsistencia interna de la doc entre la tabla de BRs y la sección Modelo de Datos.
- Fix sugerido (doc): añadir `cancelled` a la enumeración de estados de ambos en la sección Modelo de Datos.

#### [SEVERIDAD: Baja] Modelo de Datos cita `generate_folio!` como método público inexistente
- CLAUDE.md "Modelo de Datos → ResidenceCertificate" ("`generate_folio!`: formato 'CR-{association_id}-{sequence}'") ↔ `app/models/residence_certificate.rb:146-216`
- Evidencia: no existe un método público `generate_folio!`. El folio se calcula dentro de `issue!` mediante `next_folio` (privado, con reintento ante colisión, `FOLIO_MAX_ATTEMPTS`). El formato documentado sí es correcto.
- Impacto: mínimo; referencia a un nombre de método que no existe (posible confusión al buscarlo).
- Fix sugerido (doc): reemplazar "`generate_folio!`" por "el folio se genera en `issue!` vía `next_folio`".

---

**Verificado como correcto (sin hallazgos):** `Member#deactivate!` + cascada + guard `before_destroy` (BR-037/BR-099/BR-100); `NeighborhoodAssociation#deactivate!` con `dependent: :restrict_with_error` en toda su historia (BR-054/BR-100); `ResidenceCertificate#apply_mp_payment_status!`, `payment_reverted?`, `holder_deactivated?`, `downloadable?`, `payment_status` (BR-141/BR-091); `Listing` espejo (BR-088/BR-089, `SUBSCRIPTION_STATUSES`); `OnboardingRemindersJob`/`AdministrationRemindersJob` + `recurring.yml` (BR-050/BR-133); `VALIDATION_CODE_ALPHABET` sin 0/O/1/I (BR-074); `VALIDITY_PERIOD = 30.days` (BR-023); `IssueCertificateJob` 3 retries (BR-076); `mercadopago_email` validación (BR-142); `User` `generates_token_for(:account_reactivation)` + guards de no-destrucción (BR-101); `admin/members` sin `destroy` (BR-100); todas las claves i18n de pago/onboarding presentes; y todas las rutas de UC-003..UC-008 existentes.
