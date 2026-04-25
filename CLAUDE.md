# Yuntapp - Plataforma Vecinal

## Descripcion General

Yuntapp es una plataforma web que digitaliza el certificado de residencia chileno, un trámite que actualmente solo existe de forma presencial en municipalidades. Permite a los residentes solicitar, pagar y descargar su certificado 100% online, mientras las juntas de vecinos verifican identidad y residencia de forma remota antes de emitirlo. El certificado incluye QR, código alfanumérico y URL de verificación pública. Las juntas definen su precio (mínimo $1.000 CLP) y Yuntapp retiene un 10% de comisión por operación. Además incluye gestión de socios, directiva y un marketplace comunitario.

## Objetivo del Producto y Propuesta de Valor

Yuntapp digitaliza el certificado de residencia, un trámite que hoy **solo existe de forma presencial** en las municipalidades de Chile. La propuesta de valor central es:

> **Cualquier residente puede solicitar, pagar y descargar su certificado de residencia desde internet, sin ir a ninguna oficina.**

Las juntas de vecinos son el ente emisor oficial reconocido. El certificado emitido por Yuntapp tiene la misma validez que el presencial porque la junta verifica la identidad y residencia del solicitante antes de aprobar y emitir el documento.

### Diferenciadores clave
- **100% remoto**: Solicitud, pago y descarga sin desplazamiento físico.
- **Verificación documental online**: Los adminsitradores de la junta revisan los documentos de identidad y residencia enviados digitalmente antes de emitir.
- **Certificado con múltiples canales de validación**: El PDF incluye QR code, código alfanumérico y URL pública para verificar autenticidad.
- **Modelo SaaS para juntas**: Cada junta define su precio, Yuntapp opera como plataforma.

---

## Modelo de Negocio

### Precios
- Cada junta de vecinos define libremente el precio de su certificado de residencia.
- **Precio mínimo**: $1.000 CLP por certificado.
- No hay precio máximo definido, pero debe ser razonable para el contexto vecinal chileno.

### Comisión de Yuntapp
- Yuntapp retiene el **10%** del precio cobrado en cada certificado emitido.
- El 90% restante es para la junta de vecinos.
- La comisión cubre los gastos operacionales de la plataforma (hosting, pasarela de pago, soporte).

### Pasarela de Pago
- **MercadoPago** es la pasarela de pago elegida (aún no implementada).
- El pago debe completarse **antes** de que el admin de la junta revise y emita el certificado.
- Si el pago falla o es rechazado, la solicitud permanece en estado `pending_payment` y no avanza.

---

## Flujo Principal: Certificado de Residencia

Este es el flujo de negocio más importante de la aplicación. Claude Code debe proteger su integridad en todo cambio de código.

```
Socio aprobado
    │
    ▼
Solicita certificado (panel)
    │  Crea ResidenceCertificate con status: pending_payment
    ▼
Paga con MercadoPago
    │  status → paid (webhook de MercadoPago confirma)
    ▼
Admin de junta revisa solicitud + documentos
    │  status → approved  (o rejected con motivo)
    ▼
Sistema genera PDF con folio único + código de validación
    │  status → issued
    ▼
Socio descarga el PDF desde su panel
```

### Estados de ResidenceCertificate
| Estado | Descripción |
|--------|-------------|
| `pending_payment` | Solicitud creada, esperando pago |
| `paid` | Pago confirmado por MercadoPago, en cola para revisión |
| `approved` | Admin aprobó, sistema emite el PDF |
| `rejected` | Admin rechazó con motivo. El socio puede volver a intentar |
| `issued` | PDF generado y disponible para descarga |

> **REGLA CRÍTICA**: Nunca emitir un certificado sin que el pago esté confirmado (`paid`). El admin no debe ver la solicitud hasta que el pago sea exitoso.

### Código de Validación del Certificado
El PDF del certificado debe incluir **tres canales de validación simultáneos**:
1. **QR Code**: Apunta a la URL pública de verificación.
2. **Código alfanumérico**: Código único legible (ej: `CR-00042-X7K9`), útil para verificación telefónica.
3. **URL pública**: `https://yuntapp.cl/verify/{token}` — página accesible sin login que muestra la validez del certificado.

La URL pública muestra: nombre del titular, RUN, dirección, junta emisora, fecha de emisión, fecha de vencimiento y estado (válido/inválido/vencido).

---

## Casos de Uso

