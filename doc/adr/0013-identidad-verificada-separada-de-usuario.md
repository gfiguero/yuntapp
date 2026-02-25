# ADR-0013: Identidad verificada como modelo separado del usuario

## Estado

Aceptado

## Fecha

2026-02-24

## Contexto

En Chile, la identidad de una persona (RUN, nombre legal) es distinta de su cuenta de usuario (email, password). Una persona puede tener multiples cuentas, y una identidad verificada puede necesitar reutilizarse.

## Decision

- **User**: Modelo Devise. Solo maneja autenticacion (email, password). Tiene flags `admin` y `superadmin`.
- **VerifiedIdentity**: Modelo separado con datos de identidad legal (RUN, first_name, last_name, phone, identity_document). Tiene `verification_status` (pending/verified/rejected).
- **Relacion**: `User belongs_to :verified_identity` (opcional). Un usuario puede existir sin identidad verificada.
- **Member**: Modelo join que vincula `VerifiedIdentity` con `HouseholdUnit`. Tiene su propio status (pending/approved/rejected) y flag `household_admin`.
- **Delegacion**: Member delega `name`, `run`, `phone`, `email`, `first_name`, `last_name` a su verified_identity.
- **Normalizacion**: VerifiedIdentity normaliza RUN (formato XX.XXX.XXX-K), nombres (capitaliza) y telefono (formato +56) en callbacks before_validation.
- **Validacion custom**: `RunValidator` valida formato y digito verificador con algoritmo modulo 11. `PhoneValidator` valida formato chileno.

## Alternativas consideradas

- **Datos de identidad en User**: Mezcla autenticacion con identidad legal. Inflexible si la persona cambia de cuenta o si multiples usuarios comparten identidad.
- **Sin modelo Member (relacion directa User-HouseholdUnit)**: No permite trackear status por domicilio ni tener multiples miembros por hogar.

## Consecuencias

- Desacoplamiento limpio: cambiar de email/password no afecta la identidad verificada.
- Un RUN solo puede existir una vez en el sistema (unicidad en VerifiedIdentity).
- La cadena User → VerifiedIdentity → Member → HouseholdUnit es mas larga pero cada modelo tiene responsabilidad clara.
- La delegacion de atributos en Member evita violaciones de Law of Demeter en las vistas.
