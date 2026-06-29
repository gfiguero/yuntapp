---
Status: approved
Feature: payment-mercadopago
Date: 2026-06-29
Parent-Feature: Certificados end-to-end (PR-A de 3)
---

# Spec: Pago de Certificados con MercadoPago (PR-A)

## Contexto

El flujo de certificados está documentado en CLAUDE.md (UC-003 a UC-007) pero solo está implementado UC-003 parcial. El bloqueante mayor es UC-004 (pago). Sin pago, el certificado se queda en `pending_payment` indefinidamente y la promesa "100% remoto" no se cumple.

Este PR es el **primero de tres**. Aterriza el precio por junta + integración MercadoPago + transición `pending_payment → paid`. **NO incluye emisión automática, generación de PDF ni verificación pública** (PR-B y PR-C).

## Reglas de Negocio Nuevas / Activadas

| ID | Categoría | Regla | Estado |
|----|-----------|-------|--------|
| BR-005 | Precios | El precio mínimo por certificado es $1.000 CLP. Validar en modelo y en UI | ✅ Ya en CLAUDE.md, este PR la implementa |
| BR-004 | Comisión | Yuntapp retiene el 10% de cada certificado. Invariable | ✅ Ya en CLAUDE.md, este PR la calcula |
| BR-002 | Pagos | No avanzar hasta que MercadoPago confirme | ✅ Ya en CLAUDE.md, este PR la implementa |
| BR-070 | Precios | Cada junta puede definir múltiples precios históricos con vigencia (`effective_from`, `effective_to`). El precio efectivo de un certificado es el vigente al momento de crear el `ResidenceCertificate` y queda capturado en `amount` (snapshot inmutable) | **NUEVA** |
| BR-071 | Pagos | El webhook de MercadoPago es idempotente: si llega dos veces con el mismo `payment_id`, no se procesa dos veces ni se actualiza el certificado | **NUEVA** |
| BR-072 | Pagos | El webhook de MercadoPago debe validar la firma `x-signature` antes de procesar. Webhooks sin firma válida son descartados con 401 | **NUEVA** |
| BR-073 | Pagos | Si el pago es rechazado, refunded o cancelado por MP, el certificado vuelve/permanece en `pending_payment`. El usuario puede reintentar pagando (BR-003) | **NUEVA** |

## Cambios en Modelos

### Migración 1 — `add_payment_fields_to_residence_certificates`
- `amount: integer, null: true` — precio cobrado en CLP (snapshot al momento de solicitar)
- `platform_fee: integer, null: true` — 10% de `amount`, calculado en el modelo
- `payment_id: string, null: true` — referencia única de MercadoPago
- `paid_at: datetime, null: true` — timestamp de confirmación de pago
- Índice único en `payment_id` (para idempotencia)

### Migración 2 — `create_certificate_pricings`
Nuevo modelo `CertificatePricing`:
- `neighborhood_association_id: integer, null: false`
- `price: integer, null: false` — CLP
- `effective_from: datetime, null: false, default: Time.current`
- `effective_to: datetime, null: true` — null = vigente
- `created_by_id: integer, null: false` — User que la creó (admin de junta)
- Índice compuesto `(neighborhood_association_id, effective_from)`

### Cambios en `ResidenceCertificate`
- `validates :amount, numericality: { greater_than_or_equal_to: 1000 }, allow_nil: true` (BR-005)
- `validates :payment_id, uniqueness: true, allow_nil: true` (BR-071)
- `before_save :compute_platform_fee, if: -> { amount.present? && platform_fee.nil? }`
- Nuevo método `mark_as_paid!(payment_id:, paid_at: Time.current)` — transición atómica con guard contra doble-pago
- Inmutabilidad existente (BR-008) se mantiene

### Nuevo modelo `CertificatePricing`
- `belongs_to :neighborhood_association`
- `belongs_to :created_by, class_name: "User"`
- `validates :price, numericality: { greater_than_or_equal_to: 1000 }` (BR-005)
- `scope :current_for, ->(association) { where(neighborhood_association: association).where(effective_to: nil).order(effective_from: :desc).first }`
- `before_create :close_previous_pricing!` — cierra `effective_to` de la anterior