Cada caso de uso documenta el flujo ideal (happy path). Claude Code debe respetar estas precondiciones y postcondiciones al implementar cualquier feature relacionada. Agregar nuevos casos de uso con el siguiente ID disponible (`UC-XXX`).

---

### UC-001 · Registro de residente
**Actor**: Visitante sin cuenta
**Precondición**: Ninguna

| # | Paso |
|---|------|
| 1 | El visitante accede a la página de registro |
| 2 | Ingresa email y contraseña |
| 3 | Confirma su email mediante el enlace enviado |
| 4 | Es redirigido al panel con instrucciones para iniciar el onboarding |

**Postcondición**: Usuario con cuenta activa, sin asociación ni identidad verificada.

---

### UC-002 · Onboarding: convertirse en socio
**Actor**: Usuario registrado sin socio activo
**Precondición**: UC-001 completado

| # | Paso |
|---|------|
| 1 | Selecciona región, comuna y junta de vecinos |
| 2 | Ingresa nombre, apellido, RUN y teléfono; sube documentos de identidad |
| 3 | Selecciona su delegación vecinal o ingresa dirección manual |
| 4 | Revisa el resumen y envía la solicitud |
| 5 | El admin de la junta recibe la solicitud en su panel |
| 6 | El admin verifica los documentos y aprueba la solicitud |
| 7 | El sistema crea el `Member` activo y notifica al residente |

**Postcondición**: Usuario con `OnboardingRequest` en estado `approved` y `Member` activo vinculado a una `HouseholdUnit`.

---

### UC-003 · Solicitud de certificado de residencia
**Actor**: Socio aprobado (residente con `Member` activo)
**Precondición**: UC-002 completado — `OnboardingRequest` en `approved`

| # | Paso |
|---|------|
| 1 | El socio accede a "Solicitar certificado" en su panel |
| 2 | Selecciona el propósito del certificado (ej: trámite bancario, arriendo) |
| 3 | El sistema muestra el precio definido por la junta y la descripción del certificado |
| 4 | El socio confirma la solicitud |
| 5 | El sistema crea el `ResidenceCertificate` en estado `pending_payment` |
| 6 | El socio es redirigido al flujo de pago (UC-004) |

**Postcondición**: `ResidenceCertificate` creado en estado `pending_payment`.

---

### UC-004 · Pago del certificado
**Actor**: Socio aprobado con solicitud en `pending_payment`
**Precondición**: UC-003 completado

| # | Paso |
|---|------|
| 1 | El socio es redirigido a MercadoPago con el monto del certificado |
| 2 | Completa el pago con su medio de pago preferido |
| 3 | MercadoPago envía webhook de confirmación a Yuntapp |
| 4 | El sistema actualiza el `ResidenceCertificate` a estado `paid` |
| 5 | El sistema registra el `payment_id`, el `amount` pagado y calcula la `platform_fee` (10%) |
| 6 | El admin de la junta recibe notificación de nueva solicitud pagada para revisar |

**Postcondición**: `ResidenceCertificate` en estado `paid`, visible para el admin de la junta.

---

### UC-005 · Revisión y emisión del certificado
**Actor**: Admin de junta
**Precondición**: UC-004 completado — certificado en estado `paid`

| # | Paso |
|---|------|
| 1 | El admin ve la solicitud en su panel de certificados pendientes |
| 2 | Revisa los datos del solicitante: identidad, domicilio y propósito |
| 3 | Aprueba la solicitud |
| 4 | El sistema genera el folio único (`CR-{association_id}-{sequence}`) |
| 5 | El sistema genera el `validation_token` (UUID) y el `validation_code` (alfanumérico legible) |
| 6 | El sistema genera el PDF con los datos del certificado, QR, código y URL de verificación |
| 7 | El certificado pasa a estado `issued` y el socio recibe notificación |

**Postcondición**: `ResidenceCertificate` en estado `issued` con PDF generado y código de validación activo.

---

### UC-006 · Descarga del certificado
**Actor**: Socio aprobado con certificado emitido
**Precondición**: UC-005 completado — certificado en estado `issued`

| # | Paso |
|---|------|
| 1 | El socio accede a "Mis certificados" en su panel |
| 2 | Ve el certificado emitido con folio, fecha de emisión y fecha de vencimiento |
| 3 | Descarga el PDF |
| 4 | El PDF contiene: datos del titular, junta emisora, propósito, QR, código alfanumérico y URL de verificación |

