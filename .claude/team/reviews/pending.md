# Code Reviews Pendientes

Este archivo rastrea los PRs pendientes de revision. El Desarrollador crea entradas, el Tester agrega
resultados de tests, y el Reviewer aprueba o solicita cambios.

Las entradas de los PRs ya mergeados se movieron a `archive-2026-08.md`. Al cerrar un PR, mover su
entrada alli en vez de borrarla: los "Puntos que merecen ojo del reviewer" suelen ser el unico
registro de por que se decidio algo.

**Al 2026-08-20 no hay PRs abiertos** salvo el de este mismo saneo, registrado abajo.

---

## PR: Saneo de los archivos de equipo tras cerrar las cinco tareas de codigo

- **Autor**: [ARQUITECTO]
- **Fecha**: 2026-08-20
- **Branch**: `worktree-chore-saneo-equipo-post-tasks`
- **Archivos modificados**:
  - `.claude/team/backlog.md` — TASK-013/014/015/020/021 cerradas, TASK-017 parcial, TASK-022 y TASK-023 nuevas
  - `.claude/team/current-sprint.md` — PRs #161 a #166 en Completado; "Pendiente" reescrito
  - `.claude/team/reviews/pending.md` y `archive-2026-08.md` — seis entradas archivadas
- **Descripcion**: solo documentacion de equipo. No toca codigo, tests ni configuracion.
- **Tests**: no aplica — el diff no incluye codigo
- **Review**: Pendiente
- **Puntos que merecen ojo del reviewer**:
  - **TASK-017 queda marcada como parcial, no cerrada.** Se remediaron los hallazgos de impacto real por
    decision de alcance del owner; los 9 restantes de las 12 Baja siguen listados con su detalle. Si se
    prefiere cerrarla y abrir una tarea nueva para el resto, es una decision de rastreo.
  - **Un hallazgo de auditoria quedo registrado como descartado**, no como pendiente: el "doble cobro
    del primer mes" de las suscripciones es inalcanzable, y actuar sobre el habria regalado 30 dias. La
    evidencia esta en el backlog y en el PR #163.
  - **Los aprendizajes operacionales de la tanda se anotaron en el sprint** (bundle install en worktrees
    nuevos, fingerprints de Brakeman, `assigns` ausente, conflictos previsibles al mergear). Son el tipo
    de cosa que se vuelve a descubrir desde cero si no queda escrita.

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
