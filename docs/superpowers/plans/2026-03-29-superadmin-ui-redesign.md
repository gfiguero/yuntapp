# Superadmin UI Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Modernizar el panel superadmin de Yuntapp corrigiendo bugs visuales, mejorando la navegación con íconos, añadiendo un dashboard con estadísticas reales, y aplicando mejores prácticas de DaisyUI + Tailwind.

**Architecture:** Cambios puramente en capa de presentación (views + helper + controller). Sin migraciones, sin nuevas dependencias. Se respetan todos los patrones existentes del proyecto (partials, DaisyUI, i18n).

**Tech Stack:** Rails 8.1, ERB, DaisyUI 4, Tailwind CSS, helper `icon()` existente.

---

## Resumen de Archivos

| Archivo | Acción |
|---------|--------|
| `app/views/layouts/superadmin.html.erb` | Modificar — Fix bugs + sidebar con íconos + user info + breadcrumbs |
| `app/controllers/superadmin/dashboard_controller.rb` | Modificar — Añadir queries de stats |
| `app/views/superadmin/dashboard/index.html.erb` | Reemplazar — Stat cards + accesos rápidos |
| `app/helpers/application_helper.rb` | Modificar — status_badge: añadir issued/verified |
| `app/views/superadmin/neighborhood_associations/_table.html.erb` | Modificar — table-zebra + empty state |
| `app/views/superadmin/neighborhood_associations/_neighborhood_association_row.html.erb` | Modificar — btn-error + aria-label |
| `app/views/superadmin/neighborhood_associations/_buttons.html.erb` | Modificar — btn-error |
| `app/views/superadmin/onboarding_requests/_table.html.erb` | Modificar — table-zebra + empty state |
| `app/views/superadmin/onboarding_requests/_onboarding_request_row.html.erb` | Modificar — btn-error + aria-label |
| `app/views/superadmin/onboarding_requests/_buttons.html.erb` | Modificar — btn-error |
| `app/views/superadmin/identity_verification_requests/_table.html.erb` | Modificar — table-zebra + empty state |
| `app/views/superadmin/identity_verification_requests/_identity_verification_request_row.html.erb` | Modificar — btn-error + aria-label |
| `app/views/superadmin/identity_verification_requests/_buttons.html.erb` | Modificar — btn-error |
| `app/views/superadmin/residence_verification_requests/_table.html.erb` | Modificar — table-zebra + empty state |
| `app/views/superadmin/residence_verification_requests/_residence_verification_request_row.html.erb` | Modificar — btn-error + aria-label |
| `app/views/superadmin/residence_verification_requests/_buttons.html.erb` | Modificar — btn-error |
| `app/views/superadmin/regions/_table.html.erb` | Modificar — table-zebra + empty state |
| `app/views/superadmin/regions/_region_row.html.erb` | Modificar — btn-error + aria-label |
| `app/views/superadmin/regions/_buttons.html.erb` | Modificar — btn-error |
| `app/views/superadmin/communes/_table.html.erb` | Modificar — table-zebra + empty state |
| `app/views/superadmin/communes/_commune_row.html.erb` | Modificar — btn-error + aria-label |
| `app/views/superadmin/communes/_buttons.html.erb` | Modificar — btn-error |
| `app/views/superadmin/countries/_table.html.erb` | Modificar — table-zebra + empty state |
| `app/views/superadmin/countries/_country_row.html.erb` | Modificar — btn-error + aria-label |
| `app/views/superadmin/countries/_buttons.html.erb` | Modificar — btn-error |
| `app/views/superadmin/categories/_table.html.erb` | Modificar — table-zebra + empty state |
| `app/views/superadmin/categories/_category_row.html.erb` | Modificar — btn-error + aria-label |
| `app/views/superadmin/categories/_buttons.html.erb` | Modificar — btn-error |
| `app/views/superadmin/tags/_table.html.erb` | Modificar — table-zebra + empty state |
| `app/views/superadmin/tags/_tag_row.html.erb` | Modificar — btn-error + aria-label |
| `app/views/superadmin/tags/_buttons.html.erb` | Modificar — btn-error |

---

## Task 1: Fix Layout — Bugs críticos + Sidebar + Breadcrumbs

**Files:**
- Modify: `app/views/layouts/superadmin.html.erb`

- [ ] **Step 1: Reemplazar el layout completo**

Reemplazar el contenido completo de `app/views/layouts/superadmin.html.erb` con:

