# ADR-0011: Linting con RuboCop (rails-omakase), Standard, ERB Lint y Brakeman

## Estado

Aceptado

## Fecha

2026-02-24

## Contexto

Se necesita consistencia de estilo de codigo y deteccion temprana de vulnerabilidades de seguridad.

## Decision

- **RuboCop** con preset `rails-omakase`: Estilo oficial de Rails 8, opinado y sin configuracion extra.
- **Standard Ruby**: Complementa RuboCop con reglas adicionales de estilo.
- **ERB Lint**: Linting de templates ERB (trailing whitespace, void elements, autocomplete attributes).
- **Brakeman**: Analisis estatico de seguridad (SQL injection, XSS, mass assignment, etc.).
- **Bundler Audit**: Auditoria de vulnerabilidades conocidas en gems.

## Alternativas consideradas

- **Sin linting**: Inconsistencia de estilo, mas fricccion en code review.
- **Solo RuboCop sin preset**: Requiere configuracion manual extensa.
- **Prettier para ERB**: Menos integrado con el ecosistema Ruby.

## Consecuencias

- Codigo consistente sin discusiones de estilo.
- Brakeman detecta vulnerabilidades antes de llegar a produccion.
- ERB Lint previene errores de accesibilidad (autocomplete) y formato.
