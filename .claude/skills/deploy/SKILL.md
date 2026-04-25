---
name: deploy
description: Workflow de deploy con Kamal para yuntapp. Cubre pre-deploy checklist, migraciones, health checks y rollback.
user-invocable: true
allowed-tools:
  - Read
  - Bash(git log*)
  - Bash(git status*)
  - Bash(git diff*)
  - Bash(bin/rails test*)
  - Bash(bundle exec standardrb*)
  - Bash(bundle exec erb_lint*)
  - Bash(ls*)
  - Bash(grep*)
---

# Deploy — yuntapp (Kamal + Docker + Thruster)

Workflow de deploy de produccion para yuntapp usando Kamal.

## Input

`$ARGUMENTS` — Tipo de deploy. Ejemplos:
- `/deploy` — deploy estandar (main branch)
- `/deploy rollback` — rollback al deploy anterior
- `/deploy status` — estado actual del servidor
- `/deploy logs` — ver logs de produccion

## Stack de deploy

| Componente | Herramienta |
|------------|-------------|
| Orquestador | Kamal 2 |
| Contenedor | Docker (multi-stage) |
| Proxy HTTP | Thruster (caching + compresion) |
| Base de datos | SQLite3 (persistente en VPS) |
| Background jobs | Solid Queue |
| Cache | Solid Cache |
| WebSockets | Solid Cable |
| Config | `config/deploy.yml` |

## Comandos Kamal de referencia

```bash
kamal deploy           # deploy completo (build + push + run)
kamal rollback         # rollback al deploy anterior
kamal app logs         # ver logs del contenedor app
kamal app exec 'cmd'   # ejecutar comando en contenedor prod
kamal app exec 'bin/rails db:migrate'   # correr migraciones
kamal app exec 'bin/rails console'      # consola de produccion
kamal app details      # version y estado del contenedor
kamal app boot         # reiniciar app sin nuevo deploy
kamal proxy logs       # logs de Thruster
kamal accessory logs <name>  # logs de accessory (queue, cable)
```

## Fase 1: Pre-deploy checklist

Antes de cualquier deploy a produccion:

### 1.1 Verificar estado del branch

```bash
git status              # no debe haber cambios sin commitear
git log main..HEAD      # debe estar sincronizado con origin/main
```

### 1.2 Ejecutar suite de calidad completa

```bash
bundle exec standardrb
bundle exec erb_lint --lint-all
bin/rails test
```

Las tres deben pasar. Si alguna falla, NO deployar.

### 1.3 Verificar migraciones pendientes

```bash
bin/rails db:migrate:status
```

Si hay migraciones pendientes, el deploy las aplicara automaticamente (ver Fase 3).

### 1.4 Revisar cambios de schema

```bash
git diff origin/main -- db/schema.rb
```

Si hay cambios de schema, revisar que:
- [ ] Son backwards-compatible (el codigo anterior puede correr con el schema nuevo)
- [ ] No hay columnas NOT NULL sin default en tablas con datos
- [ ] Hay indices en todas las foreign keys nuevas

### 1.5 Revisar variables de entorno

Si se agregaron nuevas variables de entorno:
- [ ] Estan configuradas en el servidor (`kamal env push`)
- [ ] Tienen valores correctos en produccion
- [ ] El `Dockerfile` las expone si es necesario

## Fase 2: Deploy

```bash
kamal deploy
```

Kamal hace en orden:
1. Build de la imagen Docker
2. Push al registry
3. Pull en el servidor
4. `bin/rails db:migrate` (configurado en deploy.yml)
5. Boot del nuevo contenedor
6. Health check
7. Swap del proxy (zero-downtime)

## Fase 3: Migraciones en produccion

Las migraciones corren automaticamente durante el deploy si `config/deploy.yml` tiene:

```yaml
# config/deploy.yml
boot:
  cmd: bin/rails db:migrate && bin/rails server
```

Si necesitas correr migraciones manualmente:

```bash
kamal app exec 'bin/rails db:migrate'
```

### Consideraciones SQLite3

A diferencia de PostgreSQL, SQLite3 tiene limitaciones en migraciones con datos grandes:
- **Sin transacciones DDL separadas**: ALTER TABLE es atomico pero no concurrente
- **Sin `CREATE INDEX CONCURRENTLY`**: Los indices en SQLite siempre bloquean brevemente
- **Backups antes de migraciones destructivas**: `kamal app exec 'cp db/production.sqlite3 db/production.sqlite3.bak'`

Para migraciones de datos grandes en SQLite3:

```ruby
# En lugar de UPDATE masivo, usar batches
User.in_batches(of: 1000) do |batch|
  batch.update_all(normalized_status: "active")
end
```

## Fase 4: Post-deploy verification

Despues de que Kamal reporte deploy exitoso:

### 4.1 Verificar health check

```bash
curl https://tu-dominio.com/up
# Debe devolver 200 OK
```

### 4.2 Verificar logs

```bash
kamal app logs --since 5m
```

Buscar errores de:
- Migraciones fallidas
- Variables de entorno faltantes
- Errores de conexion a servicios

### 4.3 Verificar version desplegada

```bash
kamal app details
# Muestra el SHA del commit deployado
```

### 4.4 Smoke test manual

Verificar que el flujo critico funciona:
1. Login de usuario
2. Panel de onboarding
3. Panel de admin (si aplica)
4. Superadmin (si aplica)

## Fase 5: Rollback

Si algo falla en produccion:

```bash
kamal rollback
```

Kamal revierte al contenedor anterior (que sigue disponible en el servidor).

### Despues del rollback

Si el deploy que se revirtio incluia migraciones:

```bash
kamal app exec 'bin/rails db:rollback'
```

Solo si la migracion es reversible. Si no lo es, crear una migracion correctiva.

### Decision de rollback

Hacer rollback inmediatamente si:
- Error 500 en mas del 5% de requests
- Login no funciona
- Datos corruptos o perdidos
- Migracion fallo a mitad

NO hacer rollback si:
- Es un problema de configuracion (corregir con `kamal env push + kamal app boot`)
- Es un bug de UI menor (fix forward)

## Deploy de emergencia (hotfix)

```bash
git checkout main
git pull origin main
git checkout -b fix/descripcion-hotfix
# ... hacer el fix ...
git add <files>
git commit -m "fix: descripcion del hotfix"
git push -u origin fix/descripcion-hotfix
# Crear PR, aprobar, merge a main
git checkout main && git pull origin main
kamal deploy
```

## Checklist pre-produccion completo

- [ ] `bundle exec standardrb` — OK
- [ ] `bundle exec erb_lint --lint-all` — OK
- [ ] `bin/rails test` — todos pasan
- [ ] `bin/rails db:migrate:status` — sin migraciones pendientes inesperadas
- [ ] Schema changes son backwards-compatible
- [ ] Variables de entorno nuevas configuradas en servidor
- [ ] No hay secrets hardcodeados en el codigo nuevo
- [ ] Smoke test en staging (si existe) — OK

## Reglas

- **Nunca deployar con tests rojos** — sin excepciones
- **Nunca editar archivos directamente en el servidor** — todo via deploy
- **Siempre verificar logs post-deploy** — aunque Kamal reporte exito
- **Rollback rapido** — ante la duda, rollback primero, diagnosticar despues
- **Migraciones separadas del codigo** — el schema nuevo debe ser compatible con el codigo anterior
- **Backups antes de migraciones destructivas** — especialmente en SQLite3