**Postcondición**: El socio tiene el PDF descargado. El certificado permanece disponible para descargas futuras.

---

### UC-007 · Verificación pública del certificado
**Actor**: Cualquier persona (sin login requerido)
**Precondición**: Tener el código alfanumérico, QR, o URL del certificado

| # | Paso |
|---|------|
| 1 | El verificador accede a `yuntapp.cl/verify/{token}` o escanea el QR o ingresa el código alfanumérico |
| 2 | El sistema busca el certificado por token o código |
| 3 | Muestra: nombre del titular, RUN (parcialmente oculto), junta emisora, propósito, fecha de emisión, fecha de vencimiento y estado |
| 4 | El estado se muestra como: **Válido**, **Vencido**, o **Anulado** |

**Postcondición**: El verificador obtiene confirmación de la autenticidad del certificado sin necesidad de contactar a la junta.

---

## Reglas de Negocio

Estas reglas deben respetarse en cualquier implementación. Si una tarea entra en conflicto con alguna de ellas, consultar antes de implementar.

Claude Code debe agregar una fila a esta tabla cada vez que descubra o acuerde una nueva regla durante el desarrollo. Usar el siguiente ID disponible en la categoría correspondiente. No renumerar reglas existentes; si una regla queda obsoleta, marcarla como `[RETIRADA]` en la descripción.

| ID | Categoría | Regla |
|----|-----------|-------|
| BR-001 | Acceso | Solo socios con `onboarding_request` en estado `approved` y `member` activo pueden solicitar certificados |
| BR-002 | Pagos | No mostrar la solicitud al admin hasta que MercadoPago confirme el pago (status `paid`) |
| BR-003 | Pagos | Si el pago falla o es rechazado, la solicitud permanece en `pending_payment` sin avanzar |
| BR-004 | Comisión | Yuntapp retiene el 10% de cada certificado emitido. Esta comisión es invariable y no puede modificarse por asociación |
| BR-005 | Precios | El precio mínimo por certificado es $1.000 CLP. Validar en modelo y en UI |
| BR-006 | Integridad | El folio `CR-{association_id}-{sequence}` no puede cambiar de formato. Es el identificador oficial |
| BR-007 | Multi-tenant | Un admin solo puede ver y gestionar datos de su propia junta. El superadmin puede ver todo |
| BR-008 | Integridad | Una vez en estado `issued`, el certificado es inmutable. Para corregir errores: rechazar y emitir uno nuevo |
| BR-009 | Validación | La URL pública de verificación debe responder indefinidamente, incluso para certificados vencidos (mostrar "vencido", no 404) |
| BR-010 | Normalización | El RUN se normaliza antes de validar: eliminar puntos y espacios, convertir a mayúsculas, insertar guión antes del dígito verificador (ej: `12.345.678-k` → `12345678-K`) |
| BR-011 | Identidad | El dígito verificador del RUN debe ser válido según el algoritmo módulo 11 chileno. Rechazar RUN con dígito incorrecto |
| BR-012 | Identidad | El RUN es único en `verified_identities`. No pueden existir dos identidades verificadas con el mismo RUN |
| BR-013 | Normalización | El teléfono se normaliza a formato `+569XXXXXXXX`. Si ingresa `9XXXXXXXX` (9 dígitos), se agrega `+56` automáticamente |
| BR-014 | Normalización | Los nombres se normalizan: primera letra de cada palabra en mayúscula, resto en minúsculas, sin espacios extras |
| BR-015 | Onboarding | El socio debe aceptar los términos (`terms_accepted_at` presente) para enviar la solicitud de onboarding |
| BR-016 | Onboarding | Al cambiar de región se resetean comarca y asociación. Al cambiar de comuna se resetea la asociación (cascada) |
| BR-017 | Onboarding | El envío de onboarding es atómico: `OnboardingRequest`, `IdentityVerificationRequest` y `ResidenceVerificationRequest` pasan a `pending` juntos o ninguno |
| BR-018 | Onboarding | Al reiniciar el onboarding se elimina el `Member` activo y se cancela la solicitud pendiente. Es una acción destructiva |
| BR-019 | Residencia | Para completar el paso de domicilio: se requiere `neighborhood_delegation_id` O `street_name`, no pueden ambos estar vacíos |
| BR-020 | Residencia | El número de vivienda (`number`) es siempre obligatorio en el domicilio |
| BR-021 | Residencia | El primer residente aprobado de un domicilio recibe `household_admin: true` en su `Residency`. Los siguientes no |
| BR-022 | Acceso | Solo el `household_admin` del domicilio puede solicitar certificados y agregar nuevos miembros al hogar |
| BR-023 | Certificados | Los certificados vencen 6 meses después de la fecha de emisión (`issue_date + 6.months`) |
| BR-024 | Integridad | La aprobación del onboarding es transaccional: crea `VerifiedIdentity`, `VerifiedResidence`, `HouseholdUnit`, `Residency` y `Member` en una sola transacción. Si algo falla, se revierte todo |
| BR-025 | Integridad | Al rechazar un `OnboardingRequest`, se rechazan en cascada su `IdentityVerificationRequest` y `ResidenceVerificationRequest` |
| BR-026 | Acceso | Un `Member` rechazado puede re-enviar su solicitud cambiando el estado de vuelta a `pending` |
| BR-027 | Certificados | Un certificado de residencia se vincula obligatoriamente a un `Member` + `HouseholdUnit` + `NeighborhoodAssociation` |
| BR-028 | Multi-tenant | El admin solo ve solicitudes de onboarding en estado `pending` o posterior. Las solicitudes en `draft` son invisibles para el admin |
| BR-029 | Acceso | Un usuario solo puede ser socio activo de una junta a la vez. Al unirse a una nueva junta, el `Member` anterior pasa a estado `inactive` (nunca se destruye). El historial de certificados e identidad se conserva |
| BR-030 | Integridad | El estado `inactive` en `Member` indica que el socio ya no pertenece activamente a esa junta, pero sus registros históricos (certificados, residencias) permanecen intactos y auditables |

