# Code Reviews Pendientes

Este archivo rastrea los PRs pendientes de revision. El Desarrollador crea entradas, el Tester agrega resultados de tests, y el Reviewer aprueba o solicita cambios.

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