```erb
<!DOCTYPE html>
<html data-theme="light">
  <head>
    <title><%= content_for(:title) || "Yuntapp Superadmin" %></title>
    <link rel="icon" href="/favicon.ico" sizes="any">
    <link rel="icon" href="/favicon.svg" type="image/svg+xml">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>

    <%= yield :head %>

    <%= stylesheet_link_tag :app, "data-turbo-track": "reload" %>
    <%= javascript_importmap_tags %>
  </head>

  <body>
    <div class="drawer lg:drawer-open">
      <input id="my-drawer-2" type="checkbox" class="drawer-toggle">
      <div class="drawer-content flex flex-col items-center justify-start min-h-screen">

        <!-- Top bar (mobile + breadcrumbs) -->
        <div class="w-full bg-base-100 border-b border-base-200 px-4 py-3 flex items-center gap-3">
          <label for="my-drawer-2" class="btn btn-square btn-ghost btn-sm drawer-button lg:hidden">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" class="inline-block w-5 h-5 stroke-current">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16"></path>
            </svg>
          </label>
          <div class="text-sm breadcrumbs flex-1">
            <ul>
              <li><%= link_to "Superadmin", superadmin_root_path, class: "text-base-content/60 hover:text-base-content" %></li>
              <%= yield :breadcrumb %>
            </ul>
          </div>
        </div>

        <main class="container mx-auto mt-4 mb-8 px-5 flex flex-col w-full">
          <%= yield %>
        </main>

        <%= render "shared/footer" %>
      </div>

      <!-- Sidebar -->
      <div class="drawer-side h-screen z-50">
        <label for="my-drawer-2" aria-label="close sidebar" class="drawer-overlay"></label>
        <div class="flex flex-col w-72 bg-base-100 border-r border-base-200 h-full overflow-y-auto">

          <!-- Brand -->
          <div class="px-4 py-5 border-b border-base-200">
            <div class="flex items-center gap-2">
              <%= icon("home", class: "w-6 h-6 text-primary") %>
              <span class="font-bold text-lg text-base-content">Yuntapp</span>
              <span class="badge badge-primary badge-sm ml-auto">Superadmin</span>
            </div>
          </div>

          <!-- Navigation -->
          <ul class="menu menu-sm p-3 flex-1 gap-1">
            <li>
              <%= link_to superadmin_root_path,
                    class: "flex items-center gap-2 #{current_page?(superadmin_root_path) ? 'bg-primary text-primary-content rounded-lg' : ''}" do %>
                <%= icon("home", class: "w-4 h-4") %>
                Dashboard
              <% end %>
            </li>

            <li class="menu-title text-xs uppercase tracking-wider mt-3">Gestión Global</li>
            <li>
              <%= link_to superadmin_neighborhood_associations_path,
                    class: "flex items-center gap-2 #{controller_name == 'neighborhood_associations' ? 'bg-primary text-primary-content rounded-lg' : ''}" do %>
                <%= icon("users", class: "w-4 h-4") %>
                Juntas de Vecinos
              <% end %>
            </li>
            <li>
              <%= link_to superadmin_users_path,
                    class: "flex items-center gap-2 #{controller_name == 'users' ? 'bg-primary text-primary-content rounded-lg' : ''}" do %>
                <%= icon("user", class: "w-4 h-4") %>
                Usuarios
              <% end %>
            </li>

            <li class="menu-title text-xs uppercase tracking-wider mt-3">Solicitudes</li>
            <li>
              <%= link_to superadmin_onboarding_requests_path,
                    class: "flex items-center gap-2 #{controller_name == 'onboarding_requests' ? 'bg-primary text-primary-content rounded-lg' : ''}" do %>
                <%= icon("list", class: "w-4 h-4") %>
                Onboarding
              <% end %>
            </li>
            <li>
              <%= link_to superadmin_identity_verification_requests_path,
                    class: "flex items-center gap-2 #{controller_name == 'identity_verification_requests' ? 'bg-primary text-primary-content rounded-lg' : ''}" do %>
                <%= icon("id", class: "w-4 h-4") %>
                Identidad
              <% end %>
            </li>
            <li>
              <%= link_to superadmin_residence_verification_requests_path,
                    class: "flex items-center gap-2 #{controller_name == 'residence_verification_requests' ? 'bg-primary text-primary-content rounded-lg' : ''}" do %>
                <%= icon("home", class: "w-4 h-4") %>
                Residencia
              <% end %>
            </li>

            <li class="menu-title text-xs uppercase tracking-wider mt-3">Geografía</li>
            <li>
              <%= link_to superadmin_countries_path,
                    class: "flex items-center gap-2 #{controller_name == 'countries' ? 'bg-primary text-primary-content rounded-lg' : ''}" do %>
                <%= icon("map-pin", class: "w-4 h-4") %>
                Países
              <% end %>
            </li>
            <li>
              <%= link_to superadmin_regions_path,
                    class: "flex items-center gap-2 #{controller_name == 'regions' ? 'bg-primary text-primary-content rounded-lg' : ''}" do %>
                <%= icon("map-pin", class: "w-4 h-4") %>
                Regiones
              <% end %>
            </li>
            <li>
              <%= link_to superadmin_communes_path,
                    class: "flex items-center gap-2 #{controller_name == 'communes' ? 'bg-primary text-primary-content rounded-lg' : ''}" do %>
                <%= icon("map-pin", class: "w-4 h-4") %>
                Comunas
              <% end %>
            </li>

            <li class="menu-title text-xs uppercase tracking-wider mt-3">Configuración</li>
            <li>
              <%= link_to superadmin_categories_path,
                    class: "flex items-center gap-2 #{controller_name == 'categories' ? 'bg-primary text-primary-content rounded-lg' : ''}" do %>
                <%= icon("archive", class: "w-4 h-4") %>
                Categorías
              <% end %>
            </li>
            <li>
              <%= link_to superadmin_tags_path,
                    class: "flex items-center gap-2 #{controller_name == 'tags' ? 'bg-primary text-primary-content rounded-lg' : ''}" do %>
                <%= icon("filter", class: "w-4 h-4") %>
                Etiquetas
              <% end %>
            </li>
          </ul>

          <!-- Footer: user info + logout -->
          <div class="border-t border-base-200 p-4">
            <div class="flex items-center gap-3 mb-3">
              <div class="avatar placeholder">
                <div class="bg-primary text-primary-content rounded-full w-8">
                  <span class="text-xs"><%= current_user.email.first.upcase %></span>
                </div>
              </div>
              <div class="flex-1 min-w-0">
                <div class="text-xs font-medium truncate"><%= current_user.email %></div>
                <div class="text-xs text-base-content/50">Superadmin</div>
              </div>
            </div>
            <%= link_to destroy_user_session_path,
                  data: { turbo_method: :delete },
                  class: "btn btn-sm btn-ghost btn-block justify-start gap-2 text-error hover:bg-error/10" do %>
              <%= icon("restart", class: "w-4 h-4") %>
              Cerrar Sesión
            <% end %>
          </div>

        </div>
      </div>
    </div>
    <%= yield :filter_drawer %>
  </body>
</html>
```

- [ ] **Step 2: Verificar que no hay errores de sintaxis**

```bash
bin/rails runner "puts 'layout OK'"
```
Esperado: `layout OK` sin errores.

- [ ] **Step 3: Commit**

```bash
git add app/views/layouts/superadmin.html.erb
git commit -m "ui: modernizar layout superadmin — sidebar con íconos, breadcrumbs, user info, fix bugs"
```

---

## Task 2: Dashboard con Estadísticas Reales

