---
name: security
description: Revision de seguridad Rails para yuntapp. Cubre strong params, SQL injection, autorizacion entre asociaciones, Active Storage y el modelo de tres niveles (superadmin/admin/panel).
user-invocable: true
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash(bundle exec standardrb*)
  - Bash(bundle exec erb_lint*)
  - Bash(grep*)
  - Bash(ls*)
---

# Security Review — yuntapp (Rails 8.1.1)

Revision de seguridad especializada para el stack Rails de yuntapp. Los ejemplos y checklist son Ruby/ERB, no TypeScript.

## Input

`$ARGUMENTS` — Scope opcional. Ejemplos:
- `/security` — revision completa
- `/security controllers` — solo controladores
- `/security onboarding` — solo modulo de onboarding
- `/security admin` — solo panel admin

## Stack de seguridad en yuntapp

| Capa | Herramienta | Notas |
|------|------------|-------|
| Autenticacion | Devise | database_authenticatable, rememberable |
| Autorizacion | Manual | ensure_superadmin!, ensure_neighborhood_admin! |
| CSRF | Rails built-in | protect_from_forgery (activo por defecto) |
| XSS | ERB auto-escape | `<%= %>` escapa, `<%== %>` NO escapa |
| SQL | ActiveRecord | parametrized queries por defecto |
| Uploads | Active Storage | documentos de identidad, verificaciones |

## Checklist por categoria

### 1. Strong Parameters

```ruby
# MALO — masa assignment sin filtrar
def create
  @member = Member.new(params[:member])
end

# BUENO — strong params explicitos
def member_params
  params.require(:member).permit(:first_name, :last_name, :run, :phone)
end

# CRITICO — nunca permitir flags de seguridad en params
# Nunca: .permit(:admin, :superadmin, :neighborhood_association_id)
```

Verificar en TODOS los controladores:
- [ ] Cada `create`/`update` usa un metodo `_params` privado
- [ ] Ningun controlador permite `:admin`, `:superadmin`, o `:neighborhood_association_id` en params
- [ ] `User` params no exponen flags de roles

### 2. Autorizacion entre Asociaciones

El riesgo principal de yuntapp: un admin de la asociacion A accede a datos de la asociacion B.

```ruby
# MALO — accede a cualquier Member por ID
def show
  @member = Member.find(params[:id])
end

# BUENO — scope a la asociacion actual
def show
  @member = current_neighborhood_association.members.find(params[:id])
end
```

Verificar en controladores Admin::*:
- [ ] Todos los `find` estan scoped a `current_neighborhood_association`
- [ ] `HouseholdUnit`, `Member`, `BoardMember`, `ResidenceCertificate` siempre filtrados por asociacion
- [ ] No hay rutas que permitan pasar un `neighborhood_association_id` como param

### 3. Impersonacion de Superadmin

```ruby
# En ApplicationController — verificar que la impersonacion es solo para superadmin
def current_neighborhood_association
  if current_user.superadmin? && session[:impersonated_neighborhood_association_id]
    NeighborhoodAssociation.find(session[:impersonated_neighborhood_association_id])
  else
    current_user.neighborhood_association
  end
end
```

- [ ] `session[:impersonated_neighborhood_association_id]` solo setteable por superadmin
- [ ] Se limpia al hacer sign out (Devise callback o ApplicationController)
- [ ] No hay forma de que un admin normal sette este session key

### 4. SQL Injection en ActiveRecord

```ruby
# MALO — interpolacion directa
User.where("email = '#{params[:email]}'")
Member.where("first_name LIKE '%#{params[:q]}%'")

# BUENO — parametrized
User.where(email: params[:email])
Member.where("first_name LIKE ?", "%#{params[:q]}%")

# Concern Filterable — verificar que filter_by_name usa LIKE con ?
```

- [ ] Buscar `where("... #{` en toda la codebase — deberia ser 0 resultados
- [ ] Verificar concerns `Filterable` y `Sortable` — los scopes son seguros
- [ ] Ningun `find_by_sql` con interpolacion

### 5. XSS en Vistas ERB