## Flujo Completo

```
Socio aprobado en panel
    │
    ▼
Click "Solicitar certificado"
    │
    ▼
Selecciona miembro (sí mismo o dependiente) + propósito
    │
    ▼
Panel::ResidenceCertificatesController#create
    │  - Busca precio vigente: CertificatePricing.current_for(association)
    │  - Si no hay precio definido → error 422 "La junta no ha definido precio"
    │  - Crea ResidenceCertificate(amount: pricing.price, platform_fee: amount * 0.10,
    │                              status: "pending_payment")
    ▼
Panel::PaymentsController#new(certificate)
    │  - MercadoPagoService.create_preference(certificate)
    │    - Crea Preference vía SDK con back_urls (success/failure) + webhook URL
    │    - Guarda preference_id en certificate (opcional)
    │  - Redirige a init_point (URL del checkout de MP)
    ▼
Usuario paga en MercadoPago
    │
    ▼
MP envía webhook POST /webhooks/mercadopago
    │  - Verifica firma x-signature (BR-072)
    │  - Si firma inválida → 401
    │  - Lee payment_id del payload
    │  - Idempotencia: ya hay certificate con ese payment_id? → 200 sin hacer nada (BR-071)
    │  - Consulta estado a MP API (no confiar solo en payload)
    │  - Si status: approved → certificate.mark_as_paid!(payment_id, paid_at)
    │    - Status: pending_payment → paid (BR-002)
    │  - Si status: rejected/cancelled/refunded → no-op (BR-073)
    │  - Responde 200 a MP
    ▼
Usuario es redirigido a back_url success
    │  Panel::PaymentsController#success → muestra "Pago recibido, certificado en proceso"
    │
    │  (PR-B se encarga de emisión automática paid → issued)
```

## Archivos a Crear / Modificar

### Migraciones
1. `db/migrate/TIMESTAMP_add_payment_fields_to_residence_certificates.rb`
2. `db/migrate/TIMESTAMP_create_certificate_pricings.rb`

### Modelos
3. `app/models/residence_certificate.rb` — campos pago, validaciones, `mark_as_paid!`
4. `app/models/certificate_pricing.rb` — nuevo modelo
5. `app/models/neighborhood_association.rb` — `has_many :certificate_pricings`, `current_certificate_price`

### Services
6. `app/services/mercadopago_service.rb` — wrapper del SDK: `create_preference(certificate)`, `verify_signature(headers, body)`, `fetch_payment(payment_id)`

### Controllers
7. `app/controllers/panel/residence_certificates_controller.rb` — modificar `create` para calcular `amount/platform_fee`; nuevo `payment` que inicia checkout
8. `app/controllers/panel/payments_controller.rb` — `new` (genera preference + redirect), `success`, `failure`, `pending`
9. `app/controllers/webhooks/mercadopago_controller.rb` — `create` (sin authenticate_user!, sin CSRF, valida firma)
10. `app/controllers/admin/certificate_pricings_controller.rb` — `index`, `new`, `create` para que admin de junta defina precio

### Vistas
11. `app/views/panel/payments/success.html.erb`
12. `app/views/panel/payments/failure.html.erb`
13. `app/views/panel/payments/pending.html.erb`
14. `app/views/admin/certificate_pricings/index.html.erb` — lista de precios históricos + actual
15. `app/views/admin/certificate_pricings/new.html.erb` — formulario

### Rutas
16. `config/routes.rb`:
    - `panel/payments` con `new`, `success`, `failure`, `pending`
    - `webhooks/mercadopago` con `create` (POST, skip CSRF, skip auth)
    - `admin/certificate_pricings`

### Configuración
17. `Gemfile` + `Gemfile.lock` — agregar `gem "mercadopago-sdk"`
18. `config/credentials/development.yml.enc` + `production.yml.enc` — MP access_token + webhook_secret
19. `config/initializers/mercadopago.rb` — configura SDK con credenciales según entorno

### I18n
20. `config/locales/es.yml` — claves para precios, pagos, mensajes

