# Archivo de code reviews (2026-08)

Entradas movidas desde `pending.md` durante el saneo del 2026-08-20. **Todos estos PRs ya estan
mergeados**; ninguno tiene revision formal registrada. Se conservan porque los "Puntos que merecen ojo
del reviewer" documentan decisiones y verificaciones manuales que no viven en el codigo — sobre todo la
verificacion del SDK de MercadoPago 3.4.0 y del schema de Solid Queue 1.6.0, que los tests mockean.

---

## Aislamiento entre núcleos familiares en certificados (BR-041) + saneo de reglas de ámbito

- **Autor**: [DESARROLLADOR]
- **Fecha**: 2026-08-19
- **Branch**: `worktree-fix-aislamiento-nucleo-familiar`
- **Archivos modificados**:
  - `app/controllers/panel/residence_certificates_controller.rb` — filtro por `family_group` y fuente única
  - `test/controllers/panel/residence_certificates_controller_test.rb` — 2 tests nuevos
  - `CLAUDE.md` — BR-021 y BR-032 retiradas, BR-150/BR-151 nuevas, BR-022/034/035/041/098 corregidas
- **Tests**: 727 runs / 1883 asserts / 0 fallos. `standardrb` limpio (351 archivos).
- **Review**: no quedo registrada en este archivo; mergeado como PR #159 (`7acc76d`) el 2026-08-19, con el PR #160 (`093b84a`) limpiando un archivo que se colo
- **Puntos que merecen ojo del reviewer**:
  - **Los dos tests se vieron fallar antes del fix.** El del POST manipulado fallaba con
    `ResidenceCertificate.count didn't change by 0, but by 1` — o sea que la emisión cruzada era real,
    no teórica.
  - **Eran dos vectores, no uno.** Filtrar solo `selectable_residencies` habría dejado abierto el
    `create`, que releía `current_residencies` por su cuenta. Su comentario ya afirmaba ser "la misma
    fuente que el selector" sin serlo; ahora lo es de verdad.
  - **La decisión de fondo fue del owner**, no técnica: BR-041 (aislar) vs BR-098 (alcance por
    domicilio) estaban en conflicto explícito y ambas vigentes. Si el reviewer discrepa, la discusión
    es sobre la regla, no sobre el código.
  - **Impacto en datos existentes: ninguno.** El filtro solo restringe lo que se ofrece; no toca
    certificados ya emitidos. Vale la pena revisar en producción si algún certificado vigente fue
    emitido cruzando núcleos —hoy improbable, porque hacen falta dos `FamilyGroup` en una dirección.
  - **`current_residencies` sigue sin filtrar por núcleo** y es correcto que así sea: su docstring
    advierte que no se use para autorización. El filtro vive en el llamador. Si aparece un tercer
    consumidor, conviene revisar que también lo aplique.

---

## Suite de system tests por caso de uso + production parity (ADR-0015)

- **Autor**: [TESTER]
- **Fecha**: 2026-08-18
- **Branch**: `worktree-test-system-suite`
- **Archivos nuevos**:
  - `compose.test.yml`, `bin/system-tests-docker` — el modo con production parity
  - `test/system/registration_test.rb` (UC-001), `residence_certificate_request_test.rb` (UC-003),
    `residence_certificate_download_test.rb` (UC-006), `certificate_verification_test.rb` (UC-007),
    `administration_request_test.rb` (UC-008)
  - `doc/adr/0015-system-tests-por-caso-de-uso.md`
- **Modificados**: `test/application_system_test_case.rb` (dos modos), `config/ci.rb` (dos pasos),
  `CLAUDE.md`, `doc/adr/README.md`
- **Tests**: `bin/rails test` 723 / 0 fallos. `bin/rails test:system` **7 runs / 75 assertions / 0
  fallos en 14.3s**. `standardrb` limpio (350 archivos).