**Files:**
- Modify: `app/controllers/superadmin/dashboard_controller.rb`
- Modify: `app/views/superadmin/dashboard/index.html.erb`

- [ ] **Step 1: Actualizar el controlador con queries de stats**

Reemplazar `app/controllers/superadmin/dashboard_controller.rb`:

```ruby
module Superadmin
  class DashboardController < ApplicationController
    def index
      @stats = {
        neighborhood_associations: NeighborhoodAssociation.count,
        onboarding_pending: OnboardingRequest.where(status: "pending").count,
        identity_pending: IdentityVerificationRequest.where(status: "pending").count,
        residence_pending: ResidenceVerificationRequest.where(status: "pending").count,
        users_total: User.count
      }
    end
  end
end
```

- [ ] **Step 2: Reemplazar la vista del dashboard**

Reemplazar `app/views/superadmin/dashboard/index.html.erb`:

```erb
<% content_for :title do %>Dashboard<% end %>

<div class="mb-6">
  <h1 class="text-2xl font-bold text-base-content">Panel de Control</h1>
  <p class="text-sm text-base-content/60 mt-1">Resumen global del sistema Yuntapp</p>
</div>

<!-- Stat Cards -->
<div class="grid grid-cols-2 lg:grid-cols-5 gap-4 mb-8">
  <div class="card bg-base-100 border border-base-200 shadow-sm">
    <div class="card-body p-4">
      <div class="flex items-start justify-between">
        <div>
          <div class="text-xs font-semibold uppercase tracking-wider text-base-content/50 mb-1">Juntas de Vecinos</div>
          <div class="text-3xl font-extrabold text-primary"><%= @stats[:neighborhood_associations] %></div>
        </div>
        <div class="text-primary opacity-20"><%= icon("users", class: "w-8 h-8") %></div>
      </div>
      <%= link_to "Ver todas", superadmin_neighborhood_associations_path, class: "text-xs text-primary hover:underline mt-2 block" %>
    </div>
  </div>

  <div class="card bg-base-100 border border-base-200 shadow-sm">
    <div class="card-body p-4">
      <div class="flex items-start justify-between">
        <div>
          <div class="text-xs font-semibold uppercase tracking-wider text-base-content/50 mb-1">Onboarding Pendientes</div>
          <div class="text-3xl font-extrabold <%= @stats[:onboarding_pending] > 0 ? 'text-warning' : 'text-base-content/40' %>"><%= @stats[:onboarding_pending] %></div>
        </div>
        <div class="text-warning opacity-20"><%= icon("list", class: "w-8 h-8") %></div>
      </div>
      <%= link_to "Revisar", superadmin_onboarding_requests_path, class: "text-xs text-primary hover:underline mt-2 block" %>
    </div>
  </div>

  <div class="card bg-base-100 border border-base-200 shadow-sm">
    <div class="card-body p-4">
      <div class="flex items-start justify-between">
        <div>
          <div class="text-xs font-semibold uppercase tracking-wider text-base-content/50 mb-1">Identidad Pendientes</div>
          <div class="text-3xl font-extrabold <%= @stats[:identity_pending] > 0 ? 'text-warning' : 'text-base-content/40' %>"><%= @stats[:identity_pending] %></div>
        </div>
        <div class="text-warning opacity-20"><%= icon("id", class: "w-8 h-8") %></div>
      </div>
      <%= link_to "Revisar", superadmin_identity_verification_requests_path, class: "text-xs text-primary hover:underline mt-2 block" %>
    </div>
  </div>

  <div class="card bg-base-100 border border-base-200 shadow-sm">
    <div class="card-body p-4">
      <div class="flex items-start justify-between">
        <div>
          <div class="text-xs font-semibold uppercase tracking-wider text-base-content/50 mb-1">Residencia Pendientes</div>
          <div class="text-3xl font-extrabold <%= @stats[:residence_pending] > 0 ? 'text-warning' : 'text-base-content/40' %>"><%= @stats[:residence_pending] %></div>
        </div>
        <div class="text-warning opacity-20"><%= icon("home", class: "w-8 h-8") %></div>
      </div>
      <%= link_to "Revisar", superadmin_residence_verification_requests_path, class: "text-xs text-primary hover:underline mt-2 block" %>
    </div>
  </div>

  <div class="card bg-base-100 border border-base-200 shadow-sm">
    <div class="card-body p-4">
      <div class="flex items-start justify-between">
        <div>
          <div class="text-xs font-semibold uppercase tracking-wider text-base-content/50 mb-1">Usuarios Totales</div>
          <div class="text-3xl font-extrabold text-base-content"><%= @stats[:users_total] %></div>
        </div>
        <div class="text-base-content opacity-10"><%= icon("users", class: "w-8 h-8") %></div>
      </div>
      <%= link_to "Ver todos", superadmin_users_path, class: "text-xs text-primary hover:underline mt-2 block" %>
    </div>
  </div>
</div>

<!-- Accesos rápidos -->
<div class="mb-2">
  <h2 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider mb-3">Accesos Rápidos</h2>
  <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
    <%= link_to superadmin_neighborhood_associations_path, class: "btn btn-outline btn-sm justify-start gap-2" do %>
      <%= icon("users", class: "w-4 h-4") %> Juntas de Vecinos
    <% end %>
    <%= link_to new_superadmin_neighborhood_association_path, class: "btn btn-primary btn-sm justify-start gap-2" do %>
      <%= icon("new", class: "w-4 h-4") %> Nueva Junta
    <% end %>
    <%= link_to superadmin_regions_path, class: "btn btn-outline btn-sm justify-start gap-2" do %>
      <%= icon("map-pin", class: "w-4 h-4") %> Regiones
    <% end %>
    <%= link_to superadmin_users_path, class: "btn btn-outline btn-sm justify-start gap-2" do %>
      <%= icon("user", class: "w-4 h-4") %> Usuarios
    <% end %>
  </div>
</div>
```

- [ ] **Step 3: Verificar que la acción index renderiza sin errores**

