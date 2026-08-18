# Architecture Decision Records

Este directorio es la **fuente única** de los ADRs de Yuntapp. Cada archivo documenta una decisión con su contexto, las alternativas que se evaluaron y sus consecuencias.

Hasta el 2026-08-02 convivían dos conjuntos de ADRs con numeraciones que colisionaban entre sí: este directorio (`0001`–`0013`) y `.claude/team/architecture/decisions.md` (`ADR-001`–`ADR-006`). Se unificaron aquí; aquel archivo quedó como puntero.

## Índice

| ADR | Título | Estado |
|-----|--------|--------|
| [0001](0001-manejo-de-fechas-y-zona-horaria.md) | Manejo de fechas, zona horaria y formato de visualización | Aceptado |
| [0002](0002-autenticacion-y-autorizacion-tres-niveles.md) | Autenticación y autorización con tres niveles de acceso | Aceptado |
| [0003](0003-asset-pipeline-importmap-propshaft.md) | Asset pipeline con Importmap + Propshaft | Aceptado |
| [0004](0004-frontend-hotwire-tailwind-daisyui.md) | Frontend con Hotwire, Tailwind y DaisyUI | Aceptado |
| [0005](0005-sqlite-como-base-de-datos.md) | SQLite como base de datos principal | Aceptado |
| [0006](0006-status-como-constantes-string.md) | Status como constantes string (sin enums de Rails) | Aceptado |
| [0007](0007-deploy-kamal-docker-thruster.md) | Deploy con Kamal, Docker y Thruster | Aceptado |
| [0008](0008-solid-cache-queue-cable.md) | Solid Cache, Solid Queue y Solid Cable sobre SQLite | Aceptado |
| [0009](0009-internacionalizacion-espanol-primario.md) | Internacionalización con español como idioma primario | Aceptado |
| [0010](0010-testing-minitest-fixtures.md) | Testing con Minitest y fixtures YAML | Aceptado |
| [0011](0011-linting-standard-erb-brakeman.md) | Linting con Standard, ERB Lint y Brakeman | Aceptado |
| [0012](0012-onboarding-multi-paso-con-session-y-turbo-streams.md) | Onboarding multi-paso con session y Turbo Streams | Aceptado |
| [0013](0013-identidad-verificada-separada-de-usuario.md) | Identidad verificada como modelo separado del usuario | Aceptado (actualizado 2026-08-02) |
| [0014](0014-transferencia-de-identidad-por-run-duplicado.md) | Servicio compartido de detección de RUN duplicado y transferencia de identidad | Aceptado (implementado) |
| [0015](0015-system-tests-por-caso-de-uso.md) | System tests por caso de uso, con production parity | Aceptado |

## Cómo agregar un ADR

1. Toma el siguiente número disponible con cuatro dígitos: `00NN-titulo-en-kebab-case.md`.
2. Usa las secciones del formato existente: `Estado`, `Fecha`, `Contexto`, `Decisión`, `Alternativas consideradas`, `Consecuencias`.
3. Agrega la fila al índice de arriba.
4. No renumeres ni borres ADRs existentes. Si una decisión se revierte, marca su estado como `Reemplazado por ADR-00NN` y explica por qué; si solo cambian los hechos, añade una sección `Actualizaciones` con la fecha (como en el 0013).

Las **reglas de negocio** (BR-XXX) no van aquí: viven en la tabla de `CLAUDE.md`. Un ADR explica una decisión técnica y sus alternativas; una BR define qué debe cumplir el sistema.