### Categorías disponibles
- **Acceso**: quién puede hacer qué y condiciones de autorización
- **Pagos**: flujo y estados del pago con MercadoPago
- **Comisión**: reglas de la tarifa de Yuntapp
- **Precios**: restricciones de precio para las juntas
- **Integridad**: invariantes del modelo de datos y transacciones
- **Multi-tenant**: aislamiento entre asociaciones vecinales
- **Validación**: comportamiento del sistema de verificación de certificados
- **Normalización**: transformaciones automáticas de datos de entrada
- **Identidad**: reglas sobre `VerifiedIdentity` y el RUN chileno
- **Residencia**: reglas sobre domicilios y `HouseholdUnit`
- **Onboarding**: reglas del flujo de solicitud de membresía
- **Certificados**: reglas sobre `ResidenceCertificate` y su ciclo de vida

---

## Stack Tecnologico

- **Ruby**: 3.4.8
- **Rails**: 8.1.1
- **Base de datos**: SQLite3
- **Frontend**: Hotwire (Turbo + Stimulus), Tailwind CSS, DaisyUI
- **Asset Pipeline**: Propshaft + Importmap (sin Webpack/esbuild)
- **Autenticacion**: Devise (rama main de GitHub)
- **Paginacion**: Pagy
- **Deploy**: Kamal con Docker, Thruster para HTTP acceleration
- **Background Jobs**: Solid Queue
- **Cache**: Solid Cache
- **WebSockets**: Solid Cable
- **Tests**: Minitest con fixtures, SimpleCov para cobertura
- **Linting**: RuboCop (rails-omakase), Standard, ERB Lint

## Estructura de Directorios

```
app/
  controllers/
    admin/          # Panel de administracion de junta vecinal
    panel/          # Panel del usuario/socio
    superadmin/     # Panel de superadministrador del sistema
    users/          # Controladores Devise personalizados
    concerns/
  models/
    concerns/       # Filterable, Sortable
  views/
    admin/          # Vistas admin (board_members, dashboard, household_units, etc.)
    panel/          # Vistas panel usuario (onboarding, dashboard, listings, etc.)
    superadmin/     # Vistas superadmin
    layouts/        # application, admin, superadmin, auth, panel
    shared/         # _flash.html.erb
  validators/       # RunValidator, PhoneValidator
  helpers/
  javascript/
    controllers/    # Stimulus controllers
config/
  locales/          # en.yml, es.yml, devise.en.yml
db/
  migrate/
  schema.rb
test/
  controllers/
  models/
  fixtures/
```

## Arquitectura de la Aplicacion

### Tres Niveles de Acceso