```bash
bin/rails runner "
  ctrl = Superadmin::DashboardController.new
  puts 'DashboardController OK'
  puts NeighborhoodAssociation.count
  puts OnboardingRequest.where(status: 'pending').count
"
```
Esperado: números sin errores.

- [ ] **Step 4: Commit**

```bash
git add app/controllers/superadmin/dashboard_controller.rb \
        app/views/superadmin/dashboard/index.html.erb
git commit -m "ui: dashboard superadmin con stat cards y accesos rápidos"
```

---

## Task 3: Helper — Añadir status_badge para issued y verified

**Files:**
- Modify: `app/helpers/application_helper.rb`

- [ ] **Step 1: Actualizar el método status_badge**

En `app/helpers/application_helper.rb`, reemplazar el método `status_badge`:

```ruby
def status_badge(status)
  badge_class = case status
  when "approved" then "badge-success"
  when "pending" then "badge-warning"
  when "rejected" then "badge-error"
  when "draft" then "badge-ghost"
  when "issued" then "badge-info"
  when "verified" then "badge-primary"
  else "badge-ghost"
  end

  label = I18n.t("panel.onboarding.status.#{status}", default: status&.capitalize)
  content_tag(:span, label, class: "badge badge-sm #{badge_class}")
end
```

- [ ] **Step 2: Verificar el helper**

```bash
bin/rails runner "
  helper = ApplicationHelper.new rescue Object.new.extend(ApplicationHelper)
  puts 'status_badge OK'
"
```
Esperado: sin errores.

- [ ] **Step 3: Commit**

```bash
git add app/helpers/application_helper.rb
git commit -m "ui: añadir status_badge para issued y verified"
```

---

## Task 4: Tablas — table-zebra + empty states

Los 9 archivos `_table.html.erb` del superadmin necesitan el mismo cambio: añadir `table-zebra` y un empty state.

**Files:**
- Modify: todos los `app/views/superadmin/**/_table.html.erb`

- [ ] **Step 1: neighborhood_associations/_table.html.erb**

```erb
<div class="my-4"><%== @pagy.series_nav() %></div>

<div class="overflow-x-auto rounded-box border border-base-content/5 bg-base-100">
  <table class="table table-zebra">
    <thead>
      <tr>
        <th><%= sort_link('superadmin_neighborhood_associations_path', I18n.t('activerecord.attributes.neighborhood_association.name'), 'name') %></th>
        <th><%= I18n.t('shared.table.actions') %></th>
      </tr>
    </thead>
    <tbody>
    <% if @neighborhood_associations.empty? %>
      <tr>
        <td colspan="2" class="text-center py-8 text-base-content/40">
          No hay juntas de vecinos registradas.
        </td>
      </tr>
    <% else %>
      <% @neighborhood_associations.each do |neighborhood_association| %>
        <%= render partial: "neighborhood_association_row", locals: { neighborhood_association: neighborhood_association } %>
      <% end %>
    <% end %>
    </tbody>
  </table>
</div>

<div class="my-4"><%== @pagy.series_nav() %></div>
```

- [ ] **Step 2: onboarding_requests/_table.html.erb**

```erb
<div class="my-4"><%== @pagy.series_nav() %></div>

<div class="overflow-x-auto rounded-box border border-base-content/5 bg-base-100">
  <table class="table table-zebra">
    <thead>
      <tr>
        <th><%= sort_link('superadmin_onboarding_requests_path', I18n.t('activerecord.attributes.onboarding_request.id'), 'id') %></th>
        <th><%= I18n.t('activerecord.attributes.onboarding_request.user') %></th>
        <th><%= I18n.t('activerecord.attributes.onboarding_request.neighborhood_association') %></th>
        <th><%= sort_link('superadmin_onboarding_requests_path', I18n.t('activerecord.attributes.onboarding_request.status'), 'status') %></th>
        <th><%= sort_link('superadmin_onboarding_requests_path', I18n.t('activerecord.attributes.onboarding_request.created_at'), 'created_at') %></th>
        <th class="w-46"><%= I18n.t('shared.table.actions') %></th>
      </tr>
    </thead>
    <tbody>
    <% if @onboarding_requests.empty? %>
      <tr>
        <td colspan="6" class="text-center py-8 text-base-content/40">
          No hay solicitudes de onboarding.
        </td>
      </tr>
    <% else %>
      <% @onboarding_requests.each do |onboarding_request| %>
        <%= render partial: "onboarding_request_row", locals: { onboarding_request: onboarding_request } %>
      <% end %>
    <% end %>
    </tbody>
  </table>
</div>

<div class="my-4"><%== @pagy.series_nav() %></div>
```

- [ ] **Step 3: identity_verification_requests/_table.html.erb**

```erb
<div class="my-4"><%== @pagy.series_nav() %></div>

<div class="overflow-x-auto rounded-box border border-base-content/5 bg-base-100">
  <table class="table table-zebra">
    <thead>
      <tr>
        <th><%= sort_link('superadmin_identity_verification_requests_path', I18n.t('activerecord.attributes.identity_verification_request.id'), 'id') %></th>
        <th><%= I18n.t('activerecord.attributes.identity_verification_request.first_name') %></th>
        <th><%= I18n.t('activerecord.attributes.identity_verification_request.last_name') %></th>
        <th><%= I18n.t('activerecord.attributes.identity_verification_request.run') %></th>
        <th><%= I18n.t('activerecord.attributes.identity_verification_request.phone') %></th>
        <th><%= sort_link('superadmin_identity_verification_requests_path', I18n.t('activerecord.attributes.identity_verification_request.status'), 'status') %></th>
        <th><%= sort_link('superadmin_identity_verification_requests_path', I18n.t('activerecord.attributes.identity_verification_request.created_at'), 'created_at') %></th>
        <th class="w-46"><%= I18n.t('shared.table.actions') %></th>
      </tr>
    </thead>
    <tbody>
    <% if @identity_verification_requests.empty? %>
      <tr>
        <td colspan="8" class="text-center py-8 text-base-content/40">
          No hay solicitudes de verificación de identidad.
        </td>
      </tr>
    <% else %>
      <% @identity_verification_requests.each do |identity_verification_request| %>
        <%= render partial: "identity_verification_request_row", locals: { identity_verification_request: identity_verification_request } %>
      <% end %>
    <% end %>
    </tbody>
  </table>
</div>

<div class="my-4"><%== @pagy.series_nav() %></div>
```