```erb
<%# MALO — renderiza HTML sin escapar %>
<%== @user.name %>
<%= raw @comment.body %>

<%# BUENO — escapado automatico %>
<%= @user.name %>

<%# TURBO — verificar que los turbo_stream responses no incluyen HTML sin sanitizar %>
<%= turbo_stream.replace "field", partial: "field", locals: { value: @value } %>
```

- [ ] Buscar `raw(` y `<%==` en todas las vistas — justificar cada uso
- [ ] Turbo Streams no renderiza contenido de usuario sin escapar
- [ ] Mensajes flash no contienen HTML (o usar `html_safe` solo en constantes conocidas)

### 6. Active Storage — Uploads

```ruby
# En IdentityVerificationRequest — verificar validaciones de archivo
validates :identity_documents, 
  content_type: ['image/jpeg', 'image/png', 'application/pdf'],
  size: { less_than: 5.megabytes }
```

- [ ] Tipo de archivo validado (no solo extension)
- [ ] Tamano maximo configurado
- [ ] Los archivos no se sirven publicamente sin autenticacion
- [ ] Las rutas de Active Storage requieren login

### 7. Devise y Sesiones

- [ ] `authenticate_user!` en `ApplicationController` (ya configurado — verificar no hay bypasses)
- [ ] Controllers publicos usan `skip_before_action :authenticate_user!` solo donde necesario
- [ ] Timeout de sesion configurado en Devise initializer
- [ ] Passwords no se loguean en ninguna parte

### 8. Credenciales y Secrets

```bash
grep -r "password\|secret\|api_key\|token" config/ --include="*.rb" | grep -v "secret_key_base\|encrypted\|credentials"
```

- [ ] `config/credentials.yml.enc` en uso (no `.env` con secrets en texto plano)
- [ ] `.env` y `config/master.key` en `.gitignore`
- [ ] Ningun secret hardcodeado en initializers o modelos

### 9. CSRF

Rails incluye CSRF protection por defecto. Verificar que no esta deshabilitado:

```ruby
# MALO — deshabilita CSRF globalmente
protect_from_forgery with: :null_session

# OK — para APIs JSON (verificar que no afecta a las rutas HTML)
skip_before_action :verify_authenticity_token, if: :json_request?
```

- [ ] `protect_from_forgery` activo en ApplicationController
- [ ] Formularios Turbo incluyen CSRF token (Rails lo hace automaticamente)
- [ ] Ningun `skip_before_action :verify_authenticity_token` sin justificacion

### 10. Informacion en Errores

```ruby
# MALO — expone detalles internos
rescue_from ActiveRecord::RecordNotFound do |e|
  render json: { error: e.message, backtrace: e.backtrace }
end

# BUENO — mensaje generico
rescue_from ActiveRecord::RecordNotFound do
  render file: "public/404.html", status: :not_found
end
```

- [ ] En produccion, errores 500 muestran pagina generica
- [ ] No hay `e.message` ni `e.backtrace` en responses de produccion
- [ ] Logs no contienen RUT, telefono, ni documentos de identidad

## Ejecucion de analisis estatico

```bash
bundle exec standardrb         # detecta algunos problemas de seguridad
bundle exec erb_lint --lint-all # verifica vistas ERB
grep -rn "<%==" app/views/     # buscar raw output en vistas
grep -rn "raw(" app/views/     # buscar raw() en vistas
grep -rn "\.where(\"" app/     # buscar SQL string interpolation riesgo
```

## Reporte

Para cada hallazgo, reportar:

```
### [ALTA|MEDIA|BAJA] Descripcion del hallazgo

**Archivo:** `ruta/al/archivo.rb:linea`
**Codigo actual:**
[snippet del problema]
**Impacto:** [que puede pasar en produccion]
**Fix:** [solucion concreta con codigo]
```

## Veredicto final

- **SIN HALLAZGOS**: El codigo puede hacer PR
- **HALLAZGOS MEDIA/BAJA**: Reportar y ofrecer corregir antes del PR
- **HALLAZGOS ALTA**: BLOQUEAR el PR, corregir antes de continuar

## Reglas

- Solo reportar problemas reales (no falsos positivos)
- Siempre incluir el codigo actual y el fix propuesto
- No reportar problemas que Rails ya maneja por defecto (CSRF, escapado ERB)
- Priorizar hallazgos de autorizacion entre asociaciones — son el riesgo mas critico de yuntapp
