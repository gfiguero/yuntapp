---
Status: approved
Feature: public-certificate-verification
Date: 2026-06-29
Parent-Feature: Certificados end-to-end (PR-C de 3)
Depends-on: PR-A, PR-B (validation_token / validation_code ya existen)
---

# Spec: Verificación Pública del Certificado (PR-C)

## Contexto

Cierre del flujo end-to-end. PR-A y PR-B dejaron el certificado emitido con `validation_token` (UUID) y `validation_code` (8 caracteres alfanuméricos). Falta el endpoint público que permita a cualquier persona (banco, arrendador, organismo) verificar la autenticidad sin login.

El QR del PDF generado en PR-B ya apunta a `/verify/:token` — este PR lo hace funcional.

## Reglas activadas / nuevas

| ID | Categoría | Regla | Estado |
|----|-----------|-------|--------|
| BR-009 | Validación | La URL pública de verificación debe responder indefinidamente, incluso para certificados vencidos (mostrar "vencido", no 404) | ✅ Existente, este PR la implementa |
| UC-007 | Caso de uso | Verificador accede a `yuntapp.cl/verify/{token}` o ingresa código alfanumérico | ✅ Existente, este PR lo implementa |
| BR-078 | Validación | El RUN del titular se muestra parcialmente oculto en la verificación pública (ej: `12.XXX.XXX-K`) para proteger privacidad | **NUEVA** |
| BR-079 | Validación | El endpoint `/verify/:identifier` acepta el `validation_token` (UUID) o el `validation_code` (8 chars alfanumérico). Ambos resuelven al mismo certificado | **NUEVA** |
| BR-080 | Validación | Un certificado con `expiration_date < today` se muestra como **Vencido**, pero la respuesta es 200 OK con los datos del certificado (para auditoría). Solo identificadores **inexistentes** retornan 404 | **NUEVA** |
| BR-081 | Validación | La verificación pública nunca muestra certificados que no estén en estado `issued`. Certificados en `pending_payment` o `paid` retornan 404 | **NUEVA** |

## Flujo

```
Verificador llega a yuntapp.cl/verify
    │
    ▼
GET /verify
    │  Muestra formulario simple con campo "Código de verificación"
    ▼
Verificador ingresa código o escanea QR
    │  Submit POST /verify → redirect a /verify/:identifier
    │  (o llega directo vía QR a /verify/:token)
    ▼
GET /verify/:identifier
    │  - Busca por validation_token (formato UUID) o validation_code (8 chars)
    │  - Filtra por status == "issued"
    │  - Si no existe → 404 con mensaje "No encontrado"
    │  - Si existe:
    │    - Determina estado: Válido (expiration_date >= today) o Vencido (< today)
    │    - Renderiza vista pública con datos: nombre, RUN enmascarado,
    │      junta, propósito, fecha emisión, fecha vencimiento, estado
    ▼
Verificador obtiene confirmación visual
```

## Cambios en Modelos

### `ResidenceCertificate`
- Nuevo método `expired?` — `expiration_date.present? && expiration_date < Date.current`
- Nuevo método `masked_run` — toma `member.run` (formato `12345678-K`) y retorna `12.XXX.XXX-K`
- Nuevo scope `findable_publicly` — `where(status: "issued")` (BR-081)
- Class method `find_for_public_verification(identifier)` — busca por `validation_token` o `validation_code`, restringido al scope público

## Cambios en Controllers

### Nuevo `VerificationsController`
- Hereda de `ActionController::Base` (no requiere auth, no usa el layout admin/panel)
- Layout dedicado `verification.html.erb` (público, sin sidebar)
- `skip_forgery_protection :only => [:lookup]` (form público)
- Acciones:
  - `index` — muestra formulario con input para código
  - `lookup` — POST: redirige a show con el identifier sanitizado
  - `show` — busca cert por identifier, renderiza vista o 404

## Archivos a Crear / Modificar

### Modelos
1. `app/models/residence_certificate.rb` — `expired?`, `masked_run`, scope, class method

### Controllers
2. `app/controllers/verifications_controller.rb` — index, lookup, show