- [ ] **Step 4: residence_verification_requests/_table.html.erb**

```erb
<div class="my-4"><%== @pagy.series_nav() %></div>

<div class="overflow-x-auto rounded-box border border-base-content/5 bg-base-100">
  <table class="table table-zebra">
    <thead>
      <tr>
        <th><%= sort_link('superadmin_residence_verification_requests_path', I18n.t('activerecord.attributes.residence_verification_request.id'), 'id') %></th>
        <th><%= I18n.t('activerecord.attributes.residence_verification_request.user') %></th>
        <th><%= I18n.t('activerecord.attributes.residence_verification_request.neighborhood_delegation') %></th>
        <th><%= I18n.t('activerecord.attributes.residence_verification_request.commune') %></th>
        <th><%= sort_link('superadmin_residence_verification_requests_path', I18n.t('activerecord.attributes.residence_verification_request.status'), 'status') %></th>
        <th><%= sort_link('superadmin_residence_verification_requests_path', I18n.t('activerecord.attributes.residence_verification_request.created_at'), 'created_at') %></th>
        <th class="w-46"><%= I18n.t('shared.table.actions') %></th>
      </tr>
    </thead>
    <tbody>
    <% if @residence_verification_requests.empty? %>
      <tr>
        <td colspan="7" class="text-center py-8 text-base-content/40">
          No hay solicitudes de verificación de residencia.
        </td>
      </tr>
    <% else %>
      <% @residence_verification_requests.each do |residence_verification_request| %>
        <%= render partial: "residence_verification_request_row", locals: { residence_verification_request: residence_verification_request } %>
      <% end %>
    <% end %>
    </tbody>
  </table>
</div>

<div class="my-4"><%== @pagy.series_nav() %></div>
```

- [ ] **Step 5: regions/_table.html.erb**

```erb
<div class="my-4"><%== @pagy.series_nav() %></div>

<div class="overflow-x-auto rounded-box border border-base-content/5 bg-base-100">
  <table class="table table-zebra">
    <thead>
      <tr>
        <th><%= sort_link('superadmin_regions_path', I18n.t('activerecord.attributes.region.name'), 'name') %></th>
        <th><%= sort_link('superadmin_regions_path', I18n.t('activerecord.attributes.region.country'), 'country_name') %></th>
        <th class="w-46"><%= I18n.t('shared.table.actions') %></th>
      </tr>
    </thead>
    <tbody>
    <% if @regions.empty? %>
      <tr>
        <td colspan="3" class="text-center py-8 text-base-content/40">
          No hay regiones registradas.
        </td>
      </tr>
    <% else %>
      <% @regions.each do |region| %>
        <%= render partial: "region_row", locals: { region: region } %>
      <% end %>
    <% end %>
    </tbody>
  </table>
</div>

<div class="my-4"><%== @pagy.series_nav() %></div>
```

- [ ] **Step 6: communes/_table.html.erb**

```erb
<div class="my-4"><%== @pagy.series_nav() %></div>

<div class="overflow-x-auto rounded-box border border-base-content/5 bg-base-100">
  <table class="table table-zebra">
    <thead>
      <tr>
        <th><%= sort_link('superadmin_communes_path', I18n.t('activerecord.attributes.commune.name'), 'name') %></th>
        <th><%= sort_link('superadmin_communes_path', I18n.t('activerecord.attributes.commune.region'), 'region_name') %></th>
        <th class="w-46"><%= I18n.t('shared.table.actions') %></th>
      </tr>
    </thead>
    <tbody>
    <% if @communes.empty? %>
      <tr>
        <td colspan="3" class="text-center py-8 text-base-content/40">
          No hay comunas registradas.
        </td>
      </tr>
    <% else %>
      <% @communes.each do |commune| %>
        <%= render partial: "commune_row", locals: { commune: commune } %>
      <% end %>
    <% end %>
    </tbody>
  </table>
</div>

<div class="my-4"><%== @pagy.series_nav() %></div>
```

- [ ] **Step 7: countries/_table.html.erb**

```erb
<div class="my-4"><%== @pagy.series_nav() %></div>

<div class="overflow-x-auto rounded-box border border-base-content/5 bg-base-100">
  <table class="table table-zebra">
    <thead>
      <tr>
        <th><%= sort_link('superadmin_countries_path', I18n.t('activerecord.attributes.country.name'), 'name') %></th>
        <th class="w-46"><%= I18n.t('shared.table.actions') %></th>
      </tr>
    </thead>
    <tbody>
    <% if @countries.empty? %>
      <tr>
        <td colspan="2" class="text-center py-8 text-base-content/40">
          No hay países registrados.
        </td>
      </tr>
    <% else %>
      <% @countries.each do |country| %>
        <%= render partial: "country_row", locals: { country: country } %>
      <% end %>
    <% end %>
    </tbody>
  </table>
</div>

<div class="my-4"><%== @pagy.series_nav() %></div>
```

- [ ] **Step 8: categories/_table.html.erb**

```erb
<div class="my-4"><%== @pagy.series_nav() %></div>

<div class="overflow-x-auto rounded-box border border-base-content/5 bg-base-100">
  <table class="table table-zebra">
    <thead>
      <tr>
        <th><%= sort_link('superadmin_categories_path', I18n.t('activerecord.attributes.category.name'), 'name') %></th>
        <th class="w-46"><%= I18n.t('shared.table.actions') %></th>
      </tr>
    </thead>
    <tbody>
    <% if @categories.empty? %>
      <tr>
        <td colspan="2" class="text-center py-8 text-base-content/40">
          No hay categorías registradas.
        </td>
      </tr>
    <% else %>
      <% @categories.each do |category| %>
        <%= render partial: "category_row", locals: { category: category } %>
      <% end %>
    <% end %>
    </tbody>
  </table>
</div>

<div class="my-4"><%== @pagy.series_nav() %></div>
```

