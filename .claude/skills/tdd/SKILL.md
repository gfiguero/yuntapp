---
name: tdd
description: Workflow TDD con Minitest y fixtures para yuntapp. Tests ANTES del codigo. Patron Arrange-Act-Assert con fixtures YAML, no factories.
user-invocable: true
allowed-tools:
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - Bash(bin/rails test*)
  - Bash(ls test/*)
  - Bash(grep*)
---

# TDD Workflow — yuntapp (Minitest + Fixtures)

Workflow TDD adaptado para el stack de yuntapp: Minitest, fixtures YAML, Rails 8.1.1. No usa RSpec ni FactoryBot.

## Input

`$ARGUMENTS` — Descripcion de lo que se va a testear. Ejemplos:
- `/tdd Member#approve! cambia status a approved`
- `/tdd Admin::MembersController#create crea member correctamente`
- `/tdd ResidenceCertificate genera folio unico`

## Principio fundamental

**Tests PRIMERO. Siempre.**

```
1. Escribir test (falla en rojo)
2. Implementar minimo codigo para que pase (verde)
3. Refactorizar manteniendo tests en verde
```

## Stack de testing en yuntapp

| Herramienta | Uso |
|-------------|-----|
| Minitest | Framework de tests |
| Fixtures YAML | Datos de prueba (no factories) |
| `test/models/` | Tests de modelos |
| `test/controllers/` | Tests de controladores |
| SimpleCov | Cobertura de codigo |
| `bin/rails test` | Ejecutar suite |

## Paso 1: Entender el comportamiento a testear

Antes de escribir el test, leer:
1. El modelo/controlador existente (si aplica)
2. Los fixtures actuales en `test/fixtures/`
3. Tests existentes similares como referencia de patron

## Paso 2: Escribir los tests (primero)

### Tests de Modelo

```ruby
# test/models/member_test.rb
require "test_helper"

class MemberTest < ActiveSupport::TestCase
  # Arrange: usar fixtures YAML
  setup do
    @member = members(:pending_member)
    @association = neighborhood_associations(:junta_maipu)
  end

  # Happy path
  test "approve! cambia status a approved" do
    # Act
    @member.approve!(approved_by: users(:admin_user))
    # Assert
    assert_equal "approved", @member.status
    assert_not_nil @member.approved_at
    assert_equal users(:admin_user), @member.approved_by
  end

  # Edge case
  test "approve! falla si ya esta aprobado" do
    @member.update!(status: "approved")
    assert_raises(ActiveRecord::RecordInvalid) do
      @member.approve!(approved_by: users(:admin_user))
    end
  end

  # Validaciones
  test "invalido sin run" do
    @member.run = nil
    assert_not @member.valid?
    assert_includes @member.errors[:run], "can't be blank"
  end
end
```

### Tests de Controlador

```ruby
# test/controllers/admin/members_controller_test.rb
require "test_helper"

class Admin::MembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin_user)
    @association = neighborhood_associations(:junta_maipu)
    sign_in @admin
  end

  # Happy path
  test "GET index muestra lista de miembros" do
    get admin_members_path
    assert_response :success
  end

  # Autorizacion — critico en yuntapp
  test "admin no puede ver miembros de otra asociacion" do
    other_member = members(:member_otra_asociacion)
    get admin_member_path(other_member)
    assert_response :not_found
  end

  # Sin autenticacion
  test "redirige si no autenticado" do
    sign_out @admin
    get admin_members_path
    assert_redirected_to new_user_session_path
  end

  # Superadmin
  test "superadmin puede ver cualquier miembro" do
    sign_in users(:superadmin_user)
    get admin_member_path(members(:member_otra_asociacion))
    assert_response :success
  end
end
```

### Patrones Minitest para yuntapp

```ruby
# Assertions mas usadas en Rails/Minitest
assert_equal expected, actual          # igualdad
assert_not condition                   # negacion
assert_nil value                       # nil
assert_not_nil value                   # no nil
assert_includes collection, item       # inclusion
assert_difference "Model.count", 1     # cambio en count
assert_no_difference "Model.count"     # sin cambio
assert_redirected_to path              # redirect
assert_response :success/:not_found    # HTTP status
assert_turbo_stream action: "replace"  # Turbo Streams

# Para autenticacion con Devise en tests
sign_in user
sign_out user
```

## Paso 3: Ejecutar tests (deben fallar)

```bash
bin/rails test test/models/member_test.rb
# Expected: RED — los tests fallan porque no esta implementado aun
```

Confirmar que los tests fallan por la razon correcta (comportamiento no implementado), no por errores de sintaxis o fixtures faltantes.

## Paso 4: Crear/actualizar fixtures si es necesario

```yaml
# test/fixtures/members.yml
pending_member:
  status: pending
  verified_identity: verified_garri
  household_unit: casa_maipu
  requested_by: user_regular
  neighborhood_association: junta_maipu

approved_member:
  status: approved
  verified_identity: verified_carmen
  household_unit: casa_maipu
  requested_by: user_regular
  approved_by: admin_user
  approved_at: 2026-01-15 10:00:00
  neighborhood_association: junta_maipu

member_otra_asociacion:
  status: approved
  verified_identity: verified_pedro
  household_unit: casa_providencia
  neighborhood_association: junta_providencia
```

Reglas de fixtures:
- Nombrar descriptivamente (no `member_1`, `member_2`)
- Cubrir todos los estados (pending, approved, rejected)
- Incluir fixtures para casos de borde (otra asociacion, sin datos opcionales)
- Usar referencias por nombre (no IDs hardcodeados)

## Paso 5: Implementar el codigo minimo

Implementar solo lo necesario para que los tests pasen. No agregar logica extra "por si acaso".

```bash
bin/rails test test/models/member_test.rb
# Expected: GREEN — todos los tests pasan
```

Si un test falla: corregir la implementacion, no el test.

## Paso 6: Refactorizar

Mejorar el codigo manteniendo los tests en verde:

```bash
bin/rails test test/models/member_test.rb
# Debe seguir en GREEN despues de cada refactor
```

## Paso 7: Verificar cobertura

```bash
bin/rails test
# SimpleCov genera reporte en coverage/index.html
```

Meta: mantener cobertura de lineas > 80%.

## Casos a testear siempre

Para cada feature, cubrir estos casos:

| Caso | Ejemplo |
|------|---------|
| Happy path | accion exitosa con datos validos |
| Validacion | datos invalidos → error esperado |
| Autorizacion | usuario sin permiso → redirect/404 |
| Borde | nil, string vacio, valor maximo |
| Aislamiento de asociacion | admin no ve datos de otra asociacion |

## Ejecutar tests rapidamente

```bash
bin/rails test                                    # suite completa
bin/rails test test/models/member_test.rb         # un archivo
bin/rails test test/models/member_test.rb:42      # una linea especifica
bin/rails test test/models/ test/controllers/     # multiples directorios
```

## Reglas

- **Tests primero**: Nunca escribir implementacion antes del test
- **Fixtures, no factories**: Usar YAML fixtures, no FactoryBot
- **Sin mocks de BD**: Tests de integracion usan SQLite3 real (test database)
- **Un assert por comportamiento**: Tests enfocados y legibles
- **Nombres descriptivos**: `test "approve! cambia status a approved"` no `test "test1"`
- **Aislar asociaciones**: Siempre testear que un admin no puede ver datos de otra asociacion
- **Tests de regresion**: Para cada bug corregido, escribir primero el test que lo reproduce
