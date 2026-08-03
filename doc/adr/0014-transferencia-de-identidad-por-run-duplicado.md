# ADR-0014: Servicio compartido de detección de RUN duplicado y transferencia de identidad

## Estado

Aceptado — implementado el 2026-07-25 como `app/services/identity_transfer_service.rb`, invocado desde `Admin::OnboardingReviewsController#approve_step3` y `Admin::DependentReviewsController#approve` (TASK-004/TASK-018).

> Procede de `.claude/team/architecture/decisions.md` (donde figuraba como ADR-006), unificado aquí el 2026-08-02. Ver `README.md` de este directorio.

## Fecha

2026-07-25

## Contexto

Existen dos rutas distintas en las que se "materializa" una identidad verificada — es decir, se crea un `Member` activo — para un RUN que ya podía pertenecer a otro `Member` activo:

1. **Aprobación de onboarding** (`Admin::OnboardingReviewsController#approve_step3`): el residente hace un onboarding nuevo, posiblemente en otra junta o con otra cuenta (BR-029, BR-057–059, BR-069). TASK-004.
2. **Aprobación de dependiente** (`Admin::DependentReviewsController#approve`): un `household_admin` activo es registrado como residente dependiente de otro `FamilyGroup` y transiciona a dependiente (BR-095, BR-096, BR-097). TASK-018.

En ambas la regla es la misma: si el RUN ya tiene un `Member` **activo**, ese `Member` anterior debe pasar a `inactive` en el mismo acto de aprobación, disparando la cascada a sus dependientes (BR-096/BR-099) y la invalidación de sus certificados (BR-097).

El mecanismo de desactivación (`Member#deactivate!`) ya existía y ya cascadeaba correctamente. Lo que faltaba era *detectar el RUN duplicado y llamarlo* desde ambas rutas — ninguna de las dos lo hacía, de modo que un mismo RUN podía quedar activo en dos roles o juntas simultáneamente.

## Decisión

Extraer la detección de RUN duplicado y la desactivación del `Member` anterior a un **punto único compartido** —`IdentityTransferService.deactivate_prior_memberships!(verified_identity, reason:)`— en lugar de duplicar la lógica en los dos controllers. Ambas rutas de aprobación lo invocan, y el servicio:

1. Busca las membresías aprobadas previas de esa identidad, en cualquier junta.
2. Si existen, las desactiva con `deactivate!(reason:)` — la cascada y la invalidación de certificados salen gratis.
3. Deja registro auditable del motivo (transferencia de identidad, graduación, transición a dependiente).

**Restricción de orden**: debe invocarse **antes** de crear la nueva `Residency`/`Member`. La cascada de `deactivate!` resuelve el `household_admin` anterior por su residencia aprobada más reciente, y una residencia nueva de la misma identidad la confundiría.

## Alternativas consideradas

- **Duplicar la lógica en cada controller**: rechazado — dos copias del mismo invariante divergen con el tiempo, y de hecho una de ellas ya había quedado sin implementar.
- **Callback en `Member` que al crear un `Member(approved)` desactive los previos del mismo RUN**: rechazado — el disparo automático en `create` es demasiado implícito para una acción destructiva que exige `deactivation_reason` y contexto (quién aprobó y por qué). Mejor un punto explícito invocado desde la aprobación.

## Consecuencias

- Una sola implementación de un invariante crítico: un RUN no puede estar activo en dos juntas a la vez (BR-029). Cierra BR-059, BR-069, BR-095, BR-096 y BR-097 con un cambio único y testeable.
- Evita divergencia futura entre las dos rutas de aprobación.
- Introduce una capa de servicio en un codebase que resuelve la mayoría de estas transacciones dentro de los controllers. Se aceptó por tratarse de un invariante compartido; no es una invitación a mover toda la lógica de dominio a servicios.
- El orden de invocación es una precondición frágil: está documentada en el propio servicio, pero no forzada por el código.
