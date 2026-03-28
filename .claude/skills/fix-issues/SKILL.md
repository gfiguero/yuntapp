---
name: fix-issues
description: Resuelve GitHub issues abiertos creando un PR individual por cada issue, siguiendo el workflow establecido de branch, fix, test, PR.
disable-model-invocation: true
allowed-tools:
  - Read
  - Edit
  - Write
  - Grep
  - Glob
  - Task
  - Bash(git *)
  - Bash(gh issue *)
  - Bash(gh pr *)
  - Bash(bin/rails test*)
  - Bash(bin/rails db:migrate*)
  - Bash(bin/rails generate*)
  - Bash(bundle exec rubocop*)
  - Bash(bundle exec erb_lint*)
---

# Fix Issues Skill

Resuelve GitHub issues abiertos creando un PR por cada issue.

## Input

`$ARGUMENTS` — Filtro opcional para seleccionar issues. Ejemplos:
- `/fix-issues` — Todos los issues abiertos asignados al usuario
- `/fix-issues audit` — Issues con label `audit`
- `/fix-issues severity:alta` — Issues con label `severity:alta`
- `/fix-issues audit severity:alta` — Issues con ambos labels
- `/fix-issues #42 #43 #44` — Issues especificos por numero

Si no se proporciona filtro, listar todos los issues abiertos asignados al usuario y pedir confirmacion.

## Procedimiento

### Fase 1: Listar issues a resolver

Segun el filtro proporcionado:

```bash
# Todos los asignados
gh issue list --assignee "@me" --state open --limit 100

# Con labels
gh issue list --assignee "@me" --state open --label "audit" --label "severity:alta" --limit 100

# Issues especificos
gh issue view 42
gh issue view 43
```

Mostrar la lista al usuario y confirmar antes de proceder.

### Fase 2: Para cada issue, ejecutar el workflow

Repetir para cada issue en orden (menor numero primero):

#### 2.1 Preparar branch

```bash
git checkout main
git pull origin main
git checkout -b fix/<issue-number>-<slug>
```

El `<slug>` se genera del titulo del issue:
- Lowercase, reemplazar espacios con `-`, remover caracteres especiales
- Max 50 caracteres
- Ejemplo: issue #42 "onboarding step 3 crash" → `fix/42-onboarding-step-3-crash`

#### 2.2 Entender el issue

1. Leer el issue completo con `gh issue view <number>`
2. Leer los archivos mencionados en el issue
3. Entender el contexto: que hace el codigo actual, por que es incorrecto, cual es el fix propuesto

#### 2.3 Implementar el fix

1. Aplicar los cambios necesarios usando Edit/Write
2. Seguir los patrones establecidos en CLAUDE.md:
   - Strong params para mass assignment
   - Validaciones en modelos
   - Autorizacion por nivel de acceso (superadmin/admin/panel)
   - I18n para cadenas de usuario
   - Turbo Frames/Streams para interactividad
3. No over-engineer: implementar exactamente lo que el issue pide, nada mas
4. Si el fix requiere cambios de schema, generar migracion con `bin/rails generate migration`

#### 2.4 Validar el fix

Ejecutar las tres validaciones en secuencia:

```bash
bundle exec standardrb --fix
bundle exec erb_lint --lint-all
bin/rails test
```

Si alguna falla:
1. Analizar el error
2. Corregir el problema
3. Re-ejecutar las validaciones
4. Repetir hasta que las 3 pasen

**Importante:** No continuar al paso siguiente si las validaciones no pasan.

#### 2.5 Commit

Stage solo los archivos modificados por el fix (no usar `git add -A`):

```bash
git add <archivos-modificados>
git commit -m "$(cat <<'EOF'
<descripcion-concisa-del-fix>

Closes #<issue-number>

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

La descripcion del commit debe:
- Ser concisa (1 linea, max 72 chars)
- Describir QUE se corrigio, no solo "fix bug"
- Ejemplo: `Fix N+1 query in onboarding requests index action`

#### 2.6 Push y crear PR

```bash
git push -u origin fix/<issue-number>-<slug>

gh pr create \
  --title "<descripcion-concisa>" \
  --body "$(cat <<'EOF'
## Summary
- <1-3 bullet points describiendo el cambio>

## Test plan
- [ ] `bundle exec standardrb` passes
- [ ] `bundle exec erb_lint --lint-all` passes
- [ ] `bin/rails test` passes
- [ ] <verificacion manual si aplica>

Closes #<issue-number>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)" \
  --base main \
  --assignee "@me"
```

#### 2.7 Registrar resultado y continuar

Anotar el resultado (exito/fallo) y continuar con el siguiente issue.

### Fase 3: Resumen final

Al terminar todos los issues, imprimir un resumen:

```
## Resumen de PRs creados

| Issue | Titulo                         | PR    | Estado |
|-------|--------------------------------|-------|--------|
| #42   | onboarding step 3 crash        | #55   | Creado |
| #43   | N+1 en members index           | #56   | Creado |
| #44   | i18n missing en admin panel    | -     | Error: tests fallaron |
| ...   | ...                            | ...   | ...    |

Total: X PRs creados, Y fallidos
```

## Reglas

- **Un PR por issue**: Nunca combinar multiples issues en un solo PR
- **Branch desde main**: Siempre crear branch desde main actualizado
- **Validaciones obligatorias**: standardrb + erb_lint + tests deben pasar antes de commit
- **No skip hooks**: Nunca usar `--no-verify` en commits
- **Minimal changes**: Solo modificar lo necesario para resolver el issue
- **Stage especifico**: Usar `git add <files>` explicito, nunca `git add -A` o `git add .`
- **No push force**: Nunca usar `git push --force`
- **Continuar en error**: Si un issue no se puede resolver, registrar el error y continuar con el siguiente
- **Migraciones**: Si se modifica el schema, generar migracion con `bin/rails generate migration`