- [ ] **Step 9: tags/_table.html.erb**

```erb
<div class="my-4"><%== @pagy.series_nav() %></div>

<div class="overflow-x-auto rounded-box border border-base-content/5 bg-base-100">
  <table class="table table-zebra">
    <thead>
      <tr>
        <th><%= sort_link('superadmin_tags_path', I18n.t('activerecord.attributes.tag.name'), 'name') %></th>
        <th class="w-46"><%= I18n.t('shared.table.actions') %></th>
      </tr>
    </thead>
    <tbody>
    <% if @tags.empty? %>
      <tr>
        <td colspan="2" class="text-center py-8 text-base-content/40">
          No hay etiquetas registradas.
        </td>
      </tr>
    <% else %>
      <% @tags.each do |tag| %>
        <%= render partial: "tag_row", locals: { tag: tag } %>
      <% end %>
    <% end %>
    </tbody>
  </table>
</div>

<div class="my-4"><%== @pagy.series_nav() %></div>
```

- [ ] **Step 10: Commit**

```bash
git add app/views/superadmin/neighborhood_associations/_table.html.erb \
        app/views/superadmin/onboarding_requests/_table.html.erb \
        app/views/superadmin/identity_verification_requests/_table.html.erb \
        app/views/superadmin/residence_verification_requests/_table.html.erb \
        app/views/superadmin/regions/_table.html.erb \
        app/views/superadmin/communes/_table.html.erb \
        app/views/superadmin/countries/_table.html.erb \
        app/views/superadmin/categories/_table.html.erb \
        app/views/superadmin/tags/_table.html.erb
git commit -m "ui: tablas superadmin con table-zebra y empty states"
```

---

## Task 5: Row Actions — btn-error + aria-labels

En todos los archivos `_*_row.html.erb`, cambiar `btn-warning` → `btn-error` en el botón de eliminar y añadir `aria-label`.

**Files:**
- Modify: todos los `app/views/superadmin/**/_*_row.html.erb`

- [ ] **Step 1: neighborhood_associations/_neighborhood_association_row.html.erb**

```erb
<tr class="hover:bg-base-200/50">
  <td><%= neighborhood_association.name %></td>
  <td>
    <div class="tooltip" data-tip="Administrar como Junta">
      <%= button_to icon('users'), impersonate_superadmin_neighborhood_association_path(neighborhood_association), method: :post, class: "btn btn-sm btn-soft btn-primary", aria: { label: "Administrar #{neighborhood_association.name}" } %>
    </div>
    <div class="tooltip" data-tip="<%= I18n.t('actions.show') %>">
      <%= link_to icon('show'), [:superadmin, neighborhood_association], class: "btn btn-sm btn-soft btn-info", aria: { label: "#{I18n.t('actions.show')} #{neighborhood_association.name}" } %>
    </div>
    <div class="tooltip" data-tip="<%= I18n.t('actions.edit') %>">
      <%= link_to icon('edit'), edit_superadmin_neighborhood_association_path(neighborhood_association), class: "btn btn-sm btn-soft btn-success", aria: { label: "#{I18n.t('actions.edit')} #{neighborhood_association.name}" } %>
    </div>
    <div class="tooltip" data-tip="<%= I18n.t('actions.delete') %>">
      <%= link_to icon('delete'), delete_superadmin_neighborhood_association_path(neighborhood_association), class: "btn btn-sm btn-soft btn-error", aria: { label: "#{I18n.t('actions.delete')} #{neighborhood_association.name}" } %>
    </div>
  </td>
</tr>
```

- [ ] **Step 2: onboarding_requests/_onboarding_request_row.html.erb**

```erb
<tr class="hover:bg-base-200/50">
  <td><%= onboarding_request.id %></td>
  <td><%= onboarding_request.user&.email %></td>
  <td><%= onboarding_request.neighborhood_association&.name %></td>
  <td><%= status_badge(onboarding_request.status) %></td>
  <td><%= l(onboarding_request.created_at, format: :short) if onboarding_request.created_at %></td>
  <td>
    <div class="tooltip" data-tip="<%= I18n.t('actions.show') %>">
      <%= link_to icon('show'), [:superadmin, onboarding_request], class: "btn btn-sm btn-soft btn-info", aria: { label: "#{I18n.t('actions.show')} solicitud ##{onboarding_request.id}" } %>
    </div>
    <div class="tooltip" data-tip="<%= I18n.t('actions.edit') %>">
      <%= link_to icon('edit'), edit_superadmin_onboarding_request_path(onboarding_request), class: "btn btn-sm btn-soft btn-success", aria: { label: "#{I18n.t('actions.edit')} solicitud ##{onboarding_request.id}" } %>
    </div>
    <div class="tooltip" data-tip="<%= I18n.t('actions.delete') %>">
      <%= link_to icon('delete'), delete_superadmin_onboarding_request_path(onboarding_request), class: "btn btn-sm btn-soft btn-error", aria: { label: "#{I18n.t('actions.delete')} solicitud ##{onboarding_request.id}" } %>
    </div>
  </td>
</tr>
```

- [ ] **Step 3: identity_verification_requests/_identity_verification_request_row.html.erb**