### Tests
21. `test/models/certificate_pricing_test.rb` — validaciones, close_previous_pricing, current_for
22. `test/models/residence_certificate_test.rb` — amount/platform_fee, mark_as_paid! con idempotencia, BR-005
23. `test/controllers/panel/payments_controller_test.rb` — flujos new/success/failure
24. `test/controllers/webhooks/mercadopago_controller_test.rb` — firma válida/inválida, idempotencia, status rejected
25. `test/controllers/admin/certificate_pricings_controller_test.rb` — autorización, CRUD, multi-tenant
26. `test/controllers/panel/residence_certificates_controller_test.rb` — **nuevo** (gap auditado): solicitar sin precio vigente, con precio, autorización household_admin
27. `test/services/mercadopago_service_test.rb` — verify_signature, fake API responses
28. `test/fixtures/certificate_pricings.yml` — fixture con precio vigente para manios_de_buin

### CLAUDE.md
29. Agregar BR-070, BR-071, BR-072, BR-073 a la tabla.

## Decisiones de Diseño

- **Snapshot inmutable de precio**: `residence_certificates.amount` captura el precio al momento de la solicitud. Si la junta sube el precio después, el certificado pendiente mantiene el monto original. Evita disputas.
- **`platform_fee` calculado por el modelo, no en el controller**: `amount * 0.10` (BR-004). Garantiza consistencia sin importar el camino de creación.
- **Servicio aislado para MP**: `MercadoPagoService` encapsula todas las llamadas. Facilita stub en tests con WebMock/VCR.
- **Webhook con verificación de firma**: BR-072. Sin esto cualquiera podría POST-ear al endpoint y marcar certificados como pagados. MP envía header `x-signature: ts=..., v1=hash`.
- **Idempotencia por `payment_id`**: BR-071. Índice único en BD + chequeo explícito antes de marcar como pagado. MP reintenta webhooks varias veces.
- **Doble verificación con MP API**: el webhook payload puede ser falseado parcialmente. El servicio consulta `mercadopago.payments.get(payment_id)` para confirmar el estado real.
- **Pricings con vigencia (no edit/destroy)**: BR-070. El admin solo puede crear precios nuevos; los anteriores quedan con `effective_to` cerrado. Auditoría histórica.
- **Sin retry automático de pago**: si el pago falla, el usuario debe iniciar uno nuevo desde la UI (BR-003). No autorelanzamos checkout.
- **Credenciales Rails**: access_token y webhook_secret van en `Rails.application.credentials`. Separados por entorno (sandbox vs producción).
- **`mercadopago-sdk` gem oficial**: aunque podríamos usar HTTP directo, el SDK oficial maneja paginación, retries y firma de webhooks.
- **PR-A no toca emisión**: `paid` se mantiene como estado terminal en este PR. La transición `paid → issued` queda explícitamente en PR-B.

## Seguridad

- Webhook endpoint `POST /webhooks/mercadopago` **público** (sin auth, sin CSRF) pero **verifica firma** antes de procesar.
- Pricing solo modificable por admin de la junta o superadmin (filtro por `current_neighborhood_association`).
- Strong params: el panel no acepta `amount`, `platform_fee`, `payment_id`, `status` desde params del usuario — se asignan en el controller/servicio.
- `payment_id` único en BD evita procesamiento duplicado por reintento de webhook.
- `MercadoPagoService.fetch_payment` consulta MP API directamente — no confiamos en el payload del webhook para el monto/estado real.
- Logging: cada webhook entrante se loggea con el `payment_id` y resultado de verificación (en `Rails.logger`, no en archivo público).

## Fuera de Alcance (PR-B y PR-C)

- **Emisión automática `paid → issued`**: callback/job que dispara al confirmar pago. PR-B.
- **Generación de PDF**: Prawn + rqrcode con folio, QR, código alfanumérico. PR-B.
- **`validation_token` (UUID) + `validation_code` (alfanumérico)**: campos para verificación. PR-B.
- **Ruta pública `/verify/:token`**: PR-C.
- **Sistema de notificaciones por email** al socio cuando el pago confirma: fuera de scope (queda en BR-050 como deuda).
- **Devolución / reembolso**: BR-063 dice "no hay devoluciones porque el certificado se emite automático". Pero si el pago queda en limbo y el usuario abandona, no le devolvemos — consistente con BR-003.
