# ADR-0005: SQLite como base de datos principal

## Estado

Aceptado

## Fecha

2026-02-24

## Contexto

Se necesita una base de datos que sea simple de operar, no requiera infraestructura adicional, y funcione bien en un despliegue Docker de servidor unico.

## Decision

- **SQLite3** como unica base de datos para la aplicacion, cache, jobs y cable.
- Almacenada como archivo en volumen persistente Docker (`yuntapp_storage:/rails/storage`).
- Active Record como ORM con concerns custom (Filterable, Sortable) en ApplicationRecord.
- `activerecord-like` gem para queries LIKE limpias.

## Alternativas consideradas

- **PostgreSQL**: Mas robusto para concurrencia alta, pero agrega un servicio externo a operar.
- **MySQL/MariaDB**: Similar a PostgreSQL en complejidad operacional.

## Consecuencias

- Zero-ops: no hay servicio de base de datos que mantener, monitorear ni respaldar por separado.
- Backup simple: copiar un archivo.
- Limitacion: SQLite tiene restricciones en escritura concurrente. Si la app escala a multiples servidores, habra que migrar a PostgreSQL.
- El volumen Docker persistente es critico; perderlo significa perder datos.
