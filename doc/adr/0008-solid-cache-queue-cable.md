# ADR-0008: Solid Cache, Solid Queue y Solid Cable como infraestructura interna

## Estado

Aceptado

## Fecha

2026-02-24

## Contexto

La aplicacion necesita cache, background jobs y WebSockets. Tradicionalmente estos requieren Redis u otros servicios externos.

## Decision

- **Solid Cache** (`config.cache_store = :solid_cache_store`): Cache backed por SQLite.
- **Solid Queue** (`config.active_job.queue_adapter = :solid_queue`): Background jobs backed por SQLite, ejecutados dentro del proceso Puma (`SOLID_QUEUE_IN_PUMA=true`).
- **Solid Cable**: Action Cable backed por SQLite.
- Todas las bases de datos Solid se almacenan en el mismo volumen persistente.

## Alternativas consideradas

- **Redis**: Estandar de la industria para cache y jobs, pero agrega un servicio externo que operar y monitorear.
- **Sidekiq**: Potente pero requiere Redis.
- **Delayed Job**: Mas simple pero menos featureful que Solid Queue.
- **Memcached**: Solo cache, requiere servicio externo.

## Consecuencias

- Cero dependencias externas. Todo corre en un solo proceso con SQLite.
- Operacionalmente simple: un backup del volumen cubre todo.
- Solid Queue en proceso es adecuado para carga moderada. Si se necesitan jobs pesados o concurrentes, habra que separar workers.
