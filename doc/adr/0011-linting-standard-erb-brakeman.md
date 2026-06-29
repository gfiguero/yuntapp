# ADR-0011: Linting con Standard, ERB Lint y Brakeman

## Estado

Aceptado — 2026-02-24
Revisado — 2026-06-29: se reemplaza RuboCop rails-omakase por Standard como linter unico

## Contexto

Se necesita consistencia de estilo de codigo y deteccion temprana de vulnerabilidades de seguridad.

Mantener simultaneamente RuboCop rails-omakase y Standard Ruby genero conflictos: ambas gemas tienen reglas opuestas para `Layout/SpaceInsideHashLiteralBraces` y `Layout/SpaceInsideArrayLiteralBrackets`. Cuando una herramienta corregia el estilo, la otra lo marcaba como error. El flujo `/dev` ejecutaba `standardrb --fix` pero CI corria `rubocop`, dejando el pipeline cronicamente rojo.

## Decision

- **Standard Ruby** (`standardrb`): Linter unico. Cero configuracion, opinado, mantenido activamente. Se invoca via `bin/standardrb`.
- **ERB Lint**: Linting de templates ERB (trailing whitespace, void elements, autocomplete attributes).
- **Brakeman**: Analisis estatico de seguridad (SQL injection, XSS, mass assignment, etc.).
- **Bundler Audit**: Auditoria de vulnerabilidades conocidas en gems.

## Alternativas consideradas

- **Mantener RuboCop rails-omakase**: Tiene reglas Rails-especificas utiles, pero el costo de mantener dos linters opuestos supera el beneficio.
- **Mantener ambos linters**: Inviable en la practica — pre-commit hooks y CI generan ruido constante por reglas en conflicto.
- **Solo RuboCop sin preset**: Requiere configuracion manual extensa.

## Consecuencias

- Codigo consistente sin discusiones de estilo ni reglas en conflicto.
- CI lint job mas simple (`bin/standardrb` en vez de cache + format especifico).
- Pipeline `/dev` y CI usan la misma herramienta — desaparecen las divergencias de estilo entre desarrollo y CI.
- Brakeman detecta vulnerabilidades antes de llegar a produccion.
- ERB Lint previene errores de accesibilidad (autocomplete) y formato.
