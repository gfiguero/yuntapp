# ADR-0007: Deploy con Kamal, Docker y Thruster

## Estado

Aceptado

## Fecha

2026-02-24

## Contexto

Se necesita una estrategia de despliegue que sea simple, reproducible y no requiera plataformas managed costosas.

## Decision

- **Kamal** como orquestador de despliegue (Rails 8 nativo).
- **Docker** con build multi-stage para imagen final liviana (ruby-slim base).
- **Thruster** como proxy HTTP integrado: compresion gzip, caching de assets, HTTP/2.
- **DigitalOcean Container Registry** para imagenes Docker.
- **Volumen persistente**: `yuntapp_storage:/rails/storage` para SQLite, Active Storage y Solid Queue/Cache/Cable.
- **Solid Queue en proceso**: `SOLID_QUEUE_IN_PUMA=true` ejecuta jobs dentro del proceso web (sin worker separado).
- **Asset bridging**: Kamal mantiene assets del deploy anterior durante la transicion para zero-downtime.
- **Usuario non-root** (uid 1000) en el container por seguridad.
- **Bootsnap precompilado** en la imagen para arranque rapido.

## Alternativas consideradas

- **Capistrano + VPS**: Mas manual, no containerizado, dificil de reproducir.
- **Fly.io / Render**: Managed pero mas costoso y menos control.
- **Kubernetes**: Sobre-ingenieria para un servidor unico.
- **Nginx/Caddy como reverse proxy**: Thruster lo reemplaza para el caso de uso actual.

## Consecuencias

- Deploy reproducible con un solo comando (`kamal deploy`).
- Sin dependencias externas (no Redis, no PostgreSQL, no Nginx).
- Limitado a un servidor. Para escalar horizontalmente, se necesitaria migrar a PostgreSQL y separar workers.