- **Review**: no quedo registrada en este archivo; mergeado como PR #158 el 2026-08-18
- **Puntos que merecen ojo del reviewer**:
  - **UC-004 y UC-005 no tienen system test, a propósito.** El núcleo de ambos es un webhook y un job:
    no hay navegador que los recorra. Si el reviewer cree que igual deberían existir, es una discusión
    de ADR-0015, no de este PR.
  - **UC-006 llega hasta el enlace de descarga, no descarga el archivo.** Verificar el binario exigiría
    configurar el directorio de descargas de Chrome; el `send_data` ya está cubierto en el controller
    test. La frontera está escrita en el propio test.
  - **La detección de IP del contenedor** (`Socket.ip_address_list`) es la parte más frágil del
    montaje. Fue necesaria porque `docker compose run` no resuelve el alias `app` desde el contenedor
    de Chrome. Si alguien cambia a `docker compose up`, esto se puede simplificar.
  - **El CI ahora corre los system tests dos veces** (local y contra la imagen). Es deliberado: el
    local falla temprano, antes del build Docker, siguiendo la filosofía que ya declaraba `config/ci.rb`.
    Si el tiempo molesta, lo primero que yo quitaría es la pasada local, no la de parity.
  - **Fix de i18n incluido**: un RUT inválido mostraba `Translation missing: es.…` al usuario final.
    Al medir el alcance resultaron **seis** claves faltantes, no una (`AdministrationRequest#organization_rut`,
    `#run` y `NeighborhoodAssociation#rut`, en formato y dígito verificador). Se resolvió moviendo las
    traducciones de `RunValidator` al fallback global `es.errors.messages` en vez de seguir
    duplicándolas por modelo, más `test/models/rut_error_messages_test.rb` como guard.
    **Nota para el reviewer**: `en.yml` no tiene ninguna de estas claves. No se tocó porque el locale
    por defecto es `es` y ampliar a `en` excede este PR, pero queda anotado.

---

## System test piloto de UC-002 (onboarding en Chrome headless)

- **Autor**: [TESTER]
- **Fecha**: 2026-08-18
- **Branch**: `worktree-test-onboarding-system`
- **Archivos modificados**:
  - `test/system/onboarding_test.rb` — nuevo, el primer system test del proyecto
  - `config/ci.rb` — paso `Tests: system (Chrome headless)`
  - `CLAUDE.md` — sección Tests
- **Descripción**: Piloto para medir el costo real de un system test antes de decidir la estrategia
  completa. La infraestructura ya existía sin usar: `test/application_system_test_case.rb` está
  configurado con `headless_chrome` desde siempre y `test/system/` estaba vacío.
- **Tests**: `bin/rails test` 723 runs / 0 fallos (sin cambios). `bin/rails test:system` 1 run /
  26 assertions / 0 fallos en 9.6s. `standardrb` limpio (345 archivos).
- **Review**: no quedo registrada en este archivo; mergeado como PR #157 el 2026-08-18
- **Puntos que merecen ojo del reviewer**:
  - **El test se validó por mutación, no solo por pasar en verde.** Pasó a la primera, lo que no prueba
    nada, así que se rompió el código a propósito dos veces: (a) quitar
    `identity_verification_request&.update!(status: "pending")` de `submit!` → falla en la aserción de
    BR-017; (b) dejar el select de comuna `disabled: true` → falla esperando el cascading. Ambas
    revertidas. La segunda es el argumento entero del piloto: es un bug que solo un browser ve.
  - **`bin/rails test` no incluye system tests.** Rails los excluye por defecto. Sin el paso nuevo en
    `config/ci.rb` el test existiría sin correr nunca. Vale la pena que alguien más confirme que el
    paso quedó donde corresponde.
  - **Los system tests no corren en el contenedor** — la imagen de producción no trae Chrome. O sea
    que este nivel de test no tiene production parity, a diferencia del resto de la suite.
  - **El test espera señales del servidor, no `sleep`.** El autosave tiene 2s de debounce; en vez de
    dormir, se espera a que el botón "Continuar" se habilite, que es el turbo_stream confirmando que
    el paso quedó guardado. Si aparece flakiness, ese es el primer lugar donde mirar.
  - **Depende de fixtures con datos aleatorios**: los nombres de `neighborhood_delegations` se generan
    con `sample`/`rand`, así que el test lee el nombre en runtime en vez de hardcodearlo.

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
- **Review**: no quedo registrada en este archivo; mergeado como PR #156 el 2026-08-18
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
- **Review**: no quedo registrada en este archivo; mergeado como PR #142 el 2026-08-04 y desplegado el 2026-08-18
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

