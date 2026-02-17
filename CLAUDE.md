# Yuntapp - Plataforma Vecinal

## Descripcion General

Yuntapp es una plataforma web de gestion para juntas de vecinos chilenas. Permite a las asociaciones de vecinos administrar socios, verificar identidades y residencias, emitir certificados de residencia, gestionar directivas y publicar anuncios en un marketplace comunitario. La aplicacion sigue un flujo de onboarding por pasos donde los usuarios verifican su identidad (RUN chileno) y residencia antes de convertirse en socios.

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
- Status: pending | approved | rejected | issued
- Campos: `folio` (unico por asociacion), `issue_date`, `expiration_date`, `purpose`, `notes`
- `generate_folio!`: formato "CR-{association_id}-{sequence}"

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
