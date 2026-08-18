# Sprint Actual

Este archivo contiene las tareas del sprint en curso. Solo el Arquitecto puede mover tareas desde el backlog.

## En Progreso

### Cops Rails vía `standard-rails` (worktree `refactor-standard-rails`)
Como [DESARROLLADOR]: el owner pidió aprovechar las ventajas de escribir código Rails-way. La opción
obvia era volver a `rubocop-rails-omakase`, el preset oficial de Rails — se descartó porque reabre el
conflicto de espaciado que cerró ADR-0011 el 2026-06-29 (`{ a: 1 }` vs `{a: 1}`), reformatearía 232
líneas en 294 archivos sin cambio funcional y obligaría a reescribir `config/ci.rb`, `bin/standardrb`
y la skill `/check-code`.

Se adopta `standard-rails`, que es un **plugin de Standard**, no un segundo linter: mismo ejecutable,
misma config, mismo paso de CI, cero churn de formato.

- [x] `gem "standard-rails"` + `plugins: [standard-rails]` en `.standard.yml`
- [x] 41 ofensas corregidas en 37 archivos (`Rails/CompactBlank` ×22, `Rails/Blank` ×10, `Rails/Pluck` ×4,
      `Rails/RedundantPresenceValidationOnBelongsTo` ×2, `Rails/RootPathnameMethods` ×2, `Rails/FindEach` ×1)
- [x] 5 ofensas descartadas por falso positivo o decisión deliberada, documentadas con motivo en
      `.standard.yml` y en la tabla del ADR (migraciones históricas, `puts` de seeds, los dos endpoints
      públicos que heredan de `ActionController::Base`, y el `update` que Devise define en la superclase)
- [x] ADR-0011 revisado con la comparación omakase vs `standard-rails` y las exclusiones

**Estado: implementado, 723 tests / 1835 asserts / 0 fallos — idéntico al baseline de master.**
`bin/ci` completo en verde (3m45s), incluido el paso de production parity que corre la suite dentro
de la imagen Docker de producción. PR #156, firmado con `gh signoff`.

**Aprendizaje de plumbing**: `gh signoff` falla con `@{push} does not resolve` si la rama se pusheó
con la URL SSH explícita en vez de `origin`. El remote del repo es HTTPS y no hay credential helper
configurado, así que `git push origin` pide usuario y falla en entornos no interactivos. Arreglo sin
tocar el remote: `git fetch git@github.com:gfiguero/yuntapp.git <rama>:refs/remotes/origin/<rama>` y
después `git branch --set-upstream-to=origin/<rama>`. La solución de raíz sería `gh auth setup-git`
o pasar el remote a SSH — pendiente de decisión del owner.

### Batch J — Severidad Media de la auditoría profunda 2026-07-30 (worktree `fix-batch-j`)
Como [DESARROLLADOR]: las 11 de severidad Media de `docs/2026-07-30-auditoria-profunda.md`.

