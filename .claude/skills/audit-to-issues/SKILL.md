---
name: audit-to-issues
description: Crea GitHub issues a partir de un documento de auditoria de codigo, uno por hallazgo.
disable-model-invocation: true
allowed-tools:
  - Read
  - Bash(gh issue *)
  - Bash(gh label *)
  - Bash(gh auth status)
---

# Audit to Issues Skill

Convierte un documento de auditoria en GitHub issues individuales.

## Input

`$ARGUMENTS` — Ruta al documento de auditoria. Ejemplo:
- `/audit-to-issues docs/2026-03-28-code-audit.md`

Si no se proporciona argumento, buscar el documento de auditoria mas reciente en `docs/`.

## Procedimiento

### Fase 1: Preparar labels

Verificar que existen los labels necesarios. Si no existen, crearlos:

```bash
gh label create "audit" --description "Hallazgo de auditoria de codigo" --color "d4c5f9" --force
gh label create "severity:alta" --description "Severidad alta - funcionalidad rota o perdida de datos" --color "d73a4a" --force
gh label create "severity:media" --description "Severidad media - datos stale o performance" --color "e4a221" --force
gh label create "severity:baja" --description "Severidad baja - code quality o cosmetico" --color "0e8a16" --force
```

### Fase 2: Leer y parsear el documento

1. Leer el documento de auditoria completo
2. Extraer cada hallazgo con estos campos:
   - **ID**: H1, M1, L1, etc.
   - **Titulo**: Texto del heading `### H1. Titulo aqui`
   - **Severidad**: Alta/Media/Baja (derivada del prefijo H/M/L)
   - **Archivo**: Linea `**Archivo:**`
   - **Codigo**: Bloque(s) de codigo entre triple backticks
   - **Impacto**: Linea `**Impacto:**`
   - **Fix**: Linea `**Fix:**` (puede incluir codigo)

### Fase 3: Verificar issues existentes

Antes de crear issues, buscar issues ya existentes para evitar duplicados:

```bash
gh issue list --label "audit" --state all --limit 200
```

Si un hallazgo ya tiene un issue (matchear por ID en el titulo, e.g., `[H1]`), **saltarlo** y reportar que ya existe.

### Fase 4: Crear issues

Para cada hallazgo que no tenga issue existente, crear un GitHub issue:

**Titulo:** `[SEVERITY_ID] Titulo del hallazgo`
- Ejemplo: `[H1] SQL injection en admin members search`

**Body:** Usar este formato exacto:

```markdown
## Hallazgo de Auditoria: SEVERITY_ID

**Severidad:** Alta|Media|Baja
**Archivo:** `ruta/al/archivo.rb:lineas`
**Auditoria:** nombre-del-documento.md

### Problema

[Contenido del codigo problematico]

### Impacto

[Texto de impacto]

### Fix propuesto

[Texto del fix con codigo si aplica]
```

**Labels:**
- `audit`
- `severity:alta` | `severity:media` | `severity:baja` (segun prefijo)

**Assignee:** Self-assign (el usuario actual de gh).

Comando para crear cada issue:

```bash
gh issue create \
  --title "[H1] Titulo del hallazgo" \
  --body "$(cat <<'EOF'
## Hallazgo de Auditoria: H1
...contenido...
EOF
)" \
  --label "audit,severity:alta" \
  --assignee "@me"
```

### Fase 5: Generar resumen

Al finalizar, imprimir una tabla resumen:

```
| ID  | Titulo                              | Issue # | Estado   |
|-----|-------------------------------------|---------|----------|
| H1  | SQL injection en admin search       | #42     | Creado   |
| H2  | N+1 en onboarding requests          | #43     | Creado   |
| M1  | Missing index en members            | #38     | Ya existe|
| ... | ...                                 | ...     | ...      |
```

## Reglas

- **No duplicar**: Verificar issues existentes antes de crear
- **Batch ordering**: Crear issues en orden de severidad (Alta primero, luego Media, luego Baja)
- **Preservar formato**: El body del issue debe ser legible y bien formateado en GitHub
- **Error handling**: Si `gh issue create` falla, reportar el error y continuar con el siguiente hallazgo
- **Ritmo**: Pausar brevemente entre creaciones para evitar rate limiting de la API de GitHub
