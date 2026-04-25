---
name: feature
description: Implementa una nueva feature siguiendo el workflow completo — planning, aprobacion, implementacion, mini-audit de archivos tocados, PR y actualizacion automatica de archivos de equipo.
disable-model-invocation: true
allowed-tools:
  - Read
  - Edit
  - Write
  - Grep
  - Glob
  - Task
  - EnterPlanMode
  - ExitPlanMode
  - AskUserQuestion
  - Bash(git *)
  - Bash(gh issue *)
  - Bash(gh pr *)
  - Bash(gh label *)
  - Bash(bin/rails test*)
  - Bash(bin/rails db:migrate*)
  - Bash(bin/rails generate*)
  - Bash(bin/rails routes*)
  - Bash(bundle exec rubocop*)
  - Bash(bundle exec erb_lint*)
  - Bash(bundle exec standardrb*)
  - Bash(ls *)
---

# Feature Skill

Implementa una nueva feature con planning, mini-audit post-implementacion, y actualizacion automatica de archivos de equipo.

## Input

`$ARGUMENTS` — Descripcion de la feature o referencia a un item del backlog. Ejemplos:
- `/feature Agregar filtros de busqueda avanzada en socios`
- `/feature #003 del backlog`
- `/feature Implementar export PDF de certificados de residencia`

## Procedimiento

### Fase 1: Contexto y pre-checks

#### 1.1 Leer estado actual del equipo

Leer los archivos de equipo para entender el contexto:
- `.claude/team/backlog.md` — buscar si la feature ya esta registrada
- `.claude/team/current-sprint.md` — verificar que no haya conflictos con trabajo en progreso
- `.claude/team/architecture/decisions.md` — ADRs relevantes

#### 1.2 Verificar issues de audit abiertos

```bash
gh issue list --label "severity:alta" --state open --limit 50
```

Si hay issues de severidad alta abiertos, **advertir al usuario**:

> Hay N issues de severidad alta abiertos del ultimo audit. Se recomienda resolverlos antes de agregar features nuevas para evitar acumular deuda tecnica. Deseas continuar de todos modos?

Usar `AskUserQuestion` para confirmar. Si el usuario decide no continuar, detener.

#### 1.3 Registrar en backlog (si no existe)

Si la feature no esta en `backlog.md`, agregarla con el siguiente formato:

```markdown
- [ ] #NNN [Feature] Descripcion de la feature
  - Prioridad: (preguntar al usuario)
  - Estimacion: (determinar despues del planning)
  - Solicitado por: @usuario
```

Usar el siguiente numero secuencial disponible como ID.

### Fase 2: Planning (plan mode)

#### 2.1 Entrar en plan mode

Usar `EnterPlanMode` para iniciar la fase de diseno. Durante plan mode:

1. **Explorar el codebase** — Leer archivos relevantes a la feature:
   - Models, controllers, views, helpers, tests que se veran afectados
   - Patrones existentes en modulos similares (usar como referencia)

2. **Disenar la solucion** — Escribir un plan detallado que incluya:
   - Archivos a crear/modificar
   - Cambios de schema (migraciones si aplica)
   - Nuevos modelos/controladores necesarios
   - Vistas y parciales de UI
   - Rutas necesarias
   - Traducciones i18n
   - Impacto en modulos existentes

3. **Documentar en decisions.md** — Crear un ADR:

```markdown
### ADR-NNN: Titulo de la decision

- **Fecha**: YYYY-MM-DD
- **Estado**: Propuesto
- **Contexto**: Por que se necesita esta feature
- **Decision**: Enfoque tecnico elegido
- **Consecuencias**: Impacto positivo y negativo
- **Alternativas consideradas**:
  1. Alternativa 1 — razon de rechazo
  2. Alternativa 2 — razon de rechazo
```

4. **Estimar complejidad** — S/M/L/XL basado en:
   - S: 1-3 archivos, sin migraciones
   - M: 4-8 archivos, posible migracion
   - L: 9-15 archivos, migraciones + nuevos modelos
   - XL: 16+ archivos, cambios arquitectonicos

#### 2.2 Presentar plan y esperar aprobacion

Usar `ExitPlanMode` para presentar el plan al usuario. El plan debe incluir:
- Lista exacta de archivos a crear/modificar
- Orden de implementacion
- Riesgos identificados
- Estimacion de complejidad

**No continuar hasta recibir aprobacion del usuario.**

### Fase 3: Implementacion

#### 3.1 Preparar branch

```bash
git checkout main
git pull origin main
git checkout -b feature/<slug-descriptivo>
```

El slug se genera de la descripcion de la feature (lowercase, hyphens, max 50 chars).

#### 3.2 Actualizar current-sprint.md

Mover la feature del backlog al sprint actual:

```markdown
### En Progreso
- [ ] #NNN [Feature] Descripcion de la feature
  - Asignado: Desarrollador
  - ADR: decisions.md#adr-NNN
  - Branch: feature/<slug>
  - Estimacion: S/M/L/XL
```

#### 3.3 Implementar

Seguir el plan aprobado. Respetar los patrones de CLAUDE.md:

