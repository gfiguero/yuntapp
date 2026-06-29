---
Status: approved
Feature: certificate-issuance-pdf
Date: 2026-06-29
Parent-Feature: Certificados end-to-end (PR-B de 3)
Depends-on: PR-A (2026-06-29-payment-mercadopago)
---

# Spec: Emisión automática + PDF (PR-B)

## Contexto

PR-A dejó el flujo en `pending_payment → paid` con `mark_as_paid!` ejecutado por el webhook de MP. Falta lo que el usuario realmente necesita: **el PDF en su panel**. Este PR cierra `paid → issued` automáticamente y genera el documento.

PR-C (siguiente) implementará la verificación pública `/verify/:token`.

## Reglas activadas / nuevas

| ID | Categoría | Regla | Estado |
|----|-----------|-------|--------|
| BR-062 | Certificados | Emisión automática tras pago confirmado, sin intervención del admin | ✅ Este PR la implementa |
| BR-023 | Certificados | Certificados vencen 6 meses después de `issue_date` | ✅ Este PR la activa |
| BR-006 | Integridad | Folio `CR-{association_id}-{sequence}` no puede cambiar de formato | ✅ Existente, se respeta |
| BR-008 | Integridad | Una vez `issued`, el certificado es inmutable | ✅ Existente, se respeta |
| BR-074 | Certificados | El `validation_token` (UUID) y `validation_code` (alfanumérico de 8 caracteres) se generan al emitir el certificado y son únicos en la base de datos | **NUEVA** |
| BR-075 | Certificados | El PDF se genera una sola vez al emitir y se almacena vía Active Storage. Descargas posteriores reutilizan el archivo almacenado | **NUEVA** |
| BR-076 | Certificados | La transición `paid → issued` se ejecuta en un job asíncrono (`IssueCertificateJob`) disparado tras confirmar el pago. Si la generación del PDF falla, el job se reintenta hasta 3 veces; si todos fallan, el certificado queda en `paid` y se loggea para revisión manual | **NUEVA** |
| BR-077 | Certificados | Se elimina la acción manual `Admin::ResidenceCertificatesController#issue`. La emisión es exclusivamente automática (BR-062) | **NUEVA** |

## Cambios en Modelos

### Migración — `add_issuance_fields_to_residence_certificates`
- `validation_token: string, null: true` — UUID v4
- `validation_code: string, null: true` — 8 caracteres alfanuméricos uppercase (ej: `X7K9MP3T`)
- `issued_at: datetime, null: true`
- Índice único en `validation_token`
- Índice único en `validation_code`

### Cambios en `ResidenceCertificate`
- `has_one_attached :pdf_document`
- Nuevo método `issue!` — genera folio, tokens, fecha de vencimiento, status `issued`. Transaccional.
- Nuevo método `generate_validation_code` — random 8 char alfanumérico con retry-on-collision
- `mark_as_paid!` enqueue `IssueCertificateJob.perform_later(self)` después del commit (vía `after_commit`)
- Validaciones nuevas: `validates :validation_token, :validation_code, uniqueness: true, allow_nil: true`

### Nuevo job `IssueCertificateJob`
- `queue_as :default`
- `retry_on StandardError, attempts: 3, wait: :exponentially_longer`
- `perform(certificate_id)`:
  - Busca el cert, retorna si ya está `issued` (idempotencia)
  - Llama a `certificate.issue!`
  - Genera PDF vía `CertificatePdfService.new(certificate).generate_and_attach!`

### Nuevo servicio `CertificatePdfService`
- Encapsula Prawn + rqrcode
- `generate_and_attach!`: crea el PDF en memoria y lo adjunta como `pdf_document` del cert
- PDF incluye:
  - Header: logo/marca Yuntapp + nombre junta
  - Cuerpo: nombre, RUN, dirección, propósito, fechas (emisión + vencimiento), folio
  - QR code (rqrcode) que apunta a `verify_url(certificate.validation_token)`
  - Código alfanumérico legible (validation_code)
  - URL de verificación impresa (texto)
  - Footer: notice legal
- URL de verificación se construye con un helper que en este PR retorna `"#{base_host}/verify/#{token}"` aunque PR-C aún no exista — el QR ya queda funcional una vez merged PR-C

## Cambios en Controllers

### `Webhooks::MercadopagoController`
- Sin cambios — `mark_as_paid!` ya enqueue el job vía `after_commit`

### `Panel::ResidenceCertificatesController#show`
- Muestra link de descarga si el certificado está `issued` y tiene `pdf_document` attached

### Eliminar `Admin::ResidenceCertificatesController#issue` (BR-077)
- Quitar acción y ruta
- Quitar botón de la vista admin si existe

