# Architecture Decision Records (ADRs)

Este archivo documenta las decisiones arquitectonicas importantes del proyecto. Cada decision tiene un ID unico y sigue el formato estandar de ADR.

---

## ADR-001: Autenticacion con Devise

- **Fecha**: 2024-01-01
- **Estado**: Aceptado
- **Contexto**: La aplicacion necesita autenticacion de usuarios con registro, login, recuperacion de password y sesiones persistentes.
- **Decision**: Usar Devise (rama main de GitHub) como solucion de autenticacion. Tres niveles de acceso: superadmin, admin y usuario/socio.
- **Consecuencias**:
  - Positivo: Solucion madura, bien documentada, extensible
  - Negativo: Dependencia en la rama main (no release estable)
- **Alternativas consideradas**:
  1. Authentication from scratch — rechazado por complejidad innecesaria
  2. Rodauth — rechazado por menor ecosistema en Rails

---

## ADR-002: Frontend con Hotwire (Turbo + Stimulus)

- **Fecha**: 2024-01-01
- **Estado**: Aceptado
- **Contexto**: Necesitamos interactividad en la UI sin introducir un framework SPA complejo.
- **Decision**: Usar Hotwire (Turbo Frames, Turbo Streams, Stimulus) para interactividad progresiva. Tailwind CSS + DaisyUI para estilos.
- **Consecuencias**:
  - Positivo: Sin build JS complejo, buen rendimiento, Rails-native
  - Negativo: Curva de aprendizaje para patrones Turbo avanzados
- **Alternativas consideradas**:
  1. React/Vue SPA — rechazado por complejidad desproporcionada
  2. ViewComponent — considerado como complemento futuro

---

## ADR-003: SQLite3 como base de datos

- **Fecha**: 2024-01-01
- **Estado**: Aceptado
- **Contexto**: Proyecto en fase inicial con deploy en VPS unico. No se requiere replicacion ni conexiones concurrentes masivas.
- **Decision**: Usar SQLite3 con Solid Queue, Solid Cache y Solid Cable para jobs, cache y websockets respectivamente.
- **Consecuencias**:
  - Positivo: Sin dependencia de servidor de BD externo, deploy simple, backups triviales
  - Negativo: Limitaciones de concurrencia si el proyecto escala significativamente
- **Alternativas consideradas**:
  1. PostgreSQL — considerado para futuro si hay necesidad de escalar

---

## ADR-004: Asset Pipeline con Propshaft + Importmap

- **Fecha**: 2024-01-01
- **Estado**: Aceptado
- **Contexto**: Rails 8 depreca Sprockets en favor de Propshaft. No necesitamos bundling JS complejo.
- **Decision**: Usar Propshaft para assets estaticos e Importmap para JavaScript sin build step.
- **Consecuencias**:
  - Positivo: Sin node_modules, sin build step, deploy mas rapido
  - Negativo: No se pueden usar librerias NPM que requieran bundling
- **Alternativas consideradas**:
  1. esbuild — rechazado por agregar complejidad innecesaria al pipeline

---

## ADR-005: Deploy con Kamal + Docker

- **Fecha**: 2024-01-01
- **Estado**: Aceptado
- **Contexto**: Necesitamos un sistema de deploy reproducible para VPS.
- **Decision**: Usar Kamal con Docker multi-stage y Thruster como proxy HTTP.
- **Consecuencias**:
  - Positivo: Zero-downtime deploys, rollback facil, infraestructura como codigo
  - Negativo: Requiere Docker en la maquina de desarrollo para builds
- **Alternativas consideradas**:
  1. Capistrano — rechazado por ser legacy comparado con Kamal
  2. Heroku/Render — rechazado por costos y menor control

---

## ADR-006: Servicio compartido de detección de RUN duplicado y transferencia de identidad

- **Fecha**: 2026-07-25
- **Estado**: Aceptado — implementado 2026-07-25 como `app/services/identity_transfer_service.rb`, invocado desde `approve_step3` y `DependentReviews#approve` (TASK-004/TASK-018)
- **Contexto**: Existen dos rutas distintas en las que se "materializa" una identidad verificada (un `Member` activo) para un RUN que ya podía pertenecer a otro `Member` activo:
  1. **Aprobación de onboarding** (`Admin::OnboardingReviewsController#approve_step3`) — el residente hace un onboarding nuevo, posiblemente en otra junta o con otra cuenta (BR-029/BR-057-059/BR-069). TASK-004.
  2. **Aprobación de dependiente** (`Admin::DependentReviewsController#approve`) — un `household_admin` activo es registrado como residente dependiente de otro `FamilyGroup` y transiciona a dependiente (BR-095/BR-096/BR-097). TASK-018.

  En ambas, la regla de negocio es la misma: si el RUN ya tiene un `Member` **activo**, ese `Member` anterior debe pasar a `inactive` en el mismo acto de aprobación, disparando la cascada a dependientes (BR-099/BR-096) y la invalidación de certificados (BR-097). Hoy ninguna de las dos rutas lo hace: ambas crean un `Member` nuevo sin tocar el anterior, permitiendo que un mismo RUN quede activo en dos roles/juntas simultáneamente.

  El mecanismo de desactivación (`Member#deactivate!`) **ya existe y ya cascadea** correctamente; lo que falta es *detectar el RUN duplicado y llamarlo* desde ambas rutas de aprobación.

- **Decisión**: Extraer la detección de RUN duplicado + desactivación del `Member` anterior a un único punto compartido (service object, p. ej. `IdentityTransferService`, o un método de dominio en `VerifiedIdentity`/`Member`), en lugar de duplicar la lógica en los dos controllers. Ambas rutas de aprobación (`approve_step3` y `DependentReviews#approve`) invocan ese punto único, que:
  1. Busca el `Member` activo previo asociado al RUN (en cualquier junta).
  2. Si existe, lo desactiva con `member.deactivate!(reason:)` (cascada + invalidación de certificados salen gratis).
  3. Deja registro auditable del motivo (transferencia de identidad / graduación / transición a dependiente).

- **Consecuencias**:
  - Positivo: Una sola implementación de un invariante crítico (BR-029: un RUN no puede estar activo en dos juntas a la vez). Cierra BR-059/BR-069/BR-095/BR-096/BR-097 con un único cambio testeable. Evita divergencia futura entre las dos rutas.
  - Negativo: Introduce una capa de servicio nueva en un codebase que hoy resuelve estas transacciones dentro de los controllers. Hay que decidir dónde vive (service object vs. método de modelo) para no romper la convención existente.
- **Alternativas consideradas**:
  1. Duplicar la lógica en cada controller — rechazado: dos copias del mismo invariante divergen con el tiempo (una de ellas ya quedó sin implementar).
  2. Callback en `Member` que al crear un nuevo `Member(approved)` desactive los previos del mismo RUN — rechazado por ahora: el disparo automático en `create` es demasiado implícito para una acción destructiva que exige `deactivation_reason` y contexto (quién aprobó, por qué); mejor un punto explícito invocado desde la aprobación.