1. **Superadmin** (`user.superadmin?`): Gestiona paises, regiones, comunas, asociaciones, categorias, tags y usuarios globales. Puede impersonar asociaciones para administrarlas. Layout `superadmin`.
2. **Admin** (`user.admin?` + `neighborhood_association_id`): Administra una junta de vecinos especifica. Gestiona delegaciones, domicilios, socios, verificaciones, directiva, certificados y publicaciones. Layout `admin`.
3. **Usuario/Socio** (panel): Accede al panel de usuario. Realiza onboarding, gestiona su perfil, solicita certificados, publica en marketplace. Layout `panel`/`application`.

### Autorizacion

- `ApplicationController`: requiere `authenticate_user!` globalmente via Devise.
- `Admin::ApplicationController`: verifica `ensure_neighborhood_admin!` (superadmin o admin con asociacion).
- `Superadmin::ApplicationController`: verifica `ensure_superadmin!`.
- Despues del login, usuarios no-superadmin son redirigidos a `panel_root_path`.
- Superadmin puede impersonar asociaciones via `session[:impersonated_neighborhood_association_id]`.

### Flujo de Onboarding (4 pasos)

El onboarding es el flujo principal para que un usuario se convierta en socio:

1. **Step 1 - Seleccion de Asociacion**: Selects en cascada Region -> Comuna -> Asociacion Vecinal. Usa Turbo Streams para actualizar campos dinamicamente. Crea/actualiza `OnboardingRequest`.
2. **Step 2 - Verificacion de Identidad**: Captura nombre, apellido, RUN, telefono y documentos de identidad. Crea `IdentityVerificationRequest`. Validacion con autosave via Turbo Streams.
3. **Step 3 - Verificacion de Residencia**: Seleccion de delegacion vecinal o direccion manual. Crea `ResidenceVerificationRequest`. Checkbox para alternar entre select de delegacion e input de direccion.
4. **Step 4 - Revision y Envio**: Muestra resumen de todos los datos. Al enviar, cambia el status de onboarding_request a "pending".

Rutas de onboarding: `panel/onboarding/step1..4`, con PATCH para actualizaciones parciales.

## Modelo de Datos

### Jerarquia Geografica
```
Country -> Region -> Commune -> NeighborhoodAssociation -> NeighborhoodDelegation -> HouseholdUnit
```

### Entidades Principales

#### User
- Devise: database_authenticatable, registerable, recoverable, rememberable, validatable
- Flags: `admin`, `superadmin`
- Pertenece a: `neighborhood_association` (opcional), `verified_identity` (opcional)
- Tiene: `onboarding_requests`, `identity_verification_requests`, `residence_verification_requests`, `listings`
- `current_onboarding_request`: solicitud en estado draft/pending
- Metodo `member`: primer member de su verified_identity
- Metodo `name`: nombre de verified_identity o email

#### VerifiedIdentity
- Campos: `first_name`, `last_name`, `run` (unico), `phone`, `email`, `verification_status`
- Status: pending | verified | rejected
- Attachment: `identity_document` (Active Storage)
- Callbacks: `normalize_run_field` (formato XX.XXX.XXX-K), `normalize_names` (capitaliza), `normalize_phone` (formato +56)
- Validadores custom: `RunValidator`, `PhoneValidator`

#### OnboardingRequest
- Status: draft | pending | approved | rejected
- Pertenece a: `user`, `neighborhood_association`, `region`, `commune`
- Tiene uno: `identity_verification_request`, `residence_verification_request`

#### IdentityVerificationRequest
- Status: draft | pending | approved | rejected
- Campos: `first_name`, `last_name`, `run`, `phone`, `rejection_reason`
- Attachments: `identity_documents` (muchos)
- Callbacks de normalizacion iguales a VerifiedIdentity

#### ResidenceVerificationRequest
- Status: pending | approved | rejected
- Campos de direccion + `manual_address` (boolean) + `neighborhood_delegation_id`
- Validacion condicional: requiere delegation_id o address_line_1

#### Member
- Vincula `VerifiedIdentity` con `HouseholdUnit`
- Status: pending | approved | rejected
- Flags: `household_admin`
- Trazabilidad: `requested_by` (User), `approved_by` (User), `approved_at`
- Delega name, run, phone, email, first_name, last_name a verified_identity
- Tiene: `board_members`, `residence_certificates`, `documents` (attachments)

#### HouseholdUnit
- Pertenece a: `neighborhood_delegation`, `commune`
- Tiene muchos: `members`, `approved_members`
- Campos de direccion completos

