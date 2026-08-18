# Sprint Actual

Este archivo contiene las tareas del sprint en curso. Solo el Arquitecto puede mover tareas desde el backlog.

## En Progreso

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