- [x] **J1** (BR-120/BR-148) — nada impedía solicitar ni pagar un certificado en una junta sin RUT: `issue!` abortaba después y el certificado quedaba `paid` para siempre, sin devolución (BR-063) y sin aviso. Guards en `residence_certificates#new/create` y `payments#new` + `CertificateIssuanceFailureMailer` al staff cuando `IssueCertificateJob` se rinde. **Matiz importante**: desde BR-121 `rut` es `NOT NULL` con validación de presencia, así que el escenario no es alcanzable por la app — la auditoría lo sobrevaloró. El valor real es el aviso al staff, que cubre cualquier fallo de emisión
- [x] **J2** (BR-007) — IDOR de directiva: `member_id` viajaba por strong params sin validar pertenencia, así que un POST manipulado metía un socio de otra junta en la directiva y filtraba su nombre y RUN en las vistas (incluida la pública). Validación en `BoardMember`
- [x] **J3** (BR-091/BR-099) — `panel/dependents` solo exigía `household_admin?`, que se apoya en la `Residency` y por BR-038 no cambia al desactivar el `Member`. Un socio dado de baja registraba dependientes y al aprobarlos recuperaba un `Member(approved)`. `ensure_active_member!`
- [x] **J4** (BR-024/BR-044) — `admin/members#create` guardaba la `VerifiedIdentity` fuera de transacción: si el `Member` fallaba quedaba una identidad huérfana. Transacción + `status`/`requested_by` explícitos; `update` también deja de reventar con 500 ante datos inválidos
- [x] **J5** (BR-054) — la aprobación de administración no exigía junta `active`: dejaba un admin operando una junta disuelta. `InactiveAssociationError`
- [x] **J6** (BR-137/BR-139/BR-140) — las tres advertencias al staff existían como regla pero no en la UI. `memberships_to_deactivate`, `possible_duplicate_association` y `position_already_taken_by` en la show del staff, más el aviso al solicitante en el formulario del panel (BR-137 exige ambos)
- [x] **J7** (BR-141) — `mark_as_paid!`/`apply_mp_payment_status!`/`issue!` leían y escribían sin serializar: un job con el certificado cargado como `paid` lo emitía aunque un contracargo ya lo hubiera revertido. `with_lock` (en SQLite el `FOR UPDATE` es no-op, pero la recarga dentro de la transacción es lo que cierra la ventana)
- [x] **J8** (BR-004/BR-085/BR-149) — el cobro recurrente es por `subscription_amount`, pero `amount` se reescribe con el precio vigente: tras A6 la renovación pasa a aceptarse y registraba un 10% sobre un monto que nadie pagó. `renew_from_subscription!` re-sincroniza el snapshot. En certificados **no aplica**: su `amount` se fija al crear y ninguna ruta lo reescribe (el "fix" ahí era un no-op — `compute_platform_fee` lo recalcula en el mismo `save`)
- [x] **J9** (BR-088) — cancelar la suscripción propagaba 500 si MP ya la había cancelado. Se rescata el error del SDK y el estado local se marca `cancelled` igual
- [x] **J10** — las páginas `success` afirmaban el resultado sin mirar el estado real. Ahora distinguen "confirmado" de "procesando". Severidad real menor a la reportada: el copy anterior ya estaba matizado
- [x] **J11** (BR-062/BR-077) — `approved_by_id` vestigial eliminado (asociación, vista, jbuilder, i18n y columna, con migración). También se quitó el i18n huérfano `verified_identity/verification_status`. La rama doc del hallazgo ya se había cerrado sola al podar CLAUDE.md en `b154ad4`

**Estado: implementado, 723 tests / 1835 asserts / 0 fallos (+22 tests nuevos).**

BRs nuevas: **BR-148** (precondición de RUT + aviso al staff) y **BR-149** (fee alineado al monto
realmente cobrado). Notas de enforcement agregadas a BR-007, BR-024, BR-054, BR-077, BR-088,
BR-091, BR-137, BR-139, BR-140 y BR-141.