---

## PR #161: Saneo de backlog, sprint y reviews contra el estado real del codigo

- **Autor**: [ARQUITECTO]
- **Fecha**: 2026-08-20
- **Branch**: `worktree-chore-saneo-archivos-equipo`
- **Archivos modificados**:
  - `.claude/team/backlog.md` — 7 tareas marcadas hechas con evidencia, TASK-021 nueva, TASK-017 desglosada
  - `.claude/team/current-sprint.md` — 6 trabajos mergeados movidos a Completado; "Pendiente" reescrito
  - `.claude/team/reviews/pending.md` — vaciado
  - `.claude/team/reviews/archive-2026-08.md` — nuevo, recibe las 7 entradas cerradas
- **Descripcion**: solo documentacion de equipo. No toca codigo, tests ni configuracion.
- **Tests**: no aplica — el diff no incluye codigo
- **Review**: no quedo registrada; mergeado como PR #161 (`a644975`) el 2026-08-20
- **Puntos que merecen ojo del reviewer**:
  - **TASK-003 se cierra como falso positivo, no como implementada.** El hallazgo L5 pedia corregir la
    herencia de los controllers admin; en realidad ya estaba bien y el reporte salio de buscar el nombre
    completo `Admin::ApplicationController` con grep, cuando Ruby lo resuelve por el `module Admin`
    envolvente. Si el reviewer discrepa, es la unica tarea que se cierra sin cambio de codigo detras.
  - **TASK-005 estaba hecha en otro lugar del que decia la tarea.** Pedia `with_lock` en
    `IssueCertificateJob`; Batch J lo puso en el modelo. El efecto es el mismo o mejor (cubre las tres
    transiciones, no solo la emision), pero conviene que alguien confirme que no queda un hueco en el job.
  - **El dato mas accionable del PR no es una tarea, es el deploy**: hay cinco PRs mergeados sin
    desplegar (#156-#160) sobre la imagen `e0090c0`. Se documenta en "Pendiente" del sprint.
  - **Las reviews cerradas se archivaron, no se borraron.** Si la convencion preferida es borrarlas, el
    archivo `archive-2026-08.md` sobra — pero entonces se pierde la verificacion manual del SDK de
    MercadoPago 3.4.0 y del schema de Solid Queue 1.6.0, que ningun test cubre.

---

## PRs #162–#166: las cinco tareas de codigo del backlog

- **Autor**: [DESARROLLADOR]
- **Fecha**: 2026-08-20
- **Review**: no quedo registrada por PR; los cinco se mergearon el 2026-08-20 con `bin/ci` completo en
  verde y signoff propio. Detalle tecnico de cada uno en su PR de GitHub y en `current-sprint.md`.
- **Ramas**: `worktree-fix-normalizacion-telefono` (#162, `278e006`),
  `worktree-fix-hallazgos-baja-impacto` (#163, `60e1b35`),
  `worktree-feat-duplicar-solicitud-onboarding` (#164, `34b0e1b`),
  `worktree-feat-convivientes-domicilio` (#165, `fb3bcf3`),
  `worktree-feat-trazabilidad-certificados` (#166, `7b72f5a`)
- **Puntos que merecen ojo del reviewer**:
  - **#163 descarta un hallazgo de auditoria como falso positivo.** Si alguien discrepa, la discusion es
    sobre si `Listing#subscribable?` podria relajarse en el futuro — hoy el `start_date` propuesto
    regalaria 30 dias.
  - **#164 y #165 precisan reglas escritas**: BR-026 describia un flujo inexistente y BR-042 chocaba con
    BR-041. Ambas correcciones son decisiones de producto, no tecnicas.
  - **#166 deja la columna `requested_by_id` nullable a proposito**, sin backfill. Es la decision mas
    discutible de la tanda: prioriza no afirmar lo que no se sabe por sobre la completitud del dato.
  - **#162 cambia el comportamiento observable de `AdministrationRequest`**: un telefono malformado ahora
    falla por formato en vez de por presencia.

