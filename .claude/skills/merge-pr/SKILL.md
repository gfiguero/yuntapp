---
name: merge-pr
description: Mezcla un PR aprobado en main, deja un comentario de cierre y elimina la rama remota.
disable-model-invocation: true
allowed-tools:
  - Bash(gh pr *)
  - Bash(git *)
---

# Merge PR Skill

Mezcla uno o varios PRs aprobados, deja un comentario de cierre y elimina la rama remota.

## Input

`$ARGUMENTS` — Numeros de PR a mezclar. Ejemplos:
- `/merge-pr 233` — Mezcla el PR #233
- `/merge-pr 233 234 235` — Mezcla los PRs #233, #234 y #235 en secuencia

## Procedimiento

### Para cada PR proporcionado:

#### 1. Verificar estado del PR

```bash
gh pr view <number> --json state,title,headRefName,mergeable
```

Si el PR no esta en estado `OPEN`, reportar y saltar al siguiente.

#### 2. Mezclar el PR

```bash
gh pr merge <number> --squash --delete-branch
```

Usar `--squash` para mantener el historial limpio. `--delete-branch` elimina la rama remota automaticamente.

#### 3. Comentario de cierre

```bash
gh pr comment <number> --body "Revisado y mergeado. Rama eliminada."
```

#### 4. Registrar resultado

Anotar exito o fallo para el resumen final.

### Actualizar main local

Despues de procesar todos los PRs, actualizar la rama main local:

```bash
git fetch origin main
```

Esto asegura que el proyecto local tenga los commits mergeados sin cambiar de rama.

### Resumen final

Al terminar todos los PRs, imprimir:

```
## PRs mergeados

| PR    | Titulo                          | Estado     |
|-------|---------------------------------|------------|
| #233  | Fix onboarding step 3 crash     | Mergeado   |
| #234  | Add member search filter        | Error: ... |

Total: X mergeados, Y fallidos
```

## Reglas

- **Nunca force merge**: No usar `--admin` para saltarse checks
- **Squash merge**: Siempre usar `--squash` para mantener historial limpio
- **Eliminar rama**: Siempre eliminar la rama remota despues del merge
- **Continuar en error**: Si un PR falla, registrar el error y continuar con el siguiente
