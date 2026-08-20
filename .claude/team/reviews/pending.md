# Code Reviews Pendientes

Este archivo rastrea los PRs pendientes de revision. El Desarrollador crea entradas, el Tester agrega
resultados de tests, y el Reviewer aprueba o solicita cambios.

Las entradas de los PRs ya mergeados se movieron a `archive-2026-08.md`. Al cerrar un PR, mover su
entrada alli en vez de borrarla: los "Puntos que merecen ojo del reviewer" suelen ser el unico
registro de por que se decidio algo.

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
- **Review**: Pendiente
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