```erb
<tr class="hover:bg-base-200/50">
  <td><%= identity_verification_request.id %></td>
  <td><%= identity_verification_request.first_name %></td>
  <td><%= identity_verification_request.last_name %></td>
  <td><%= identity_verification_request.run %></td>
  <td><%= identity_verification_request.phone %></td>
  <td><%= status_badge(identity_verification_request.status) %></td>
  <td><%= l(identity_verification_request.created_at, format: :short) if identity_verification_request.created_at %></td>
  <td>
    <div class="tooltip" data-tip="<%= I18n.t('actions.show') %>">
      <%= link_to icon('show'), [:superadmin, identity_verification_request], class: "btn btn-sm btn-soft btn-info", aria: { label: "#{I18n.t('actions.show')} solicitud ##{identity_verification_request.id}" } %>
    </div>
    <div class="tooltip" data-tip="<%= I18n.t('actions.edit') %>">
      <%= link_to icon('edit'), edit_superadmin_identity_verification_request_path(identity_verification_request), class: "btn btn-sm btn-soft btn-success", aria: { label: "#{I18n.t('actions.edit')} solicitud ##{identity_verification_request.id}" } %>
    </div>
    <div class="tooltip" data-tip="<%= I18n.t('actions.delete') %>">
      <%= link_to icon('delete'), delete_superadmin_identity_verification_request_path(identity_verification_request), class: "btn btn-sm btn-soft btn-error", aria: { label: "#{I18n.t('actions.delete')} solicitud ##{identity_verification_request.id}" } %>
    </div>
  </td>
</tr>
```

- [ ] **Step 4: residence_verification_requests/_residence_verification_request_row.html.erb**

```erb
<tr class="hover:bg-base-200/50">
  <td><%= residence_verification_request.id %></td>
  <td><%= residence_verification_request.user&.email %></td>
  <td><%= residence_verification_request.neighborhood_delegation&.name || residence_verification_request.street_name %></td>
  <td><%= residence_verification_request.commune&.name %></td>
  <td><%= status_badge(residence_verification_request.status) %></td>
  <td><%= l(residence_verification_request.created_at, format: :short) if residence_verification_request.created_at %></td>
  <td>
    <div class="tooltip" data-tip="<%= I18n.t('actions.show') %>">
      <%= link_to icon('show'), [:superadmin, residence_verification_request], class: "btn btn-sm btn-soft btn-info", aria: { label: "#{I18n.t('actions.show')} solicitud ##{residence_verification_request.id}" } %>
    </div>
    <div class="tooltip" data-tip="<%= I18n.t('actions.edit') %>">
      <%= link_to icon('edit'), edit_superadmin_residence_verification_request_path(residence_verification_request), class: "btn btn-sm btn-soft btn-success", aria: { label: "#{I18n.t('actions.edit')} solicitud ##{residence_verification_request.id}" } %>
    </div>
    <div class="tooltip" data-tip="<%= I18n.t('actions.delete') %>">
      <%= link_to icon('delete'), delete_superadmin_residence_verification_request_path(residence_verification_request), class: "btn btn-sm btn-soft btn-error", aria: { label: "#{I18n.t('actions.delete')} solicitud ##{residence_verification_request.id}" } %>
    </div>
  </td>
</tr>
```

- [ ] **Step 5: regions/_region_row.html.erb**

```erb
<tr class="hover:bg-base-200/50">
  <td><%= region.name %></td>
  <td><%= region.country.name %></td>
  <td>
    <div class="tooltip" data-tip="<%= I18n.t('actions.show') %>">
      <%= link_to icon('show'), [:superadmin, region], class: "btn btn-sm btn-soft btn-info", aria: { label: "#{I18n.t('actions.show')} #{region.name}" } %>
    </div>
    <div class="tooltip" data-tip="<%= I18n.t('actions.edit') %>">
      <%= link_to icon('edit'), edit_superadmin_region_path(region), class: "btn btn-sm btn-soft btn-success", aria: { label: "#{I18n.t('actions.edit')} #{region.name}" } %>
    </div>
    <div class="tooltip" data-tip="<%= I18n.t('actions.delete') %>">
      <%= link_to icon('delete'), delete_superadmin_region_path(region), class: "btn btn-sm btn-soft btn-error", aria: { label: "#{I18n.t('actions.delete')} #{region.name}" } %>
    </div>
  </td>
</tr>
```

- [ ] **Step 6: communes/_commune_row.html.erb**

```erb
<tr class="hover:bg-base-200/50">
  <td><%= commune.name %></td>
  <td><%= commune.region.name %></td>
  <td>
    <div class="tooltip" data-tip="<%= I18n.t('actions.show') %>">
      <%= link_to icon('show'), [:superadmin, commune], class: "btn btn-sm btn-soft btn-info", aria: { label: "#{I18n.t('actions.show')} #{commune.name}" } %>
    </div>
    <div class="tooltip" data-tip="<%= I18n.t('actions.edit') %>">
      <%= link_to icon('edit'), edit_superadmin_commune_path(commune), class: "btn btn-sm btn-soft btn-success", aria: { label: "#{I18n.t('actions.edit')} #{commune.name}" } %>
    </div>
    <div class="tooltip" data-tip="<%= I18n.t('actions.delete') %>">
      <%= link_to icon('delete'), delete_superadmin_commune_path(commune), class: "btn btn-sm btn-soft btn-error", aria: { label: "#{I18n.t('actions.delete')} #{commune.name}" } %>
    </div>
  </td>
</tr>
```

- [ ] **Step 7: countries/_country_row.html.erb**

```erb
<tr class="hover:bg-base-200/50">
  <td><%= country.name %></td>
  <td>
    <div class="tooltip" data-tip="<%= I18n.t('actions.show') %>">
      <%= link_to icon('show'), [:superadmin, country], class: "btn btn-sm btn-soft btn-info", aria: { label: "#{I18n.t('actions.show')} #{country.name}" } %>
    </div>
    <div class="tooltip" data-tip="<%= I18n.t('actions.edit') %>">
      <%= link_to icon('edit'), edit_superadmin_country_path(country), class: "btn btn-sm btn-soft btn-success", aria: { label: "#{I18n.t('actions.edit')} #{country.name}" } %>
    </div>
    <div class="tooltip" data-tip="<%= I18n.t('actions.delete') %>">
      <%= link_to icon('delete'), delete_superadmin_country_path(country), class: "btn btn-sm btn-soft btn-error", aria: { label: "#{I18n.t('actions.delete')} #{country.name}" } %>
    </div>
  </td>
</tr>
```

- [ ] **Step 8: categories/_category_row.html.erb**