### Vistas
3. `app/views/layouts/verification.html.erb` — layout público minimalista
4. `app/views/verifications/index.html.erb` — formulario
5. `app/views/verifications/show.html.erb` — resultado de verificación
6. `app/views/verifications/not_found.html.erb` — 404 amigable

### Rutas
7. `config/routes.rb`:
   - `get "verify", to: "verifications#index"`
   - `post "verify", to: "verifications#lookup"`
   - `get "verify/:identifier", to: "verifications#show", as: :verification`

### I18n
8. `config/locales/es.yml` — claves para form, resultado, estados Válido/Vencido, footer legal

### CLAUDE.md
9. Agregar BR-078 a BR-081

### Tests
10. `test/models/residence_certificate_test.rb` — expired?, masked_run, find_for_public_verification, scope findable_publicly
11. `test/controllers/verifications_controller_test.rb` — index sin auth, lookup redirect, show happy path con token, show happy path con código, show 404 para identifier inexistente, show 404 para cert no-issued, show 200 con badge "Vencido" para cert expirado, no muestra RUN completo

## Decisiones de Diseño

- **Sin auth y sin CSRF en GET**: el endpoint es público total. Tampoco hay tracking de quién verifica para preservar privacidad del verificador.
- **404 solo para identificadores inexistentes** (BR-080): un cert vencido sigue respondiendo 200 con badge "Vencido". Esto cumple BR-009 (URL responde indefinidamente).
- **RUN enmascarado** (BR-078): mostramos `12.XXX.XXX-K` para evitar exfiltración de datos. El verificador ya sabe el RUN porque el titular se lo dio — esto es solo defensa en profundidad ante scraping masivo.
- **Detección automática del tipo de identifier**: si tiene 36 caracteres y formato UUID → busca por token. Si tiene 8 chars alfanuméricos → busca por código. Sino, 404 sin tocar BD.
- **Sin rate limit en este PR**: el `validation_token` UUID es prácticamente imposible de brute-forcear (2^122 posibilidades). El `validation_code` 8-char alfanumérico tiene ~33^8 = 1.4 trillion combinaciones, aún costoso pero más débil. Rate limiting queda como deuda (Rack::Attack o similar).
- **Sin tracking/analytics**: no registramos verificaciones individuales. Esto preserva privacidad pero pierde data útil para auditoría — decisión consciente.
- **Layout dedicado**: la página pública debe sentirse confiable y minimalista. Sin navegación interna de Yuntapp. Logo + contenido + footer legal.
- **`find_for_public_verification` en el modelo**: encapsula la lógica de búsqueda (token o código + scope issued). El controller queda fino.

## Seguridad

- Endpoint completamente público — autorización N/A.
- `find_for_public_verification` aplica scope `where(status: "issued")` automáticamente. Imposible filtrar otros estados desde la URL.
- RUN enmascarado por defecto.
- Output del cert escapa por ERB (no usamos `raw` en datos del usuario).
- Detección de formato del identifier antes de consultar BD evita queries innecesarias y dificulta enumeración.
- **Deuda conocida**: rate limiting del endpoint para mitigar brute-force del código de 8 chars. Recomendado Rack::Attack en producción.

## Fuera de Alcance

- Rate limiting (queda como deuda explícita)
- Notificación al titular cuando alguien verifica su certificado
- Estado "Anulado" — no existe en el modelo de estados actual (`pending_payment | paid | issued`). Si se necesita, requiere nueva migración + BR.
- Analytics de verificaciones (cuántas veces se verificó cada cert)
- Soporte multi-idioma del endpoint público (ES only por ahora)

## Cierre del flujo end-to-end

Con este PR mergeado, el caso "persona se registra → solicita certificados para sí y 3 hijos → paga → recibe PDF descargable → tercero verifica por QR/código" queda completo. El UC-001 al UC-007 totalmente funcional.

Lo único pendiente del audit original que NO se resuelve aquí:
- **BR-017 violado en `submit`** del onboarding (3 `update!` sin transaction) — bug latente, fix pequeño separado
- **BR-051 cancelación de pending** — feature pequeña, separada
- **Devise `:confirmable`** — discrepancia con CLAUDE.md
