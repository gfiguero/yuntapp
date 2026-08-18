# Code Reviews Pendientes

Este archivo rastrea los PRs pendientes de revision. El Desarrollador crea entradas, el Tester agrega resultados de tests, y el Reviewer aprueba o solicita cambios.

---

## Cops Rails vía `standard-rails` (plugin de Standard, no un segundo linter)

- **Autor**: [DESARROLLADOR]
- **Fecha**: 2026-08-18
- **Branch**: `worktree-refactor-standard-rails`
- **Archivos modificados**:
  - `Gemfile`, `Gemfile.lock` — `standard-rails` 1.6.0 (trae `rubocop-rails` 2.34.3)
  - `.standard.yml` — `plugins:` + 5 exclusiones con su motivo
  - 33 archivos de `app/`, `lib/` y `test/` — las correcciones automáticas
  - `doc/adr/0011-linting-standard-erb-brakeman.md` — revisión 2026-08-18
  - `CLAUDE.md`, `.claude/skills/check-code/SKILL.md`
- **Descripción**: El pedido era escribir más código Rails-way. El camino evidente —volver a
  `rubocop-rails-omakase`, el preset oficial de Rails— se midió y se descartó: reabre el conflicto de
  espaciado que cerró ADR-0011 (`Layout/SpaceInsideHashLiteralBraces`, omakase exige `{ a: 1 }` y
  Standard `{a: 1}`), reformatea **232 líneas en 294 archivos** sin un solo cambio de comportamiento y
  obliga a tocar `config/ci.rb`, `bin/standardrb` y la skill `/check-code`. `standard-rails` es un
  plugin de Standard: un solo ejecutable, una sola config, un solo paso de CI, cero churn de formato.
- **Tests**: Pasando — 723 runs / 1835 asserts / 0 fallos. **Idéntico al baseline de master**, medido
  antes y después del autofix. `standardrb` limpio (344 archivos), `erb_lint` limpio (332 archivos),
  `zeitwerk:check` OK, Brakeman 0 warnings.
- **Review**: Pendiente
- **Puntos que merecen ojo del reviewer**:
  - **Las 41 correcciones son `--fix-unsafely`**, no autofix seguro. RuboCop marca estas cops como
    unsafe porque no puede probar equivalencia semántica (p. ej. `Rails/CompactBlank` asume que el
    receptor responde a `blank?`). Se revisó el diff completo a mano y se corrió la suite antes y
    después; aun así es el punto que más merece una segunda lectura.
  - **`Rails/RedundantPresenceValidationOnBelongsTo` en `Member` y `Residency`** es el único cambio con
    efecto observable posible: quitar `validates :verified_identity_id, presence: true` mueve el error
    de validación del atributo `:verified_identity_id` al `:verified_identity`. `belongs_to` no es
    `optional` en ninguno de los dos, así que la validación se mantiene; lo que cambia es la clave del
    mensaje. Se verificó que ningún test ni i18n cuelga de `verified_identity_id`, pero si alguna vista
    renderiza errores por atributo, conviene mirarla.
  - **Las 5 exclusiones son decisiones, no ruido silenciado**: migraciones ya aplicadas
    (`Rails/CreateTableWithTimestamps`), el `puts` intencional de seeds (`Rails/Output`), los dos
    endpoints públicos que heredan de `ActionController::Base` a propósito porque
    `ApplicationController` exige `authenticate_user!` (BR-009 verificación pública, BR-072 webhook de
    MP), y el `update` que Devise define en la superclase. Cada una está comentada en `.standard.yml`.
  - **`bin/ci` completo en verde** (3m45s), incluido el paso de production parity: los 723 tests
    corren también **dentro de la imagen Docker de producción**, 0 fallos. `gh signoff` firmado sobre
    `5cb3363`; el PR queda `MERGEABLE` / `CLEAN`.

---

## Actualización de gemas: 16 al día, 3 retenidas por sus dependencias