## Archivos a Crear / Modificar

### Migraciones
1. `db/migrate/TIMESTAMP_add_issuance_fields_to_residence_certificates.rb`

### Modelos
2. `app/models/residence_certificate.rb` — issue!, generate_validation_code, after_commit hook, has_one_attached

### Jobs
3. `app/jobs/issue_certificate_job.rb`

### Services
4. `app/services/certificate_pdf_service.rb`

### Controllers
5. `app/controllers/admin/residence_certificates_controller.rb` — eliminar acción issue

### Vistas
6. `app/views/panel/residence_certificates/show.html.erb` — botón descarga PDF si issued

### Rutas
7. `config/routes.rb` — eliminar `patch :issue` en admin/residence_certificates

### Configuración
8. `Gemfile` + `Gemfile.lock` — agregar `gem "prawn"`, `gem "prawn-table"`, `gem "rqrcode"`
9. `config/application.rb` o similar — config de host para URL de verificación

### I18n
10. `config/locales/es.yml` — claves para PDF (texto del documento), botón descarga

### CLAUDE.md
11. Agregar BR-074, BR-075, BR-076, BR-077

### Tests
12. `test/models/residence_certificate_test.rb` — issue!, validation_token único, validation_code generation, after_commit enqueue, idempotency
13. `test/jobs/issue_certificate_job_test.rb` — perform happy path, idempotent on already-issued, retry on failure
14. `test/services/certificate_pdf_service_test.rb` — genera PDF válido, attached al cert, contiene los datos esperados (texto buscable)
15. `test/controllers/panel/residence_certificates_controller_test.rb` — show con cert issued muestra link de descarga
16. `test/controllers/admin/residence_certificates_controller_test.rb` — verificar que la ruta /issue ya NO existe (returns 404)

## Decisiones de Diseño

- **Job asíncrono** vs callback síncrono: separamos la generación del PDF del webhook de MP. Si Prawn falla (OOM, font missing), no perdemos la confirmación del pago. El job reintenta. El webhook ya respondió 200 al MP.
- **PDF en Active Storage**: aprovecha la infra existente (no nuevo servicio de storage). El archivo se guarda una vez; descargas posteriores son `redirect_to rails_blob_path`. Beneficios: CDN-friendly, no regenera, audit-friendly.
- **`validation_token` UUID + `validation_code` 8 char alfanumérico**: dos canales distintos. UUID para QR (largo, único, no se digita). Alfanumérico legible para verificación telefónica/manual.
- **Folio se sigue generando en `issue!`** (no antes): mantiene la regla "folio solo existe cuando el cert está emitido". BR-006 cumplida.
- **`after_commit` hook**: el job se enqueue después de que el `mark_as_paid!` se persistió. Evita race conditions y trabajos huérfanos si la transacción rollback.
- **Retry exponencial**: 3 intentos con backoff. Si todos fallan, el cert queda en `paid` (no `issued`) y el log lo marca para revisión manual.
- **`Admin#issue` eliminado**: la spec PR-A ya marcó esto como deuda (BR-062 inverso). Sin manual issuance.
- **URL de verificación con placeholder host**: en este PR ya generamos el QR aunque PR-C no exista. El QR queda apuntando a `/verify/:token` que dará 404 hasta PR-C — esperable.
- **Sin notificación por email al socio cuando se emite**: out of scope. Queda como deuda (BR-050 ya menciona algo similar pero para admins).

## Seguridad

- Strong params: el panel no acepta `validation_token`, `validation_code`, `issued_at`, `pdf_document`, `status` desde params.
- El PDF en Active Storage se sirve vía `rails_blob_path` con autorización: solo el `household_admin` del domicilio puede descargarlo (mismo guard que `show`).
- `validation_token`/`validation_code` son únicos y no se reusan entre certificados.
- El job verifica idempotencia: si ya está `issued`, no regenera ni sobreescribe. Defensa contra duplicate enqueueing.

## Fuera de Alcance (PR-C)

- **Ruta pública `/verify/:token`**: PR-C
- **UI de verificación pública** con estados Válido / Vencido / Anulado
- **Notificación por email al socio cuando el certificado se emite**

## Riesgos identificados

1. **Prawn + fuentes**: si el font default de Prawn no soporta caracteres especiales (acentos, ñ), el PDF puede romperse. Mitigación: registrar fonts UTF-8 (DejaVu o equivalent) en el inicializador.
2. **rqrcode versión**: la API cambió entre versiones. Pinear `~> 2.2`.
3. **URL del QR sin PR-C mergeado**: el código de verificación apunta a una ruta que dará 404 hasta PR-C. Aceptable porque PR-B y PR-C se mergean en secuencia rápida.
