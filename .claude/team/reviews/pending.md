# Code Reviews Pendientes

Este archivo rastrea los PRs pendientes de revision. El Desarrollador crea entradas, el Tester agrega resultados de tests, y el Reviewer aprueba o solicita cambios.

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
