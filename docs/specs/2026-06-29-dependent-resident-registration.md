---
Status: approved
Feature: dependent-resident-registration
Date: 2026-06-29
---

# Spec: Registro de Residentes Dependientes

## Contexto

Un `household_admin` puede registrar residentes dependientes (hijos menores) en su `FamilyGroup`.
El dependiente no tiene cuenta de usuario — el padre actúa en su nombre. La junta de vecinos
debe verificar la identidad del dependiente mediante documentación antes de aprobarlo.

Se reutiliza `IdentityVerificationRequest` con el flag `dependent: true` para aprovechar
la detección de RUN duplicado existente (BR-057 a BR-059), lo que permite la "graduación"
automática cuando el hijo crezca y haga su propio onboarding independiente.

## Reglas de Negocio Nuevas

| ID | Categoría | Regla |
|----|-----------|-------|
| BR-065 | Residencia | El `household_admin` puede registrar residentes dependientes (menores de edad) en su `FamilyGroup` sin que estos tengan cuenta de usuario |
| BR-066 | Identidad | El admin de la junta debe verificar la identidad del dependiente con documentación antes de aprobarlo, igual que en el onboarding estándar |
| BR-067 | Residencia | Al aprobar un dependiente, se crea `VerifiedIdentity` + `Member(dependent: true)` + `Residency(household_admin: false)` usando la `VerifiedResidence` del `FamilyGroup` del padre |
| BR-068 | Identidad | El teléfono es opcional para dependientes (menores pueden no tenerlo) |
| BR-069 | Graduación | Cuando un dependiente crece y hace su propio onboarding en cualquier junta, el mecanismo existente de RUN duplicado (BR-057-059) detecta la coincidencia. Al aprobar, el `Member(dependent: true)` anterior pasa a `inactive` automáticamente |

## Cambios en Modelos

### Migraciones necesarias

**1. `identity_verification_requests`**
- `dependent: boolean, default: false, null: false`
- `family_group_id: integer` (FK a `family_groups`) — grupo familiar al que pertenece el dependiente
- `requested_by_id: integer` (FK a `users`) — el `household_admin` que creó la solicitud
- `neighborhood_association_id: integer` (FK a `neighborhood_associations`) — para filtrado multi-tenant en el admin
- `user_id`: cambiar de `null: false` a nullable (el dependiente no tiene `User`)

**2. `members`**
- `dependent: boolean, default: false, null: false`

### Cambios en `IdentityVerificationRequest`
- `belongs_to :user, optional: true` (ya no obligatorio)
- `belongs_to :requested_by, class_name: "User", optional: true`
- `belongs_to :family_group, optional: true`
- `belongs_to :neighborhood_association, optional: true`
- Validación de `phone`: omitir si `dependent?`
- Nuevo método: `dependent?`
- Validación: si `dependent?`, requiere `family_group_id` y `requested_by_id`

### Cambios en `Member`
- Nuevo método: `dependent?`
- Scope: `dependent` y `independent`

## Flujo Completo

```
household_admin ingresa a "Mis dependientes" en el panel
    │
    ▼
Completa formulario: nombre, apellido, RUN, documentos
    │  Crea IdentityVerificationRequest(dependent: true, status: pending,
    │  family_group_id, requested_by_id, neighborhood_association_id)
    ▼
Admin de la junta ve nueva solicitud de dependiente en su panel
    │  Sección separada de los onboardings normales
    ▼
Admin revisa documentos y aprueba
    │  Transacción:
    │    1. VerifiedIdentity.find_or_initialize_by(run:) → save!
    │    2. Member.create!(dependent: true, neighborhood_association:,
    │                      requested_by: household_admin_user,
    │                      approved_by: current_admin_user, status: approved)
    │    3. Residency.create!(verified_identity:, household_admin: false,
    │                         family_group:, household_unit: family_group.household_unit,
    │                         verified_residence: family_group.household_unit.verified_residence,
    │                         status: approved)
    │    4. identity_verification_request.update!(status: approved)
    ▼
household_admin puede solicitar certificado a nombre del dependiente
    │  ResidenceCertificate → Member(dependent: true) del hijo
    ▼
PDF del certificado muestra nombre y RUN del hijo, misma dirección
```

## Archivos a Crear / Modificar

### Migraciones
1. `db/migrate/TIMESTAMP_add_dependent_fields_to_identity_verification_requests.rb`
2. `db/migrate/TIMESTAMP_add_dependent_to_members.rb`

### Modelos
3. `app/models/identity_verification_request.rb` — flags, asociaciones, validaciones condicionales
4. `app/models/member.rb` — flag `dependent`, scope

### Panel (household_admin)
5. `app/controllers/panel/dependents_controller.rb` — `index`, `new`, `create`
6. `app/views/panel/dependents/index.html.erb`
7. `app/views/panel/dependents/new.html.erb`

### Admin (junta)
8. `app/controllers/admin/dependent_reviews_controller.rb` — `index`, `show`, `approve`, `reject`
9. `app/views/admin/dependent_reviews/index.html.erb`
10. `app/views/admin/dependent_reviews/show.html.erb`

### Rutas
11. `config/routes.rb` — `panel/dependents` y `admin/dependent_reviews`

### I18n
12. `config/locales/es.yml` — claves para panel y admin

### Tests
13. `test/models/identity_verification_request_test.rb` — tests del flag dependent
14. `test/models/member_test.rb` — tests del flag dependent
15. `test/controllers/panel/dependents_controller_test.rb`
16. `test/controllers/admin/dependent_reviews_controller_test.rb`
17. `test/fixtures/identity_verification_requests.yml` — fixtures dependientes
18. `test/fixtures/members.yml` — fixtures dependent members

## Decisiones de Diseño

- **`user_id` nullable**: Se permite null en `IdentityVerificationRequest.user_id` para
  dependientes. El padre queda registrado en `requested_by_id`.
- **Sin paso draft**: La solicitud del dependiente inicia directamente en `pending` —
  el formulario es simple (sin los 4 pasos del onboarding).
- **Verificación de residencia omitida**: El dependiente hereda la `VerifiedResidence`
  del `FamilyGroup` del padre. No hay `ResidenceVerificationRequest`.
- **`dependent` en `Member` vs `user_id: nil`**: Flag explícito para que el código sea
  autodocumentado y las queries sean claras (`Member.dependent`).
- **Multi-tenancy en admin**: `neighborhood_association_id` en la solicitud permite
  filtrar sin joins costosos.
- **Graduación automática**: Al hacer onboarding independiente, BR-059 desactiva el
  `Member(dependent: true)` anterior cuando el admin aprueba el nuevo onboarding
  (mismo mecanismo que RUN duplicado entre juntas).

## Seguridad

- Solo el `household_admin` puede crear solicitudes de dependientes (`ensure_household_admin!`)
- El admin solo ve solicitudes de su propia junta (filtro por `neighborhood_association_id`)
- Strong params en ambos controladores — no exponer `dependent`, `family_group_id` ni `neighborhood_association_id` al usuario
- El `household_admin` solo puede ver los dependientes de su propio `FamilyGroup`