#### ResidenceCertificate
- Status: pending_payment | paid | approved | rejected | issued
- Campos: `folio` (unico por asociacion), `issue_date`, `expiration_date`, `purpose`, `notes`
- Campos pendientes de implementar: `amount` (precio cobrado en CLP), `platform_fee` (10% de amount), `payment_id` (referencia MercadoPago), `validation_token` (UUID para URL publica), `validation_code` (codigo alfanumerico legible)
- `generate_folio!`: formato "CR-{association_id}-{sequence}"
- Regla: solo avanza de `paid` a `approved`/`rejected` el admin de la junta correspondiente

#### BoardMember
- Posiciones: presidente | secretario | tesorero | director
- Campos: `position`, `start_date`, `end_date`, `active`

#### Listing (Marketplace)
- Pertenece a: `user`, `category` (opcional)
- Campos: `name`, `description`, `price`, `active`

### Concerns

- **Filterable**: Incluido en ApplicationRecord. Provee `filter_by_id(ids)` y `filter_by_name(name)` con LIKE.
- **Sortable**: Incluido en ApplicationRecord. Provee scopes `sort_by_{column}(direction)` para id, name, active, created_at, position, status, folio, member_id.

## Validadores Custom

- **RunValidator** (`app/validators/run_validator.rb`): Valida formato RUN chileno (`\d{7,8}-[\dkK]`) y digito verificador con algoritmo modulo 11.
- **PhoneValidator** (`app/validators/phone_validator.rb`): Valida formato telefono chileno (`+569XXXXXXXX`).

## Frontend

### Stimulus Controllers
- **autosave_controller**: Auto-envia formularios tras un delay configurable (default 2s). Usado en onboarding para guardar campos individuales via Turbo Streams.
- **cascading_select_controller**: Selects en cascada Region -> Comuna -> Asociacion. Carga datos completos como JSON en un value de Stimulus para evitar requests extra.
- **manual_address_controller**: Alterna entre select de delegacion e input de direccion manual con checkbox.

### Turbo Streams
Uso extensivo en el onboarding para actualizar campos individuales sin recargar la pagina. Patron: PATCH envia campo -> controlador valida -> responde con `turbo_stream.replace` del campo y boton de submit.

### CSS
- Tailwind CSS via `tailwindcss-rails` gem
- DaisyUI como libreria de componentes (temas, drawer, alerts, badges, etc.)
- Tema fijo: `data-theme="light"`

### Layouts
- `application.html.erb`: Layout publico general
- `auth.html.erb`: Login/registro (centrado, minimalista)
- `admin.html.erb`: Panel admin con drawer sidebar
- `superadmin.html.erb`: Panel superadmin con sidebar
- `panel.html.erb`: Panel de usuario

## Patrones y Convenciones

### Controladores
- Todos los recursos CRUD siguen un patron consistente con acciones: index, show, new, create, edit, update + `search` (collection) y `delete` (member, vista de confirmacion).
- Filtrado dinamico: los controladores usan `filter_scope` y `sort_scope` helpers que convierten params a nombres de scope (`filter_by_{attr}`, `sort_by_{col}`).
- Paginacion con Pagy en listados.

### Vistas
- Vistas ERB con Tailwind/DaisyUI.
- Helpers: `input_class(model, field)` para clases de validacion, `error_message(invalid, messages)` para errores inline, `icon(name)` para SVG icons.
- `sort_link` helper para columnas de tabla ordenables.
- Turbo Frames y Turbo Streams para interactividad sin SPA.

### Modelos
- Todos heredan de `ApplicationRecord` que incluye Sortable y Filterable.
- Status como constantes string (no enums de Rails), con metodos `status?` manuales.
- Normalizacion de datos en callbacks `before_validation`.
- Delegacion de atributos para evitar law of demeter violations.

### Tests
- Minitest con fixtures YAML.
- Tests de modelos y controladores.
- SimpleCov para cobertura de codigo.
- Ejecutar tests: `bin/rails test`
- Ejecutar test especifico: `bin/rails test test/models/user_test.rb`

## Comandos Utiles

