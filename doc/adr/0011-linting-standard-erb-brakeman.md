# ADR-0011: Linting con Standard, ERB Lint y Brakeman

## Estado

Aceptado — 2026-02-24
Revisado — 2026-06-29: se reemplaza RuboCop rails-omakase por Standard como linter unico
Revisado — 2026-08-18: se agrega el plugin `standard-rails` para recuperar las cops Rails-específicas sin reintroducir un segundo linter

## Contexto

Se necesita consistencia de estilo de codigo y deteccion temprana de vulnerabilidades de seguridad.

Mantener simultaneamente RuboCop rails-omakase y Standard Ruby genero conflictos: ambas gemas tienen reglas opuestas para `Layout/SpaceInsideHashLiteralBraces` y `Layout/SpaceInsideArrayLiteralBrackets`. Cuando una herramienta corregia el estilo, la otra lo marcaba como error. El flujo `/dev` ejecutaba `standardrb --fix` pero CI corria `rubocop`, dejando el pipeline cronicamente rojo.

### Revisión 2026-08-18 — las cops Rails, sin el segundo linter

La revisión de 2026-06-29 resolvió el conflicto de estilos, pero pagó un precio: se perdieron las cops
Rails-específicas de `rubocop-rails` (`Rails/CompactBlank`, `Rails/Blank`, `Rails/Pluck`, `Rails/FindEach`,
`Rails/RootPathnameMethods`…), que no son reglas de formato sino de idioma Rails — señalan dónde el código
reinventa algo que el framework ya resuelve.

Volver a `rubocop-rails-omakase` habría reabierto exactamente el conflicto que esta ADR cerró: omakase exige
`{ a: 1 }` y Standard `{a: 1}`, y `Layout/SpaceInsideArrayLiteralBrackets` choca igual. Medido sobre el
codebase, ese cambio habría reformateado **232 líneas en 294 archivos** sin un solo cambio de comportamiento,
además de obligar a reescribir `config/ci.rb`, `bin/standardrb`, `.standard.yml` y la skill `/check-code`.

`standard-rails` es un **plugin de Standard**, no un linter aparte: Standard sigue siendo el único ejecutable
(`bin/standardrb`), la única configuración (`.standard.yml`) y el único paso de CI. Se ganan las cops Rails
con cero churn de formato y cero cambios en el pipeline.

## Decision

- **Standard Ruby** (`standardrb`): Linter unico. Cero configuracion, opinado, mantenido activamente. Se invoca via `bin/standardrb`.
- **standard-rails**: Plugin de Standard que habilita las cops de `rubocop-rails`. No es un segundo linter — se declara en `plugins:` dentro de `.standard.yml` y corre en el mismo `bin/standardrb`.
- **ERB Lint**: Linting de templates ERB (trailing whitespace, void elements, autocomplete attributes).
- **Brakeman**: Analisis estatico de seguridad (SQL injection, XSS, mass assignment, etc.).
- **Bundler Audit**: Auditoria de vulnerabilidades conocidas en gems.

## Alternativas consideradas

- **Mantener RuboCop rails-omakase**: Tiene reglas Rails-especificas utiles, pero el costo de mantener dos linters opuestos supera el beneficio.
- **Mantener ambos linters**: Inviable en la practica — pre-commit hooks y CI generan ruido constante por reglas en conflicto.
- **Solo RuboCop sin preset**: Requiere configuracion manual extensa.
- **Volver a rubocop-rails-omakase (2026-08-18)**: Es el preset oficial de Rails, pero reabre el conflicto de
  espaciado que cerró la revisión de 2026-06-29 y obliga a un reformateo de 232 líneas sin valor funcional.
  `standard-rails` entrega el mismo beneficio —las cops Rails— sin ninguno de esos costos.

### Cops desactivadas y por qué (`.standard.yml`)

| Cop | Alcance | Motivo |
|---|---|---|
| `Rails/CreateTableWithTimestamps` | `db/migrate/**/*` | Las migraciones ya aplicadas en producción son historia inmutable |
| `Rails/Output` | `db/seeds.rb` | El `puts` de progreso de las seeds es intencional |
| `Rails/ApplicationController` | `verifications_controller.rb`, `webhooks/mercadopago_controller.rb` | Heredan de `ActionController::Base` a propósito: `ApplicationController` exige `authenticate_user!` y estos endpoints son públicos (BR-009, BR-072) |
| `Rails/LexicallyScopedActionFilter` | `users/registrations_controller.rb` | `update` lo define `Devise::RegistrationsController` en la superclase; el cop solo mira el cuerpo léxico |

## Consecuencias

- Codigo consistente sin discusiones de estilo ni reglas en conflicto.
- CI lint job mas simple (`bin/standardrb` en vez de cache + format especifico).
- Pipeline `/dev` y CI usan la misma herramienta — desaparecen las divergencias de estilo entre desarrollo y CI.
- Brakeman detecta vulnerabilidades antes de llegar a produccion.
- ERB Lint previene errores de accesibilidad (autocomplete) y formato.
- (2026-08-18) El linter ahora señala código no idiomático de Rails, no solo formato. La adopción inicial
  corrigió 41 ofensas en 37 archivos sin cambio de comportamiento (723 tests verdes antes y después).
- (2026-08-18) `config/ci.rb`, `bin/standardrb` y la skill `/check-code` no cambian: el comando sigue
  siendo el mismo. El costo de mantenimiento del plugin es la lista de exclusiones de arriba.
