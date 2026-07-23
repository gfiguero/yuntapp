# MercadoPago — Pruebas en Sandbox

Guía y datos para probar los flujos de pago (certificados, publicaciones y
suscripciones) contra el sandbox de MercadoPago.

## Cuentas de prueba

| Rol | Usuario | Contraseña | Email (para `payer_email`) |
|-----|---------|------------|----------------------------|
| Comprador (buyer) | `TESTUSER8291550847826441200` | `U9W5s93ROU` | `test_user_8291550847826441200@testuser.com` |

> El `payer_email` debe ir en formato `test_user_<id>@testuser.com` (en
> minúsculas y con guiones bajos). Otras variantes (`testuser<id>@…`,
> `TESTUSER<id>@…`) devuelven `500 Internal server error`.

> Son cuentas de prueba de MercadoPago (sin dinero real). El vendedor es la
> cuenta de prueba cuyo `access_token` (`APP_USR-…`) está configurado vía
> `MERCADOPAGO_ACCESS_TOKEN` / credentials.

## Trampas frecuentes del checkout de prueba

- **"Una de las partes con la que intentas hacer el pago es de prueba"**:
  aparece si se abre el checkout con una sesión de MP real (o sin sesión).
  Solución: ventana de incógnito → iniciar sesión en mercadopago.cl con la
  cuenta buyer de prueba → recién entonces abrir el `init_point`. Ambas
  cuentas de prueba (vendedor y comprador) deben colgar de la misma cuenta
  madre en "Tus integraciones".
- **Tarjetas de prueba**: Mastercard `5416 7526 0258 2580`, CVV `123`,
  vencimiento futuro. Nombre del titular controla el resultado: `APRO`
  aprueba, `OTHE` rechaza.

## Restricciones del sandbox descubiertas en las pruebas

- **Pagos obsoletos con `external_reference` reciclado**: si la BD dev se
  recrea, los ids de certificados/listings se repiten y un *payment search*
  por `external_reference` puede encontrar pagos aprobados de sesiones
  anteriores. Al probar, filtrar por `date_created` o usar ids nuevos.
  Este escenario motivó BR-090 (validación de monto en el webhook).
- **`back_urls` de preferences con `auto_return`**: también exigen https
  público (`auto_return invalid. back_url.success must be defined` con
  localhost). Sin `auto_return` las preferences sí aceptan localhost.

- **`back_url` de suscripciones debe ser https válida**: la API de
  `preapproval` rechaza `http://localhost:3000/...` con
  `Invalid value for back_url`. Consecuencia: el flujo de suscripción no
  puede completarse de punta a punta desde un dev server en localhost sin un
  túnel https (ngrok/cloudflared). Las preferences de pago único sí aceptan
  localhost.
- **`reason` de la preapproval: máximo 60 caracteres** (error 400
  `reason has more than 60 characters`). `MercadopagoService` lo trunca.
- **`payer_email` debe ser un usuario de prueba real** de la misma cuenta
  sandbox; con un email inexistente la API devuelve un críptico
  `500 Internal server error`.
- **Webhooks no llegan a localhost**: para validar el procesamiento en dev se
  puede simular la entrega con un POST local a `/webhooks/mercadopago`
  usando los datos reales obtenidos por polling (`fetch_preapproval`,
  `fetch_authorized_payment`).

## Receta rápida (suscripción de publicación)

1. Asegurar precio de publicación vigente para la junta
   (`ListingPricing.current_for(assoc)` o `admin/listing_pricings`).
2. Crear la preapproval vía consola con back_url https (en producción el
   controller usa la URL real del request):

   ```ruby
   listing.update!(amount: pricing.price, platform_fee: nil, neighborhood_association: assoc)
   svc = MercadopagoService.new
   resp = svc.create_listing_subscription(listing,
     payer_email: "<email del buyer de prueba>",
     back_url: "https://yuntapp.cl/panel/listing_subscriptions/success")
   listing.update!(preapproval_id: resp["id"], subscription_status: "pending")
   resp["init_point"] # → abrir y autorizar con el buyer de prueba
   ```

3. Autorizar en el checkout con la cuenta buyer de la tabla.
4. Poll del estado: `svc.fetch_preapproval(listing.preapproval_id)["status"]`
   → `authorized`.
5. Simular los webhooks localmente (o esperar el webhook real en producción):
   `subscription_preapproval` sincroniza el estado; los cobros aparecen en
   `svc.sdk`→`/authorized_payments/search` y se procesan vía
   `subscription_authorized_payment`.