```erb
<tr class="hover:bg-base-200/50">
  <td><%= category.name %></td>
  <td>
    <div class="tooltip" data-tip="<%= I18n.t('actions.show') %>">
      <%= link_to icon('show'), [:superadmin, category], class: "btn btn-sm btn-soft btn-info", aria: { label: "#{I18n.t('actions.show')} #{category.name}" } %>
    </div>
    <div class="tooltip" data-tip="<%= I18n.t('actions.edit') %>">
      <%= link_to icon('edit'), edit_superadmin_category_path(category), class: "btn btn-sm btn-soft btn-success", aria: { label: "#{I18n.t('actions.edit')} #{category.name}" } %>
    </div>
    <div class="tooltip" data-tip="<%= I18n.t('actions.delete') %>">
      <%= link_to icon('delete'), delete_superadmin_category_path(category), class: "btn btn-sm btn-soft btn-error", aria: { label: "#{I18n.t('actions.delete')} #{category.name}" } %>
    </div>
  </td>
</tr>
```

- [ ] **Step 9: tags/_tag_row.html.erb**

```erb
<tr class="hover:bg-base-200/50">
  <td><%= tag.name %></td>
  <td>
    <div class="tooltip" data-tip="<%= I18n.t('actions.show') %>">
      <%= link_to icon('show'), [:superadmin, tag], class: "btn btn-sm btn-soft btn-info", aria: { label: "#{I18n.t('actions.show')} #{tag.name}" } %>
    </div>
    <div class="tooltip" data-tip="<%= I18n.t('actions.edit') %>">
      <%= link_to icon('edit'), edit_superadmin_tag_path(tag), class: "btn btn-sm btn-soft btn-success", aria: { label: "#{I18n.t('actions.edit')} #{tag.name}" } %>
    </div>
    <div class="tooltip" data-tip="<%= I18n.t('actions.delete') %>">
      <%= link_to icon('delete'), delete_superadmin_tag_path(tag), class: "btn btn-sm btn-soft btn-error", aria: { label: "#{I18n.t('actions.delete')} #{tag.name}" } %>
    </div>
  </td>
</tr>
```

- [ ] **Step 10: Commit**

```bash
git add app/views/superadmin/neighborhood_associations/_neighborhood_association_row.html.erb \
        app/views/superadmin/onboarding_requests/_onboarding_request_row.html.erb \
        app/views/superadmin/identity_verification_requests/_identity_verification_request_row.html.erb \
        app/views/superadmin/residence_verification_requests/_residence_verification_request_row.html.erb \
        app/views/superadmin/regions/_region_row.html.erb \
        app/views/superadmin/communes/_commune_row.html.erb \
        app/views/superadmin/countries/_country_row.html.erb \
        app/views/superadmin/categories/_category_row.html.erb \
        app/views/superadmin/tags/_tag_row.html.erb
git commit -m "ui: botones de acción con btn-error y aria-labels en todas las tablas superadmin"
```

---

## Task 6: Botones _buttons.html.erb — btn-error en link de eliminar

El link de navegación que va a la página de confirmación de eliminación usa `btn-warning`. Cambiarlo a `btn-error` en todas las secciones.

**Files:**
- Modify: todos los `app/views/superadmin/**/_buttons.html.erb`

El cambio en cada archivo es idéntico: en la línea que tiene `%w[ show edit update ].include? action_name` cambiar `btn-warning` → `btn-error`:

- [ ] **Step 1: neighborhood_associations/_buttons.html.erb**

Cambiar la línea:
```erb
<%= link_to raw(icon('delete') + I18n.t('actions.delete')), delete_superadmin_neighborhood_association_path(@neighborhood_association), class: "btn btn-soft btn-warning" %>
```
Por:
```erb
<%= link_to raw(icon('delete') + I18n.t('actions.delete')), delete_superadmin_neighborhood_association_path(@neighborhood_association), class: "btn btn-soft btn-error" %>
```

- [ ] **Step 2: onboarding_requests/_buttons.html.erb**

Cambiar `btn-warning` → `btn-error` en el link_to de delete.

- [ ] **Step 3: identity_verification_requests/_buttons.html.erb**

Cambiar `btn-warning` → `btn-error` en el link_to de delete.

- [ ] **Step 4: residence_verification_requests/_buttons.html.erb**

Cambiar `btn-warning` → `btn-error` en el link_to de delete.

- [ ] **Step 5: regions/_buttons.html.erb**

Cambiar `btn-warning` → `btn-error` en el link_to de delete.

- [ ] **Step 6: communes/_buttons.html.erb**

Cambiar `btn-warning` → `btn-error` en el link_to de delete.

- [ ] **Step 7: countries/_buttons.html.erb**

Cambiar `btn-warning` → `btn-error` en el link_to de delete.

- [ ] **Step 8: categories/_buttons.html.erb**

Cambiar `btn-warning` → `btn-error` en el link_to de delete.

- [ ] **Step 9: tags/_buttons.html.erb**

Cambiar `btn-warning` → `btn-error` en el link_to de delete.

- [ ] **Step 10: Commit**

```bash
git add app/views/superadmin/neighborhood_associations/_buttons.html.erb \
        app/views/superadmin/onboarding_requests/_buttons.html.erb \
        app/views/superadmin/identity_verification_requests/_buttons.html.erb \
        app/views/superadmin/residence_verification_requests/_buttons.html.erb \
        app/views/superadmin/regions/_buttons.html.erb \
        app/views/superadmin/communes/_buttons.html.erb \
        app/views/superadmin/countries/_buttons.html.erb \
        app/views/superadmin/categories/_buttons.html.erb \
        app/views/superadmin/tags/_buttons.html.erb
git commit -m "ui: botones de eliminar con btn-error en todas las secciones superadmin"
```

---

## Task 7: Verificación Final

- [ ] **Step 1: Correr los tests**

```bash
bin/rails test
```
Esperado: todos los tests pasan (0 failures).

- [ ] **Step 2: Verificar que el servidor inicia sin errores**

```bash
bin/rails runner "Rails.application.eager_load!; puts 'OK'"
```
Esperado: `OK`
