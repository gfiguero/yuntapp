# ADR-0013: Identidad verificada como modelo separado del usuario

## Estado

Aceptado

## Fecha

2026-02-24

## Contexto

En Chile, la identidad de una persona (RUN, nombre legal) es distinta de su cuenta de usuario (email, password). Una persona puede tener multiples cuentas, y una identidad verificada puede necesitar reutilizarse.

## Decision

- **User**: Modelo Devise. Solo maneja autenticacion (email, password). Tiene flags `admin` y `superadmin`.
- **VerifiedIdentity**: Modelo separado con datos de identidad legal (RUN, first_name, last_name, phone, identity_document).
- **Relacion**: `User belongs_to :verified_identity` (opcional). Un usuario puede existir sin identidad verificada.
- **Member**: pertenencia de una `VerifiedIdentity` a una `NeighborhoodAssociation`. Tiene su propio status (pending/approved/inactive/rejected) y flag `dependent`.
- **Residency**: la estancia de una identidad en un `HouseholdUnit`, con el flag `household_admin`. Es la que vincula identidad y domicilio, y modela historial: una misma identidad puede acumular varias estancias.
- **Delegacion**: Member delega `name`, `run`, `phone`, `email`, `first_name`, `last_name` a su verified_identity.
- **Normalizacion**: VerifiedIdentity normaliza RUN (formato XX.XXX.XXX-K), nombres (capitaliza) y telefono (formato +56) en callbacks before_validation.
- **Validacion custom**: `RunValidator` valida formato y digito verificador con algoritmo modulo 11. `PhoneValidator` valida formato chileno.

## Alternativas consideradas

- **Datos de identidad en User**: Mezcla autenticacion con identidad legal. Inflexible si la persona cambia de cuenta o si multiples usuarios comparten identidad.
- **Sin modelo Member (relacion directa User-HouseholdUnit)**: No permite trackear status por domicilio ni tener multiples miembros por hogar.

## Consecuencias

- Desacoplamiento limpio: cambiar de email/password no afecta la identidad verificada.
- Un RUN solo puede existir una vez en el sistema (unicidad en VerifiedIdentity).
- La cadena User → VerifiedIdentity → Member (junta) / Residency → HouseholdUnit (domicilio) es mas larga pero cada modelo tiene responsabilidad clara.
- La delegacion de atributos en Member evita violaciones de Law of Demeter en las vistas.
- Que la identidad viva fuera de la cuenta es lo que hace posible transferirla entre cuentas por RUN duplicado (ver ADR-0014).

## Actualizaciones

**2026-08-02** — corregido contra el esquema real. La versión original de este ADR afirmaba dos cosas que dejaron de ser ciertas:

- `VerifiedIdentity` tenía `verification_status` (pending/verified/rejected): la columna fue eliminada por la migración `20260225042222_remove_verification_status_from_verified_identities_and_verified_residences`. El estado de la verificación vive hoy en las solicitudes (`IdentityVerificationRequest`) y en el `Member`.
- `Member` era el join entre `VerifiedIdentity` y `HouseholdUnit`: dejó de serlo con `20260225054342_create_residencies` y `20260225054427_remove_household_fields_from_members`. Hoy `Member` vincula identidad con **junta**, y `Residency` vincula identidad con **domicilio**.
