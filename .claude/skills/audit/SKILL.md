---
name: audit
description: Genera una auditoria integral del codebase identificando bugs, security issues, missing validations, N+1 queries, problemas de performance, dead code y schema issues.
disable-model-invocation: true
allowed-tools:
  - Read
  - Grep
  - Glob
  - Task
  - Bash(bundle exec rubocop*)
  - Bash(bundle exec erb_lint*)
  - Bash(bin/rails test*)
  - Bash(ls *)
---

# Code Audit Skill

Genera un documento de auditoria estructurado para el codebase yuntapp.

## Input

`$ARGUMENTS` — Scope opcional de la auditoria. Ejemplos:
- `/audit` — Auditoria completa de todo el codebase
- `/audit models` — Solo modelos
- `/audit controllers` — Solo controladores
- `/audit onboarding` — Solo modulo de onboarding
- `/audit admin` — Solo panel de administracion
- `/audit auth` — Solo autenticacion y autorizacion

Si no se proporciona scope, auditar todo el codebase.

## Procedimiento

### Fase 1: Recopilar hallazgos previos

1. Leer **todos** los documentos de auditoria existentes en `docs/`:
   - Buscar archivos con patron `docs/*audit*.md` y `docs/*code-audit*.md`
2. Extraer los IDs de todos los hallazgos ya reportados (H1, M1, L1, etc.)
3. Estos hallazgos se **excluyen** de la nueva auditoria para evitar duplicados
4. Tambien verificar si hallazgos previos fueron resueltos (buscar PRs que los referencien)

### Fase 2: Exploracion sistematica

Explorar el codebase segun el scope indicado. Para auditoria completa, cubrir **todas** estas areas:

| Area | Archivos clave |
|------|---------------|
| **Models** | `app/models/*.rb`, `app/models/concerns/*.rb` |
| **Controllers** | `app/controllers/**/*.rb` |
| **Views** | `app/views/**/*.html.erb` |
| **Helpers** | `app/helpers/*.rb` |
| **Validators** | `app/validators/*.rb` |
| **JavaScript** | `app/javascript/**/*.js` |
| **Config** | `config/routes.rb`, `config/locales/*.yml` |
| **Migrations** | `db/migrate/*.rb` |
| **Schema** | `db/schema.rb` |
| **Tests** | `test/**/*.rb` |

Para cada archivo, buscar:

1. **Security** — SQL injection, XSS, CSRF bypass, mass assignment sin strong params, secrets expuestos
2. **N+1 queries** — Queries en loops, missing includes/eager_load, counter_cache faltante
3. **Missing validations** — Campos requeridos sin validar, formatos no validados, unicidad sin indice
4. **Authorization** — Acceso sin verificar rol, recursos de otra asociacion accesibles
5. **I18n** — Strings hardcodeados en vistas, mensajes flash sin traducir
6. **Performance** — Queries sin indice, loads de tablas completas, missing pagination
7. **Dead code** — Metodos no referenciados, rutas sin controlador, vistas huerfanas
8. **Schema issues** — Missing indexes en foreign keys, campos sin null constraint, inconsistencias
9. **Race conditions** — Operaciones no atomicas, missing database locks
10. **Inconsistencias** — Patrones diferentes para la misma operacion entre modulos

### Fase 3: Ejecutar herramientas de analisis estatico

1. Ejecutar `bundle exec rubocop` y anotar warnings/errors relevantes
2. Ejecutar `bundle exec erb_lint --lint-all` y anotar errores
3. Ejecutar `bin/rails test` y anotar tests fallidos

### Fase 4: Clasificar hallazgos

Clasificar cada hallazgo por severidad:

**Alta (H)** — Perdida de datos, funcionalidad rota, crash en produccion, vulnerabilidad de seguridad explotable
- SQL injection, XSS, acceso no autorizado a datos, datos perdidos silenciosamente

**Media (M)** — Datos stale, performance degradada, inconsistencias que causan bugs intermitentes, missing validation
- N+1 queries, missing indexes, validaciones faltantes, i18n incompleto

**Baja (L)** — Code quality, dead code, inconsistencias menores, mejoras cosmeticas
- Dead code, naming conventions, rubocop warnings menores

### Fase 5: Generar documento

Crear el archivo `docs/YYYY-MM-DD-code-audit.md` (usar fecha actual) con este formato exacto:

```markdown
# Code Audit - YYYY-MM-DD

[Descripcion breve del scope y contexto de la auditoria. Mencionar auditorias previas excluidas.]

---

## Severidad Alta

### H1. [Titulo descriptivo del hallazgo]

**Archivo:** `ruta/al/archivo.rb:lineas`

```ruby
# Codigo problematico con comentarios explicativos
```

**Impacto:** [Explicacion clara de las consecuencias en produccion]

**Fix:** [Solucion concreta, idealmente con codigo]

---

### H2. [Siguiente hallazgo...]

[...repetir para cada hallazgo Alta...]

## Severidad Media

### M1. [Titulo descriptivo]

[...mismo formato...]

## Severidad Baja

### L1. [Titulo descriptivo]

[...mismo formato...]

## Resumen

| Severidad | Count | IDs |
|-----------|-------|-----|
| **Alta**  | N     | H1-HN |
| **Media** | N     | M1-MN |
| **Baja**  | N     | L1-LN |

## Orden recomendado de implementacion

1. **H1** — [razon, complejidad estimada]
2. **H2+H3** — [agrupar fixes relacionados]
[...etc...]
```

## Reglas

- **Idioma**: Todo en espanol (consistente con el proyecto)
- **No duplicar**: Excluir hallazgos ya reportados en auditorias previas
- **Codigo real**: Siempre incluir snippets del codigo actual, no ejemplos inventados
- **Lineas exactas**: Referenciar numeros de linea reales del archivo
- **Fix concreto**: Cada hallazgo debe tener una solucion implementable, no solo la descripcion del problema
- **Sin falsos positivos**: Solo reportar problemas reales y verificados. Si no estas seguro, no lo incluyas.
- **Agrupar relacionados**: En el orden de implementacion, agrupar fixes que tocan los mismos archivos o patrones