- **Models**: Heredar de ApplicationRecord, incluir Sortable/Filterable, status como constantes string
- **Controllers**: Patron CRUD consistente con index, show, new, create, edit, update, search, delete
- **Views**: ERB con Tailwind/DaisyUI, usar helpers (input_class, error_message, icon, sort_link)
- **Frontend**: Turbo Frames/Streams para interactividad, Stimulus controllers
- **I18n**: Todas las cadenas de usuario en es.yml/en.yml
- **Normalizacion**: before_validation callbacks para datos como RUN, telefono, nombres
- **Migraciones**: Si se modifica el schema, generar migracion con `bin/rails generate migration`

#### 3.4 Validar

Ejecutar en secuencia:

```bash
bundle exec standardrb --fix
bundle exec erb_lint --lint-all
bin/rails test
```

Si alguna falla, corregir y re-ejecutar hasta que las 3 pasen.

### Fase 4: Mini-audit post-implementacion

**Esta fase es critica.** Antes de crear el PR, auditar los archivos tocados para no introducir bugs.

#### 4.1 Identificar archivos tocados

```bash
git diff --name-only main...HEAD
```

#### 4.2 Auditar cada archivo nuevo/modificado

Para cada archivo, verificar estas categorias:

| Categoria | Que buscar |
|-----------|-----------|
| **Seguridad** | SQL injection, XSS, CSRF bypass, mass assignment sin strong params |
| **N+1 queries** | Queries en loops, missing `includes`/`eager_load` |
| **Validaciones** | Campos requeridos sin validar, formatos no validados |
| **Autorizacion** | Acceso sin verificar rol (admin/superadmin/panel) |
| **I18n** | Strings hardcodeados en espanol sin usar traducciones |
| **Callbacks** | before_validation para normalizacion, efectos secundarios inesperados |
| **Tests** | Cobertura de happy path y edge cases |
| **Performance** | Queries sin indice, loads de tablas completas |
| **Turbo** | Turbo Frames/Streams correctamente configurados |

#### 4.3 Reportar y corregir

Si el mini-audit encuentra problemas:
1. Listar los hallazgos encontrados al usuario
2. Corregir cada uno **antes** de crear el PR
3. Re-ejecutar validaciones (rubocop/erb_lint/tests) despues de las correcciones

Si no encuentra problemas, reportar:
> Mini-audit completado: 0 hallazgos en N archivos revisados.

### Fase 5: Commit, PR y actualizacion de equipo

#### 5.1 Commit

Stage solo los archivos de la feature:

```bash
git add <archivos-modificados>
git commit -m "$(cat <<'EOF'
<descripcion-concisa-de-la-feature>

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

Si la feature tiene un issue asociado, agregar `Closes #<number>` al mensaje.

#### 5.2 Push y crear PR

```bash
git push -u origin feature/<slug>

gh pr create \
  --title "<descripcion-concisa>" \
  --body "$(cat <<'EOF'
## Summary
- <bullet points describiendo la feature>

## Changes
- <lista de archivos creados/modificados con breve descripcion>

## Mini-audit results
- <N> archivos auditados, <M> hallazgos encontrados y corregidos (o 0 hallazgos)

## Test plan
- [ ] `bundle exec standardrb` passes
- [ ] `bundle exec erb_lint --lint-all` passes
- [ ] `bin/rails test` passes
- [ ] <pasos de verificacion manual de la feature>

## ADR
- decisions.md#adr-NNN

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)" \
  --base main \
  --assignee "@me"
```

#### 5.3 Actualizar archivos de equipo

**current-sprint.md** — Mover a completado:

```markdown
### Completado
- [x] #NNN [Feature] Descripcion
  - PR: #<pr-number>
  - Branch: feature/<slug>
```

**pending.md** — Crear entrada de review:

```markdown
### PR #<number>: Titulo del PR
- **Autor**: Desarrollador (Claude Code)
- **Branch**: feature/<slug>
- **Archivos**: <lista de archivos modificados>
- **Tests**: Pasando
- **Mini-audit**: <N> archivos, <M> hallazgos corregidos
- **Review**: Pendiente
- **ADR**: decisions.md#adr-NNN
```

**decisions.md** — Actualizar estado del ADR:

```markdown
- **Estado**: Aceptado (implementado en PR #<number>)
```

**backlog.md** — Remover el item (ya esta en current-sprint como completado).

#### 5.4 Resumen final

Imprimir resumen:

```
## Feature completada

| Campo | Valor |
|-------|-------|
| Feature | Descripcion |
| Branch | feature/<slug> |
| PR | #<number> |
| ADR | ADR-NNN |
| Archivos tocados | N |
| Mini-audit | N archivos, M hallazgos corregidos |
| Validaciones | lint, erb_lint, tests |
```

## Reglas

- **Plan mode obligatorio**: Nunca empezar a implementar sin aprobacion del plan
- **Mini-audit obligatorio**: Nunca crear PR sin ejecutar el mini-audit de archivos tocados
- **Validaciones obligatorias**: standardrb + erb_lint + tests deben pasar antes de commit
- **Un branch por feature**: Nunca mezclar multiples features en un branch
- **Stage especifico**: Usar `git add <files>` explicito, nunca `git add -A`
- **No skip hooks**: Nunca usar `--no-verify`
- **No push force**: Nunca usar `git push --force`
- **Archivos de equipo**: Siempre actualizar backlog, current-sprint, pending y decisions
- **I18n**: Todas las cadenas de usuario deben usar traducciones (es.yml/en.yml)
- **Migraciones**: Si se modifica el schema, generar migracion con `bin/rails generate migration`
