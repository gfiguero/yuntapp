# Spec: Rediseño UI Panel Superadmin

**Fecha:** 2026-03-29
**Estado:** Aprobado
**Tipo:** UI/UX — Modernización visual

---

## Objetivo

Modernizar el panel de superadministrador de Yuntapp usando DaisyUI + Tailwind CSS, corrigiendo bugs, mejorando la jerarquía visual, y aplicando los principios de Accessible & Ethical + Minimalism adecuados para una aplicación de gobierno/servicio público.

---

## Sistema de Diseño

- **Estilo:** Accessible & Ethical + Minimalism (Government/Public Service)
- **Paleta:** Primary `#2563EB`, Background `#F8FAFC`, Text `#1E293B`
- **Stack:** DaisyUI + Tailwind CSS (sin dependencias nuevas)
- **Íconos:** SVG inline via helper `icon()` existente
- **Temas:** DaisyUI `data-theme="light"` (sin cambios)

---

## Bugs a Corregir

| ID | Archivo | Descripción |
|----|---------|-------------|
| B1 | `layouts/superadmin.html.erb:64` | Sección "Sistema" duplicada — segunda instancia renombrar a "Sesión" |
| B2 | `layouts/superadmin.html.erb` | `content_for :breadcrumb` definido pero nunca renderizado en el layout |
| B3 | `layouts/superadmin.html.erb:33` | H1 hardcodeado "Administración" conflicta con H1 de cada página |
| B4 | `layouts/superadmin.html.erb:45` | Link Dashboard apunta a `admin_root_path` en vez de `superadmin_root_path` |

---

## Cambios por Componente

### 1. Layout (`layouts/superadmin.html.erb`)

**Sidebar:**
- Cambiar fondo: `bg-base-200` → `bg-base-100 border-r border-base-200`
- Agregar íconos SVG a todos los links de navegación
- Agregar sección de usuario logueado al final del sidebar (email + badge "Superadmin")
- Renombrar segunda sección "Sistema" → "Sesión"
- Corregir link Dashboard a `superadmin_root_path`
- Item activo: clase `active` ya funciona con DaisyUI menu

**Top bar (mobile):**
- Reemplazar texto plano "Admin Panel" por `content_for(:title) || "Superadmin"`

**Header del contenido:**
- Eliminar el `<div class="flex justify-between">` con H1 hardcodeado "Administración"
- Agregar en su lugar: `yield :breadcrumb` como `div.breadcrumbs text-sm mb-2`

### 2. Dashboard (`superadmin/dashboard/index.html.erb` + controlador)

Reemplazar el hero box por:
- 5 stat cards en grid responsive (2 cols móvil, 3-5 desktop)
- Datos: Juntas de Vecinos, Onboarding Pendientes, Identidad Pendientes, Residencia Pendientes, Usuarios
- Links de acceso rápido debajo de las stats

**Controlador:** Añadir queries para stats al `DashboardController#index`.

### 3. Tablas — todas las `_table.html.erb` del superadmin

- Agregar clase `table-zebra` a `<table>` para legibilidad
- Agregar empty state en `<tbody>` cuando no hay registros:
  ```erb
  <% if collection.empty? %>
    <tr><td colspan="N" class="text-center py-8 text-base-content/50">
      Sin registros.
    </td></tr>
  <% end %>
  ```

### 4. Botones de acción — `_buttons.html.erb` de todas las secciones

- Cambiar `btn-warning` por `btn-error` en el botón "Eliminar" de las vistas show/edit
- Agregar `aria-label` a botones icon-only en `_*_row.html.erb`

### 5. Helper `status_badge` (`application_helper.rb`)

Agregar casos faltantes:
- `"issued"` → `badge-info`
- `"verified"` → `badge-primary`

---

## Archivos a Modificar

| Archivo | Cambio |
|---------|--------|
| `app/views/layouts/superadmin.html.erb` | Layout completo — sidebar, topbar, breadcrumbs, fix bugs |
| `app/views/superadmin/dashboard/index.html.erb` | Stat cards |
| `app/controllers/superadmin/dashboard_controller.rb` | Queries para stats |
| `app/helpers/application_helper.rb` | status_badge: issued/verified |
| `app/views/superadmin/neighborhood_associations/_table.html.erb` | table-zebra + empty state |
| `app/views/superadmin/neighborhood_associations/_buttons.html.erb` | btn-error en delete |
| `app/views/superadmin/neighborhood_associations/_neighborhood_association_row.html.erb` | aria-label |
| `app/views/superadmin/onboarding_requests/_table.html.erb` | table-zebra + empty state |
| `app/views/superadmin/onboarding_requests/_buttons.html.erb` | btn-error |
| `app/views/superadmin/onboarding_requests/_onboarding_request_row.html.erb` | aria-label |
| `app/views/superadmin/identity_verification_requests/_table.html.erb` | table-zebra + empty state |
| `app/views/superadmin/identity_verification_requests/_buttons.html.erb` | btn-error |
| `app/views/superadmin/identity_verification_requests/_identity_verification_request_row.html.erb` | aria-label |
| `app/views/superadmin/residence_verification_requests/_table.html.erb` | table-zebra + empty state |
| `app/views/superadmin/residence_verification_requests/_buttons.html.erb` | btn-error |
| `app/views/superadmin/residence_verification_requests/_residence_verification_request_row.html.erb` | aria-label |
| `app/views/superadmin/regions/_table.html.erb` | table-zebra + empty state |
| `app/views/superadmin/regions/_buttons.html.erb` | btn-error |
| `app/views/superadmin/communes/_table.html.erb` | table-zebra + empty state |
| `app/views/superadmin/communes/_buttons.html.erb` | btn-error |
| `app/views/superadmin/countries/_table.html.erb` | table-zebra + empty state |
| `app/views/superadmin/countries/_buttons.html.erb` | btn-error |
| `app/views/superadmin/categories/_table.html.erb` | table-zebra + empty state |
| `app/views/superadmin/categories/_buttons.html.erb` | btn-error |
| `app/views/superadmin/tags/_table.html.erb` | table-zebra + empty state |
| `app/views/superadmin/tags/_buttons.html.erb` | btn-error |

---

## Criterios de Éxito

- [ ] Sin breadcrumbs fantasma (se muestran en todas las páginas del superadmin)
- [ ] Sin título duplicado en ninguna vista
- [ ] Dashboard muestra datos reales (no hero vacío)
- [ ] Sidebar con íconos y usuario logueado visible
- [ ] Botón eliminar en rojo (btn-error) en todas las secciones
- [ ] Tablas con zebra y empty state
- [ ] No se introducen dependencias nuevas
- [ ] Tests existentes siguen pasando
