# Sprint Actual

Este archivo contiene las tareas del sprint en curso. Solo el Arquitecto puede mover tareas desde el backlog.

## En Progreso

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

- Las **11 severidades Media** de `docs/2026-07-30-auditoria-profunda.md` (y 12 Baja + 4 BR
  faltantes). Ningún trabajo iniciado.

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
