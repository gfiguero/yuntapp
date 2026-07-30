# Confirmación de email de MercadoPago para suscripciones — Diseño

**Fecha:** 2026-07-30
**Rama:** `worktree-feat-mercadopago-email-suscripcion`

## Problema

La auto-renovación de publicaciones (preapproval de MP, BR-088) envía `payer_email: current_user.email`.
La doc oficial de MP establece que en las **suscripciones sin plan asociado**, durante el pago se valida
que el email del pagador coincida con el `payer_email` declarado — si no coinciden, el cobro se rechaza.
Un socio cuyo email de MercadoPago difiere del de yuntapp ve su suscripción fallar (en sandbox, un email
que no es test user hace fallar la creación misma con un 500 críptico). El email de yuntapp es el de login
y es **inmutable** (BR-093), así que no puede cambiarse para coincidir. El pago único NO tiene este
problema: su `payer.email` es solo informativo.

## Solución

Capturar/confirmar el email de MercadoPago en un paso previo del flujo de suscripción, persistirlo en el
usuario, y usarlo como `payer_email` de la preapproval.

## Cambios

### 1. Modelo de datos
Migración: columna **`mercadopago_email`** (string, nullable) en `users`. Sin backfill.
Validación en `User`: `validates :mercadopago_email, format: {with: URI::MailTo::EMAIL_REGEXP}, allow_blank: true`.
Es un campo separado del `email` de login (inmutable, BR-093).

### 2. Rutas
`resources :listing_subscriptions, only: [:new, :create]` (se agrega `create`; se conservan las
collection `success`/`cancel`).

### 3. `Panel::ListingSubscriptionsController` — partir el flujo en dos

- **`new` (GET)**: conserva los guards actuales (`subscribable?`, `ensure_priced_association!`). En vez de
  crear la preapproval y redirigir, **renderiza un formulario** con el email prellenado
  `@payer_email = current_user.mercadopago_email.presence || current_user.email`. No crea nada todavía.
- **`create` (POST)** [nueva]: repite los guards (`subscribable?`, `ensure_priced_association!`). Toma
  `params[:mercadopago_email]`:
  - Si es blank o formato inválido → redirect de vuelta al formulario
    (`new_panel_listing_subscription_path(listing_id: @listing.id)`) con alert
    `panel.listing_subscriptions.flash.invalid_email`, para que el socio corrija sin perder el flujo.
  - Guarda `current_user.update!(mercadopago_email: email)`.
  - Captura el precio (snapshot): `@listing.update!(amount: @pricing.price, platform_fee: nil, neighborhood_association: @association)`.
  - `mercadopago.create_listing_subscription(@listing, payer_email: email, back_url: success_...)`.
  - Si no hay `init_point`/`id` → redirect al listing con alert accionable
    `panel.listing_subscriptions.flash.subscription_failed` ("Verificá que el correo (X) coincida con el
    de tu cuenta de MercadoPago").
  - Si OK → `@listing.update!(preapproval_id:, subscription_status: "pending")` + redirect al `init_point`.
  - `rescue MercadopagoService::ConfigurationError` → alert `misconfigured` (igual que hoy).

### 4. Vista
Nueva `app/views/panel/listing_subscriptions/new.html.erb`: form (POST a
`panel_listing_subscriptions_path(listing_id: @listing.id)`) con:
- Input `mercadopago_email` prellenado con `@payer_email`, editable.
- Nota: "Debe coincidir con el correo de tu cuenta de MercadoPago, o el cobro se rechazará".
- Botón "Continuar a MercadoPago".
La vista `panel/listings/show.html.erb` (botón "Activar renovación automática" → `new_panel_listing_subscription_path`)
NO cambia; ahora el link lleva al formulario.

### 5. Alcance (YAGNI)
Solo suscripciones. El pago único (`Panel::PaymentsController`, `create_preference`) NO cambia — su
`payer.email` es informativo. `mercadopago_email` se usa únicamente como `payer_email` de la preapproval.
El paso previo se muestra SIEMPRE (email prellenado y editable), incluso si ya está guardado, para que el
socio confirme cada vez.

### 6. i18n (es + en)
Nuevas keys bajo `panel.listing_subscriptions`:
- `new.title`, `new.email_label`, `new.email_hint`, `new.submit` (form).
- `flash.invalid_email`, `flash.subscription_failed` (errores).

### 7. Regla de negocio — BR-142
"Para la auto-renovación de publicaciones, el socio confirma el email de su cuenta MercadoPago
(`users.mercadopago_email`, distinto del email de login inmutable BR-093). MP valida que ese `payer_email`
coincida con el pagador al autorizar/cobrar la suscripción sin plan asociado; si no coincide, rechaza el
cobro. No aplica al pago único, donde el `payer.email` es solo informativo." Se agrega a CLAUDE.md.

## Testing

- **Modelo**: `mercadopago_email` válido / inválido (formato) / nil.
- **Controller `new`**: renderiza el form con el email prellenado (mercadopago_email si existe, si no el de
  login). Guard `subscribable?` false → redirect.
- **Controller `create`**: (a) email válido → guarda `mercadopago_email`, crea preapproval con ese email
  (stub del service), setea preapproval_id + pending, redirige al init_point; (b) email inválido → alert,
  no crea; (c) MP sin init_point → alert accionable, no persiste preapproval.
- **Regresión**: suite completa + `bin/ci`.

## Fuera de alcance
- OAuth / vinculación real de cuenta MP (over-engineering; MP Connect es para vendedores).
- Verificar contra la API de MP que el email tenga cuenta (MP valida al pagar; el error se maneja).
- Usar `mercadopago_email` en el pago único.