**DESPLEGADO A PRODUCCIÓN el 2026-08-18** — imagen `53855ed`, que incluye Batch J (`46803d8`, PR
#142) más el bump de gems de seguridad (PR #154). La migración `20260802210000`
(`RemoveApprovedByFromResidenceCertificates`) se aplicó sola en el boot (`migrated (0.3063s)`).
Post-deploy verificado: `/up` 200, columna `approved_by_id` ausente, cero excepciones en la ventana
del deploy, `/verify/<code>` 200 y `/verify/<inexistente>` 404, datos intactos (7 certificados,
6 emitidos, 20 socios, 1 junta).

**Riesgo que se corrió y no se materializó:** el `remove_reference` de `approved_by_id` no es
backwards-compatible. Kamal migra al bootear el contenedor nuevo y recién después hace el swap del
proxy, así que hubo una ventana de segundos donde el contenedor viejo —que todavía tenía
`belongs_to :approved_by` y su schema cache en memoria— sirvió tráfico contra un schema sin la
columna. Un `INSERT` en `residence_certificates` en esa ventana habría dado 500. No ocurrió (cero
excepciones en los logs), pero **la próxima vez que se elimine una columna conviene el patrón de
dos fases**: primero desplegar con `ignored_columns`, después la migración que la borra.

### Batch I — Severidad Alta de la auditoría profunda 2026-07-30 (directo en `master`)
Como [DESARROLLADOR]: las 8 de severidad Alta de `docs/2026-07-30-auditoria-profunda.md`.
Trabajo directo en master por indicación del owner (sin worktree).

- [x] **A1** (BR-083/BR-143) — la vitrina pública usaba `Listing.all`: cualquiera publicaba gratis. `ListingsController` pasa a `Listing.published` en index/show/search y en el bypass `items=all`
- [x] **A2** (BR-018/BR-100) — `onboarding#restart` destruía la solicitud `pending` (y en cascada su identidad y residencia). Ahora `cancel!`; solo el borrador se descarta
- [x] **A3** (BR-100) — geografía con `dependent: :destroy`: Country→regions y Region→communes pasan a `restrict_with_error`; `Commune` gana `restrict` sobre juntas y domicilios (antes los orfanaba por nullify). Los 3 controllers superadmin informan en vez de reventar
- [x] **A4** (BR-100/BR-144) — `listing.destroy!` físico borraba el snapshot financiero. Guard `before_destroy` + `withdraw!` (`active: false`); `active` pasa a significar "visible en la vitrina"
- [x] **A5** (BR-046) — `admin/members#update` permitía reescribir el RUN de una identidad verificada. Params `.except(:run)` + campo deshabilitado en edición
- [x] **A6** (BR-088/BR-090/BR-145) — el cobro recurrente se validaba contra `listing.amount`, que se reescribe con el precio vigente: si la junta subía el precio, la renovación legítima se rechazaba y la publicación vencía pese al pago. Nueva columna `subscription_amount` (migración con backfill)
- [x] **A7** (BR-141/BR-146) — una notificación tardía con el mismo `payment_id` como `approved` podía deshacer un refund/contracargo. Guarda por `PaymentEvent` revertido
- [x] **A8** (BR-091/BR-092/BR-141/BR-147) — el PDF se servía por URL de blob sin expiración, evadiendo `downloadable?`. Ahora `send_data` autorizado en cada descarga + `urls_expire_in = 5.minutes`

**Estado: COMPLETADO Y DESPLEGADO (2026-08-02).** 701 tests / 1747 asserts / 0 fallos (+31 tests
nuevos). `bin/ci` verde en todas las etapas (Standard, ERB lint, gem + importmap audit, Brakeman,
zeitwerk, tests locales y en contenedor) + signoff.

- Commit `e25e7b0` (Batch I), pusheado a `master`.
- Deploy `014340e` a producción (desde `e261ed5`, que llevaba 3 días): boot healthy en 100,7s.
- Migración `20260731174440_add_subscription_amount_to_listings` aplicada **automáticamente
  durante el boot** (log: `Migrating to AddSubscriptionAmountToListings` a las 01:14:50, antes
  de que Puma escuchara). Lo hace `bin/docker-entrypoint`, que corre `db:prepare` cuando los dos
  últimos argumentos del `CMD` son `./bin/rails server` — y el CMD es
  `["./bin/thrust", "./bin/rails", "server"]`, así que la condición se cumple. **No hace falta
  migrar a mano**; el `kamal app exec 'bin/rails db:migrate'` que se corrió después fue un no-op.
  Backfill afectó 0 filas: prod es entorno demo y hoy no tiene publicaciones.
- Backup previo: `storage/production.sqlite3.bak-predeploy-batchi` (573.440 bytes).
- Verificado post-deploy: `/up` 200, home 200, `/como-funciona` 200, `/users/sign_in` 200,
  columna presente, logs sin errores de aplicación.

**Notas operacionales:**
- `gh signoff` exige que no queden cambios sin pushear, así que el orden es push → signoff. Al ir
  directo a master eso deja un `Bypassed rule violations` en el push, que el signoff resuelve.
- Las migraciones corren solas en cada boot vía `bin/docker-entrypoint` → `db:prepare`. Esa
  automatización depende del `CMD` del Dockerfile: si se cambia por uno cuyos dos últimos
  argumentos no sean `./bin/rails server`, dejará de migrar **en silencio**.

## Pendiente

- Las **12 severidades Baja** de `docs/2026-07-30-auditoria-profunda.md`. De las 4 BR faltantes
  del informe quedan 2: normalización de direcciones (Baja) — las otras dos son BR-143 (Batch I)
  y BR-148/BR-149 (Batch J).
- **Hallazgo nuevo (2026-08-02, fuera de la auditoría):** `VerifiedIdentity#normalize_phone` borra
  todo carácter no numérico, así que un teléfono basura (`"no-es-un-telefono"`) queda como `""` y
  la validación `phone: true, if: -> { phone.present? }` no llega a correr. El usuario cree que
  registró un teléfono y se guarda vacío. Detectado escribiendo los tests de J4; sin remediar.

### Bump de seguridad previo al deploy de Batch J (worktree `chore-bump-gems-seguridad`) — 2026-08-18
Como [DESARROLLADOR]: `bin/ci` sobre master (`46803d8`) falló en `Security: Gem audit` y
`Security: Brakeman`, así que no hubo signoff y el deploy de Batch J quedó bloqueado. Ambos fallos
son **preexistentes y ajenos a Batch J**. Resueltos subiendo `sqlite3` 2.9.5→2.9.6 (CVE real de la
BD de producción), `json` 2.21.1→2.21.2 (transitiva) y `brakeman` 8.0.5→8.0.6 (solo destraba el
exit 5 "no es la última versión"; Brakeman reporta **0 hallazgos** en el código).

**Aprendizaje operacional:** el squash merge crea un commit nuevo en master que **no hereda el
signoff** de la rama. Por eso hay que correr `bin/ci` sobre master antes de cada deploy, no solo
antes del merge.

### Actualización de gemas al día (worktree `chore-actualizar-gemas`) — 2026-08-18
Como [DESARROLLADOR]: pedido de "Ruby 4.0.6 + último Rails + todas las gemas al día".

**Ruby y Rails ya estaban en la última**: Ruby 4.0.6 desde el PR #81 (`.ruby-version`, intérprete y
`ARG RUBY_VERSION` del Dockerfile coinciden; es lo último que ofrece rbenv) y Rails 8.1.3.1,
publicada el 2026-07-29. No hubo nada que migrar ahí.