- **Autor**: [DESARROLLADOR]
- **Fecha**: 2026-08-18
- **Branch**: `worktree-chore-actualizar-gemas`
- **Issue relacionado**: cierra los 8 PRs de Dependabot abiertos (#143, #144, #145, #147, #149, #150, #152, #153)
- **Archivos modificados**:
  - `Gemfile.lock`
- **Descripción**: `bundle update` completo. **Ruby y Rails ya estaban en la última**: Ruby 4.0.6
  (`.ruby-version`, intérprete y `ARG RUBY_VERSION` del Dockerfile ya coincidían desde el PR #81) y
  Rails 8.1.3.1 (publicada 2026-07-29, la restricción `~> 8.1` no bloqueaba nada). El trabajo real
  fueron las 19 gemas desactualizadas: 16 subieron, 3 quedan retenidas por restricciones legítimas
  de sus propias dependencias, no por nuestro Gemfile:
  - `bigdecimal` 3.3.1 (última 4.1.2) ← `ttfunk 1.8.0` exige `bigdecimal (~> 3.1)`. ttfunk es
    dependencia de Prawn, el generador del PDF de certificados. Forzar 4.x rompería la emisión.
  - `rubocop` 1.88.2 (última 1.89.0) ← `standard 1.56.0` exige `rubocop (~> 1.88.0)`.
  - `rubocop-performance` 1.26.1 (última 1.27.0) ← `standard-performance 1.9.0` exige `~> 1.26.0`.
- **Tests**: Pasando — 723 runs / 1835 asserts / 0 fallos, sin cambios respecto de master.
- **Review**: Mergeado como PR #155 (`e0090c0`) y desplegado a producción el 2026-08-18
- **Puntos que merecen ojo del reviewer**:
  - **`mercadopago-sdk` 3.2.1 → 3.4.0 es el cambio de mayor riesgo** y los tests lo mockean, así
    que no lo cubren de verdad. Verificado a mano contra el código de la gem: 3.4.0 envuelve las
    respuestas en `MPResponse`, pero es `MPResponse < Hash` y la propia gem lo documenta como
    "backward-compatible Hash wrapper" — `response[:response]`, que es lo único que usa
    `MercadopagoService`, sigue funcionando. Las excepciones tipadas nuevas (`MercadoPagoError` y
    subtipos) son **opt-in** vía `raise_for_status!`, que no llamamos, así que el manejo de errores
    no cambia. `RequestOptions.new(custom_headers:)` intacto (importa: es el vehículo del
    `x-idempotency-key` estable de #126). Los 5 recursos que usamos —`preference`, `preapproval`,
    `payment`, `invoice`, `merchant_order`— siguen existiendo. Todo lo demás del diff es aditivo
    (`search`, `capture`, paginación, tuning de reintentos).
  - **`solid_queue` 1.5.1 → 1.6.0 no requiere migración.** Comparé `db/queue_schema.rb` contra el
    template de la gem 1.6.0: mismas 11 tablas y mismos índices; solo difieren en espacios dentro
    de los corchetes (formato de Standard en nuestra copia). Los cambios de 1.6.0 son internos
    (`fiber_pool.rb`/`thread_pool.rb` nuevos, `pool.rb`/`worker.rb`/`configuration.rb`). El
    post-install message sobre breaking changes aplica a upgrades desde <1.0, no al nuestro.
  - **`resend` 1.6.0 → 1.9.0**: solo se ejercita en producción (`delivery_method = :resend`), así
    que ningún test lo cubre. Verificado que el railtie sigue registrando `add_delivery_method
    :resend, Resend::Mailer` y que `Resend::Mailer` no cambió. El diff está en automations,
    broadcasts y suppressions — APIs que no usamos.

---

## Bump de seguridad: sqlite3 2.9.6 · json 2.21.2 · brakeman 8.0.6

- **Autor**: [DESARROLLADOR]
- **Fecha**: 2026-08-18
- **Branch**: `worktree-chore-bump-gems-seguridad`
- **Issue relacionado**: bloqueaba el deploy de Batch J (`bin/ci` sin signoff)
- **Archivos modificados**:
  - `Gemfile.lock`
- **Descripción**: al preparar el deploy de Batch J, `bin/ci` falló en dos pasos de seguridad. Los
  fallos son **preexistentes en master y ajenos a Batch J** (el diff `014340e..46803d8` no toca
  `Gemfile` ni `Gemfile.lock`); aparecieron porque salieron advisories nuevos desde la última
  corrida. Este PR los resuelve para poder desplegar con el gate limpio:
  - `sqlite3` 2.9.5 → 2.9.6 — GHSA-mwm8-39rw-8826, use-after-free en argumentos de agregación.
    Es la BD de producción. Explotación requiere funciones de agregación custom, que Rails no usa,
    pero es el driver de la base y no hay razón para quedarse atrás.
  - `json` 2.21.1 → 2.21.2 — GHSA-9hj4-r449-hfvc en `JSON::ResumableParser#partial_value`. API
    opt-in que la app no usa; es dependencia transitiva.
  - `brakeman` 8.0.5 → 8.0.6 — **no es una vulnerabilidad**. Brakeman salía con exit 5 ("no es la
    última versión") y **cero hallazgos de seguridad en el código**. Gem de desarrollo, no viaja a
    producción; se sube solo para destrabar el paso del CI.
- **Tests**: Pasando — 723 runs / 1835 asserts / 0 fallos, sin cambios respecto de master.
- **Review**: Mergeado como PR #154 (`53855ed`) y desplegado a producción el 2026-08-18
- **Puntos que merecen ojo del reviewer**:
  - `bundle update --conservative` acotado a las tres gems: el diff del lock son 10 líneas, todas
    de versión. No arrastra nada más.
  - Supersede los PRs de Dependabot #148 (sqlite3) y #151 (brakeman), que quedan por cerrar. El
    bump de `json` no tenía PR de Dependabot por ser transitivo.

---

## Batch J: las 11 severidades Media de la auditoría profunda 2026-07-30

- **Autor**: [DESARROLLADOR]
- **Fecha**: 2026-08-02
- **Branch**: `worktree-fix-batch-j`
- **Issue relacionado**: `docs/2026-07-30-auditoria-profunda.md` (sección 🟡 Severidad MEDIA)
- **Descripción**: remedia las 11 Media. Guards de RUT + aviso al staff (BR-148), IDOR de
  directiva (BR-007), dependientes de socio desactivado (BR-091/099), transaccionalidad del alta
  manual (BR-024), junta activa al aprobar administración (BR-054), advertencias al staff y al
  solicitante (BR-137/139/140), `with_lock` en las transiciones de pago (BR-141), fee alineado al
  monto cobrado (BR-149), cancelación idempotente (BR-088), estado real en `success`, y borrado de
  `approved_by` vestigial (BR-077, con migración).
- **Tests**: Pasando — 723 runs / 1835 asserts / 0 fallos (+22 nuevos). `bin/ci` verde en Standard,
  ERB lint, gem + importmap audit, Brakeman, zeitwerk y tests (local y contenedor).
- **Review**: Pendiente
- **Puntos que merecen ojo del reviewer**:
  - **J1**: la auditoría sobrevaloró el hallazgo. Desde BR-121 `rut` es `NOT NULL` + `presence`,
    así que "junta sin RUT" no es alcanzable por la aplicación; los guards son defensa en
    profundidad y el valor real está en el aviso al staff cuando la emisión se rinde.
  - **J8**: en certificados no hacía falta tocar nada (`amount` es inmutable desde la creación);
    el primer intento de "limpiar el fee" era un no-op porque `compute_platform_fee` lo recalcula
    en el mismo `save`. Solo se corrigió la rama de suscripciones.
  - **J7**: `with_lock` obligó a reescribir el test de colisión de folio, que simulaba la carrera
    asignando el atributo en memoria (ahora prohibido). Se pasó al mismo `define_singleton_method`
    que ya usaba el test hermano — simula mejor la concurrencia real.
  - **J10**: severidad real menor a la reportada; el copy anterior ya decía "se está procesando".

---

<!-- Agregar nuevos PRs aqui con el siguiente formato:

## PR #XXX: Titulo del PR

- **Autor**: [nombre del agente]
- **Fecha**: YYYY-MM-DD
- **Branch**: feature/xxx o fix/xxx
- **Issue relacionado**: #XXX o BUG-XXX
- **Archivos modificados**:
  - `path/to/file1.rb`
  - `path/to/file2.html.erb`
- **Descripcion**: Breve descripcion de los cambios
- **Tests**: Pendiente / Pasando / Fallando
- **Review**: Pendiente / Aprobado / Cambios solicitados
- **Comentarios**:
  - [Tester] Resultados de tests...
  - [Reviewer] Comentarios de revision...

---

-->
