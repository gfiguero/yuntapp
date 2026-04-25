---
name: review
description: Revisa el branch actual contra los standards del proyecto. Genera reporte con veredicto APROBADO, CAMBIOS REQUERIDOS o BLOQUEADO.
user-invocable: true
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash(git diff*)
  - Bash(git log*)
  - Bash(git status*)
  - Bash(gh pr*)
  - Bash(bin/rails test*)
  - Bash(bundle exec rubocop*)
  - Bash(bundle exec standardrb*)
  - Bash(bundle exec erb_lint*)
  - Bash(ls*)
---

# Review Skill

Revisa el codigo del branch actual y genera un reporte estructurado con veredicto claro.

## Input

`$ARGUMENTS` — Opcional. Branch o numero de PR a revisar. Si se omite, usa el branch actual.

Ejemplos:
- `/review` — Revisar branch actual
- `/review feature/filtros-socios` — Revisar branch especifico
- `/review #42` — Revisar PR #42

## Procedimiento

### Fase 1: Recopilar contexto

1. Identificar el branch y commits desde main:
```bash
git log main...HEAD --oneline
git diff --stat main...HEAD
```

2. Si se indico un PR numero, obtener descripcion:
```bash
gh pr view <number>
```

3. Leer contexto del equipo:
   - `.claude/team/reviews/pending.md` — estado del PR
   - `.claude/team/architecture/decisions.md` — ADRs relacionados

### Fase 2: Analisis de cambios

```bash
git diff main...HEAD
```

Para cada archivo modificado, evaluar:

| Categoria | Criterios |
|-----------|-----------|
| **Seguridad** | SQL injection, XSS, CSRF, mass assignment sin strong params |
| **Autorizacion** | Acceso sin verificar rol (superadmin/admin/panel) |
| **N+1 queries** | Queries en loops, missing includes/eager_load |
| **Validaciones** | Campos requeridos, formatos (RUN, telefono), unicidad |
| **I18n** | Strings hardcodeados en espanol sin usar es.yml/en.yml |
| **Convenciones** | Status como strings, callbacks before_validation, delegacion |
| **Tests** | Cobertura del happy path y edge cases |
| **Performance** | Indices faltantes, loads de tablas completas |
| **Turbo** | Turbo Frames/Streams correctamente configurados |
| **Migraciones** | null constraints, indices en foreign keys, rollback viable |

### Fase 3: Ejecutar validaciones

```bash
bundle exec standardrb
bundle exec erb_lint --lint-all
bin/rails test
```

Reportar resultado de cada uno.

### Fase 4: Clasificar hallazgos

- **BLOQUEADOR**: Vulnerabilidad de seguridad, perdida de datos, tests fallando, acceso no autorizado
- **CAMBIO REQUERIDO**: Validacion faltante, N+1, i18n incompleto, convencion no seguida, indice faltante
- **SUGERENCIA**: Mejora de calidad no critica, naming, refactor menor

### Fase 5: Veredicto y reporte

```
## Code Review — <branch-name>

**Veredicto:** APROBADO / CAMBIOS REQUERIDOS / BLOQUEADO

**Archivos revisados:** N
**Commits:** N (lista de commit hashes y mensajes)

### Bloqueadores
[lista detallada con archivo:linea y fix propuesto, o "Ninguno"]

### Cambios requeridos
[lista detallada con archivo:linea y fix propuesto, o "Ninguno"]

### Sugerencias
[lista, o "Ninguno"]

### Validaciones
| Check | Resultado |
|-------|-----------|
| StandardRB | pass/fail |
| ERB Lint | pass/fail |
| Tests | X tests, Y assertions — pass/fail |
```

Reglas del veredicto:
- **APROBADO**: 0 bloqueadores, 0 cambios requeridos
- **CAMBIOS REQUERIDOS**: 0 bloqueadores, >= 1 cambio requerido
- **BLOQUEADO**: >= 1 bloqueador

Si hay bloqueadores o cambios requeridos, preguntar:
> "Deseas que corrija los hallazgos antes de continuar con el PR?"

### Fase 6: Actualizar pending.md

Agregar o actualizar entrada en `.claude/team/reviews/pending.md`:

```markdown
### PR #<number>: <titulo>
- **Veredicto**: APROBADO / CAMBIOS REQUERIDOS / BLOQUEADO
- **Bloqueadores**: N
- **Cambios requeridos**: N
- **Revisado**: YYYY-MM-DD
```

## Reglas

- **Codigo real**: Siempre citar archivo y linea exacta del problema
- **Fix concreto**: Para cada hallazgo, proponer la solucion especifica
- **Sin falsos positivos**: Solo reportar problemas reales y verificados
- **Veredicto explicito**: Siempre terminar con APROBADO, CAMBIOS REQUERIDOS o BLOQUEADO
- **Contexto completo**: Leer el archivo completo antes de reportar un hallazgo