El trabajo real fueron las 19 gemas desactualizadas: **16 subieron**, incluidas `mercadopago-sdk`
3.2.1→3.4.0, `resend` 1.6.0→1.9.0 y `solid_queue` 1.5.1→1.6.0. **3 quedan retenidas** por
restricciones de sus propias dependencias, no por nuestro Gemfile: `bigdecimal` (ttfunk→Prawn exige
`~> 3.1`; forzar 4.x rompería el PDF de certificados), `rubocop` y `rubocop-performance` (Standard
los pinea a propósito). Forzarlas sería pasar por encima de la compatibilidad declarada.

Cierra los 8 PRs de Dependabot abiertos. Detalle de la verificación manual del SDK de MercadoPago
y del schema de solid_queue en `reviews/pending.md`.

**DESPLEGADO A PRODUCCIÓN el 2026-08-18** — imagen `e0090c0` (PR #155), desde `53855ed`. Deploy sin
migraciones ni cambios de schema: solo `Gemfile.lock` y docs, así que no hubo ventana de
incompatibilidad. Post-deploy verificado en el contenedor: Ruby 4.0.6 · Rails 8.1.3.1 ·
mercadopago-sdk 3.4.0 (los 5 recursos que usamos responden, `RequestOptions` conserva
`custom_headers` y `MPResponse < Hash` es `true`) · resend 1.9.0 con `delivery_method: resend`
registrado · solid_queue 1.6.0 con Supervisor/Dispatcher/Worker/Scheduler arriba y el worker ya en
el `pool_type: :thread` nuevo · sqlite3 2.9.6 · rack 3.2.7. Cero excepciones en los logs, `/up` 200,
`/verify/<code>` 200 y `/verify/<inexistente>` 404, datos intactos (7 certs / 20 socios / 1 junta).

## En Review

<!-- Tareas con PR abierto esperando revision -->

## Completado

### Recuperación de la auditoría perdida (2026-07-31)
La sesión de auditoría del 2026-07-30 se cortó por un apagón antes de versionarse. Se recuperó
íntegra desde el transcript (`~/.claude/projects/.../2fe1aa36-….jsonl`): los 6 informes de los
agentes viven en las filas `task-notification` y el consolidado en el último mensaje del asistente.
Resultado en `docs/2026-07-30-auditoria-profunda.md` (8 Alta · 11 Media · 12 Baja · 4 BR faltantes).

**Siguiente:** las 11 de severidad Media (ver el informe), empezando por el certificado que queda
atascado en `paid` cuando la junta no tiene RUT (BR-120) y el IDOR de directiva (BR-007).