```bash
# Servidor de desarrollo
bin/dev                          # Inicia con Procfile.dev (rails + tailwind watch)
bin/rails server                 # Solo Rails

# Base de datos
bin/rails db:migrate             # Ejecutar migraciones
bin/rails db:seed                # Cargar datos semilla
bin/rails db:schema:load         # Cargar schema desde cero

# Tests
bin/rails test                   # Todos los tests
bin/rails test test/models/      # Tests de modelos
bin/rails test test/controllers/ # Tests de controladores

# Linting
bundle exec rubocop              # RuboCop
bundle exec erb_lint --lint-all  # ERB Lint
bundle exec standardrb           # Standard Ruby

# Deploy
kamal setup                      # Setup inicial
kamal deploy                     # Deploy con Kamal
```

## Deploy

- Docker con Kamal para despliegue en VPS.
- Archivo `Dockerfile` incluido con build multi-stage.
- Configuracion en `config/deploy.yml` y `config/deploy.local.yml` para simulacion local.
- `LOCAL_DEPLOY.md` documenta como simular deploy en local con Docker.
- Thruster como proxy HTTP para caching y compresion.

## Idioma

La aplicacion esta primariamente en espanol (interfaz, mensajes flash, labels de formularios). Los archivos i18n estan en `config/locales/es.yml` y `config/locales/en.yml`. Las vistas del admin, panel y onboarding usan traducciones i18n extensivamente.

## Agent Team Configuration

> **OBLIGATORIO:** Para cualquier tarea de codigo (feature, fix, refactor, UI), seguir este workflow sin que el usuario lo pida.

### Archivos compartidos (`.claude/team/`)

```
backlog.md                 # Tareas pendientes
current-sprint.md          # Sprint actual
architecture/decisions.md  # ADRs
reviews/pending.md         # PRs en revision
bugs/active.md             # Bugs activos
```

### Roles

| Rol | Responsabilidad |
|-----|----------------|
| Arquitecto | Diseno, ADRs, sprint planning |
| Desarrollador | Implementacion |
| Tester | Tests |
| Reviewer | Code review |
| Documentador | Docs, CLAUDE.md |

Indicar rol al inicio: `Como [DESARROLLADOR]: Implementando...`

### Worktrees — Aislamiento por Sesion

Crear un worktree al inicio de **cada sesion de codigo**:

```
EnterWorktree(name: "{tipo}-{slug}")
```

| Tipo | Prefijo | Ejemplo |
|------|---------|---------|
| Feature | `feat-` | `feat-filtros-socios` |
| Bug fix | `fix-` | `fix-onboarding-crash` |
| Refactor | `refactor-` | `refactor-service-objects` |
| UI | `ui-` | `ui-admin-dashboard` |
| Tests | `test-` | `test-residence-certificate` |

**Flujo completo por sesion**:
```
1. EnterWorktree(name: "fix-mi-tarea")
2. Leer .claude/team/ → registrar en current-sprint.md
3. Implementar cambios
4. Actualizar reviews/pending.md con el PR
5. git add / commit / push
6. gh pr create
7. ExitWorktree(action: "keep")    # "remove" si se abandona sin cambios
```

**Reglas**:
1. Siempre `EnterWorktree` antes de escribir codigo
2. Los archivos compartidos son la fuente de verdad
3. Leer estado actual antes de actuar
4. Documentar decisiones en `decisions.md`
5. Usar IDs unicos: `BUG-XXX`, `ADR-XXX`, `#XXX`

### Skills disponibles

| Skill | Descripcion |
|-------|-------------|
| `/dev` | Pipeline autonomo: clasifica prompt → branch → implementa → review → PR |
| `/feature` | Feature completa con planning, mini-audit y actualizacion de equipo |
| `/review` | Revisa branch actual: seguridad, N+1, tests, veredicto APROBADO/CAMBIOS/BLOQUEADO |
| `/security` | Revision de seguridad Rails: strong params, autorizacion entre asociaciones, XSS, SQL injection |
| `/tdd` | Workflow TDD con Minitest y fixtures: tests primero, patron Arrange-Act-Assert |
| `/deploy` | Deploy con Kamal: pre-checklist, migraciones, health checks y rollback |
| `/db-migrate` | Crea y aplica migraciones Rails con checklist de indices, null constraints, expand-contract y batch |
| `/fix-issues` | Resuelve GitHub issues creando un PR por cada uno |
| `/audit` | Auditoria integral del codebase |
| `/audit-to-issues` | Convierte hallazgos de auditoria en GitHub issues |
| `/merge-pr` | Mezcla PRs aprobados con squash merge |
| `/check-code` | Ejecuta todas las validaciones de calidad |
