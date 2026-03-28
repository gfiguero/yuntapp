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
