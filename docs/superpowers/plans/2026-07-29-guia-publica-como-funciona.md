# Guía pública "Cómo funciona" — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publicar en `/como-funciona` un deck de diapositivas, accesible sin login, que explique Yuntapp en lenguaje muy simple y en dos niveles (flujo simple obligatorio + "para saber más" opcional).

**Architecture:** Ruta pública Rails (`GuideController#index`, `skip_before_action :authenticate_user!`, patrón de `HomeController`) con un layout autónomo minimalista (`guide.html.erb`, estilo `verification.html.erb`). La vista `index.html.erb` renderiza todas las diapositivas en el DOM; un Stimulus controller (`deck_controller.js`) muestra una a la vez y maneja navegación (botones, clic, teclado, swipe). El Acto 2 es opcional: la diapositiva de bifurcación salta al cierre con `deck#goto`.

**Tech Stack:** Rails 8.1, Hotwire/Stimulus (Importmap, auto-carga vía `eagerLoadControllersFrom`), Tailwind (`tailwindcss-rails`), Minitest.

**Spec:** `docs/superpowers/specs/2026-07-29-guia-publica-como-funciona-design.md`

---

## Estructura de archivos

- Crear: `app/controllers/guide_controller.rb` — controlador público, una acción `index`.
- Crear: `app/views/layouts/guide.html.erb` — layout autónomo (sin navbar de la app), carga Tailwind + importmap.
- Crear: `app/views/guide/index.html.erb` — contenedor del deck, barra de progreso, controles y las 19 diapositivas.
- Crear: `app/views/guide/slides/_slide.html.erb` — parcial genérico de diapositiva estándar (ícono, eyebrow, título, párrafos).
- Crear: `app/javascript/controllers/deck_controller.js` — Stimulus controller de navegación.
- Crear: `test/controllers/guide_controller_test.rb` — request tests (acceso sin login + hitos del deck).
- Modificar: `config/routes.rb` — agregar `get "como-funciona", to: "guide#index", as: :guide`.
- Modificar: `app/views/home/index.html.erb` — enlace "¿Cómo funciona?" hacia `guide_path`.

**Nota sobre i18n:** el texto en español va inline en las vistas (decisión del spec): es prosa larga solo-español y meterla en `es.yml` la haría ilegible.

**Nota sobre tests de JS:** el proyecto no tiene harness de tests de JavaScript (no hay system tests). El comportamiento del `deck_controller` se valida con una checklist manual al final (Task 6). Los request tests cubren que el markup y los data-attributes que el controller necesita estén presentes.

---

## Task 1: Ruta, controlador y layout públicos (200 sin login)

**Files:**
- Test: `test/controllers/guide_controller_test.rb`
- Modify: `config/routes.rb`
- Create: `app/controllers/guide_controller.rb`
- Create: `app/views/layouts/guide.html.erb`
- Create: `app/views/guide/index.html.erb`

- [ ] **Step 1: Escribir el test que falla**

Crear `test/controllers/guide_controller_test.rb`:

```ruby
require "test_helper"

class GuideControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rack::Attack.cache.store.clear if defined?(Rack::Attack)
  end

  test "es accesible sin autenticación" do
    get guide_url
    assert_response :success
  end
end
```

- [ ] **Step 2: Correr el test y verificar que falla**

Run: `bin/rails test test/controllers/guide_controller_test.rb`
Expected: FAIL — `NameError`/`NoMethodError: undefined ... guide_url` (la ruta aún no existe).

- [ ] **Step 3: Agregar la ruta pública**

En `config/routes.rb`, justo debajo del bloque de verificación pública (`get "verify/:identifier", ...`), agregar:

```ruby
  # Guía pública "cómo funciona" (deck explicativo). Sin autenticación.
  get "como-funciona", to: "guide#index", as: :guide
```

- [ ] **Step 4: Crear el controlador**

Crear `app/controllers/guide_controller.rb`:

```ruby
# Guía pública que explica Yuntapp en un deck de diapositivas. Sin autenticación:
# cualquier persona puede entenderla, igual que la verificación de certificados.
class GuideController < ApplicationController
  skip_before_action :authenticate_user!
  layout "guide"

  def index
  end
end
```

- [ ] **Step 5: Crear el layout autónomo**

Crear `app/views/layouts/guide.html.erb`:

```erb
<!DOCTYPE html>
<html data-theme="light">
  <head>
    <title><%= content_for(:title) || "¿Cómo funciona Yuntapp?" %></title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <meta name="description" content="Guía simple para entender cómo funciona Yuntapp, paso a paso.">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>
    <%= render "shared/google_fonts" %>
    <link rel="icon" href="/icon.png" type="image/png">
    <link rel="icon" href="/icon.svg" type="image/svg+xml">
    <%= stylesheet_link_tag :app, "data-turbo-track": "reload" %>
    <%= javascript_importmap_tags %>
  </head>

  <body class="bg-amber-50 min-h-screen flex flex-col text-stone-800">
    <header class="py-5 px-6">
      <div class="max-w-2xl mx-auto">
        <%= link_to root_path, class: "inline-block", aria: {label: "Ir al inicio"} do %>
          <%= render "shared/logo", variant: :horizontal, size: "lg" %>
        <% end %>
      </div>
    </header>

    <main id="main-content" tabindex="-1" class="flex-1 px-4 py-6 md:py-10">
      <%= yield %>
    </main>

    <footer class="py-6 px-6 text-center text-sm text-stone-500">
      Yuntapp · Plataforma vecinal
    </footer>
  </body>
</html>
```

- [ ] **Step 6: Crear la vista mínima (placeholder temporal)**

Crear `app/views/guide/index.html.erb` con un contenido mínimo (se reemplaza en Task 3):

```erb
<% content_for :title, "¿Cómo funciona Yuntapp?" %>
<div class="max-w-2xl mx-auto">
  <h2 class="text-2xl font-bold text-center">¿Cómo funciona Yuntapp?</h2>
</div>
```

- [ ] **Step 7: Correr el test y verificar que pasa**

Run: `bin/rails test test/controllers/guide_controller_test.rb`
Expected: PASS (1 runs, 1 assertions).

- [ ] **Step 8: Verificar que `shared/logo` acepta `size: "lg"`**

Run: `grep -rn "def \|size" app/views/shared/_logo.html.erb`
Expected: el parcial existe y usa `local_assigns`/`size` (ya se usa así en `verification.html.erb`). Si el parcial NO existe o falla al render, reemplazar la línea del logo en el layout por: `<span class="text-2xl font-bold text-amber-700">Yuntapp</span>`.

- [ ] **Step 9: Commit**

```bash
git add config/routes.rb app/controllers/guide_controller.rb app/views/layouts/guide.html.erb app/views/guide/index.html.erb test/controllers/guide_controller_test.rb
git commit -m "feat(guide): ruta pública /como-funciona con layout autónomo"
```

---

## Task 2: Stimulus deck_controller (navegación)

**Files:**
- Create: `app/javascript/controllers/deck_controller.js`

No hay test automatizado de JS en el proyecto; se verifica manualmente en Task 6. Esta task solo crea el controller (auto-registrado por `eagerLoadControllersFrom` en `app/javascript/controllers/index.js`, no requiere editar el manifest).

- [ ] **Step 1: Crear el controller**

Crear `app/javascript/controllers/deck_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

// Deck de diapositivas para la guía pública /como-funciona.
// Muestra una diapositiva a la vez y permite avanzar con botones, clic en la
// diapositiva, flechas del teclado y swipe. El Acto 2 es opcional: la
// diapositiva de bifurcación usa #goto para saltar directo al cierre.
export default class extends Controller {
  static targets = ["slide", "prev", "next", "progress"]

  connect() {
    this.index = 0
    this.touchStartX = null
    this.onKeydown = this.handleKeydown.bind(this)
    window.addEventListener("keydown", this.onKeydown)
    this.show()
  }

  disconnect() {
    window.removeEventListener("keydown", this.onKeydown)
  }

  next() {
    if (this.index < this.lastIndex) {
      this.index++
      this.show()
    }
  }

  prev() {
    if (this.index > 0) {
      this.index--
      this.show()
    }
  }

  // Salto directo (bifurcación → cierre). Usa data-deck-index-param.
  goto(event) {
    const target = Number(event.params.index)
    if (!Number.isNaN(target) && target >= 0 && target <= this.lastIndex) {
      this.index = target
      this.show()
    }
  }

  reset() {
    this.index = 0
    this.show()
  }

  // Clic en la diapositiva para avanzar, salvo que el clic sea sobre un botón/enlace.
  advance(event) {
    if (event.target.closest("button, a")) return
    this.next()
  }

  touchStart(event) {
    this.touchStartX = event.changedTouches[0].screenX
  }

  touchEnd(event) {
    if (this.touchStartX === null) return
    const delta = event.changedTouches[0].screenX - this.touchStartX
    if (Math.abs(delta) > 50) {
      if (delta < 0) {
        this.next()
      } else {
        this.prev()
      }
    }
    this.touchStartX = null
  }

  handleKeydown(event) {
    if (event.key === "ArrowRight") this.next()
    if (event.key === "ArrowLeft") this.prev()
  }

  show() {
    this.slideTargets.forEach((slide, i) => {
      const active = i === this.index
      slide.classList.toggle("hidden", !active)
      slide.setAttribute("aria-hidden", active ? "false" : "true")
    })

    if (this.hasProgressTarget) {
      const pct = ((this.index + 1) / this.slideTargets.length) * 100
      this.progressTarget.style.width = `${pct}%`
    }

    if (this.hasPrevTarget) this.prevTarget.disabled = this.index === 0
    if (this.hasNextTarget) this.nextTarget.disabled = this.index === this.lastIndex

    const heading = this.slideTargets[this.index].querySelector("h2, h1")
    if (heading) heading.focus()
    window.scrollTo({ top: 0, behavior: "instant" })
  }

  get lastIndex() {
    return this.slideTargets.length - 1
  }
}
```

- [ ] **Step 2: Verificar que el controller es sintácticamente válido**

Run: `node --check app/javascript/controllers/deck_controller.js`
Expected: sin salida (exit 0). Si `node` no está disponible, omitir; se validará al cargar la página en Task 6.

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/deck_controller.js
git commit -m "feat(guide): stimulus deck_controller para navegar el deck"
```

---

## Task 3: Parcial de diapositiva + Acto 1 + bifurcación

**Files:**
- Create: `app/views/guide/slides/_slide.html.erb`
- Modify: `app/views/guide/index.html.erb` (reemplaza el placeholder de Task 1)
- Test: `test/controllers/guide_controller_test.rb`

- [ ] **Step 1: Escribir los tests que fallan**

Agregar a `test/controllers/guide_controller_test.rb` (dentro de la clase):

```ruby
  test "renderiza la portada y monta el deck" do
    get guide_url
    assert_response :success
    assert_select "[data-controller='deck']"
    assert_select "h2", text: "¿Cómo funciona Yuntapp?"
  end

  test "incluye los pasos del flujo simple y la bifurcación opcional" do
    get guide_url
    assert_select "h2", text: "Se hace socia de su junta"
    assert_select "h2", text: "Paga en línea"
    # La bifurcación del Acto 2 salta al cierre con un índice explícito.
    assert_select "[data-deck-index-param]"
  end
```

- [ ] **Step 2: Correr los tests y verificar que fallan**

Run: `bin/rails test test/controllers/guide_controller_test.rb`
Expected: FAIL — los nuevos tests no encuentran `data-controller='deck'` ni los `h2` (la vista aún es el placeholder).

- [ ] **Step 3: Crear el parcial de diapositiva estándar**

Crear `app/views/guide/slides/_slide.html.erb`:

```erb
<%# locals: index (Integer), icon (String emoji), eyebrow (String|nil), title (String), body (Array<String>) %>
<section
  class="deck-slide text-center bg-white rounded-3xl shadow-sm border border-amber-100 px-6 py-12 md:py-16 <%= "hidden" unless index.zero? %>"
  data-deck-target="slide"
  data-action="click->deck#advance"
  aria-hidden="<%= index.zero? ? "false" : "true" %>">
  <div class="text-6xl md:text-7xl mb-6" aria-hidden="true"><%= icon %></div>
  <% if eyebrow.present? %>
    <p class="text-sm font-semibold uppercase tracking-wide text-amber-700 mb-2"><%= eyebrow %></p>
  <% end %>
  <h2 tabindex="-1" class="text-2xl md:text-3xl font-bold text-stone-800 mb-4 outline-none"><%= title %></h2>
  <div class="space-y-3 text-lg text-stone-600 max-w-prose mx-auto">
    <% Array(body).each do |paragraph| %>
      <p><%= paragraph %></p>
    <% end %>
  </div>
</section>
```

- [ ] **Step 4: Reescribir la vista index con el deck, Acto 1 y bifurcación**

Reemplazar TODO el contenido de `app/views/guide/index.html.erb` por (el Acto 2 se agrega en Task 4, justo antes del cierre):

```erb
<% content_for :title, "¿Cómo funciona Yuntapp?" %>

<div class="max-w-2xl mx-auto"
     data-controller="deck"
     data-action="touchstart->deck#touchStart touchend->deck#touchEnd">

  <%# Barra de progreso %>
  <div class="h-2 bg-amber-100 rounded-full overflow-hidden mb-8" aria-hidden="true">
    <div class="h-full bg-amber-500 transition-all duration-300 motion-reduce:transition-none"
         style="width: 0%" data-deck-target="progress"></div>
  </div>

  <div aria-live="polite">
    <%# --- Acto 1: la historia de María (obligatorio) --- %>

    <%= render "guide/slides/slide", index: 0, icon: "🏠", eyebrow: nil,
          title: "¿Cómo funciona Yuntapp?",
          body: ["Saca tu certificado de residencia por internet, sin ir a la municipalidad.",
                 "Te lo explicamos paso a paso, con calma."] %>

    <%= render "guide/slides/slide", index: 1, icon: "👋", eyebrow: "La historia de María",
          title: "Ella es María",
          body: ["María vive en su barrio hace años.",
                 "Hoy necesita un certificado de residencia para un trámite. Antes tenía que ir a una oficina; ahora lo hace desde su casa."] %>

    <%= render "guide/slides/slide", index: 2, icon: "📝", eyebrow: "Paso 1",
          title: "Crea su cuenta",
          body: ["Es como abrir un correo: pone su email y una clave.",
                 "Con eso ya puede entrar a Yuntapp."] %>

    <%= render "guide/slides/slide", index: 3, icon: "✅", eyebrow: "Paso 2",
          title: "Se hace socia de su junta",
          body: ["María muestra quién es (su carnet) y dónde vive.",
                 "La junta de vecinos lo revisa una sola vez y la aprueba. Listo: ya es socia."] %>

    <%= render "guide/slides/slide", index: 4, icon: "📄", eyebrow: "Paso 3",
          title: "Pide su certificado",
          body: ["Elige para qué lo necesita (por ejemplo, un trámite en el banco).",
                 "Con un par de clics, queda solicitado."] %>

    <%= render "guide/slides/slide", index: 5, icon: "💳", eyebrow: "Paso 4",
          title: "Paga en línea",
          body: ["Paga desde su celular con MercadoPago.",
                 "El pago va primero: es el último paso antes de recibir el documento."] %>

    <%= render "guide/slides/slide", index: 6, icon: "⚡", eyebrow: "Paso 5",
          title: "Lo recibe al instante",
          body: ["Apenas se confirma el pago, el sistema genera el certificado solo.",
                 "María lo descarga en PDF, sin esperar a nadie."] %>

    <%= render "guide/slides/slide", index: 7, icon: "🔎", eyebrow: "Paso 6",
          title: "Cualquiera puede comprobar que es real",
          body: ["El certificado trae un código QR, un código de letras y un enlace.",
                 "Un banco o un arrendador puede verificar que es auténtico en segundos."] %>

    <%# --- Bifurcación (index 8): el Acto 2 es opcional --- %>
    <section class="deck-slide hidden text-center bg-white rounded-3xl shadow-sm border border-amber-100 px-6 py-12 md:py-16"
             data-deck-target="slide" aria-hidden="true">
      <div class="text-6xl md:text-7xl mb-6" aria-hidden="true">🙌</div>
      <h2 tabindex="-1" class="text-2xl md:text-3xl font-bold text-stone-800 mb-4 outline-none">¡Eso es todo!</h2>
      <div class="space-y-3 text-lg text-stone-600 max-w-prose mx-auto mb-8">
        <p>Así de simple: María solicitó, pagó y recibió su certificado.</p>
        <p>¿Quieres ver cómo funciona por dentro?</p>
      </div>
      <div class="flex flex-col sm:flex-row gap-3 justify-center">
        <button type="button" data-action="click->deck#next"
                class="inline-flex items-center justify-center gap-2 rounded-full px-6 py-3 text-lg font-semibold bg-amber-500 text-white hover:bg-amber-600 transition motion-reduce:transition-none">
          Sí, muéstrame
        </button>
        <button type="button" data-action="click->deck#goto" data-deck-index-param="18"
                class="inline-flex items-center justify-center gap-2 rounded-full px-6 py-3 text-lg font-semibold bg-white text-stone-700 border border-stone-300 hover:bg-stone-50 transition motion-reduce:transition-none">
          Con esto me basta
        </button>
      </div>
    </section>

    <%# ACTO 2 y CIERRE se insertan aquí en Task 4 %>
  </div>

  <%# Controles inferiores %>
  <div class="flex items-center justify-between gap-4 mt-8">
    <button type="button" data-deck-target="prev" data-action="click->deck#prev"
            class="inline-flex items-center gap-2 rounded-full px-5 py-3 font-semibold bg-white text-stone-700 border border-stone-300 hover:bg-stone-50 disabled:opacity-40 disabled:cursor-not-allowed transition motion-reduce:transition-none">
      ← Atrás
    </button>
    <%= link_to "Salir", root_path, class: "text-sm text-stone-500 hover:text-stone-700 underline" %>
    <button type="button" data-deck-target="next" data-action="click->deck#next"
            class="inline-flex items-center gap-2 rounded-full px-5 py-3 font-semibold bg-amber-500 text-white hover:bg-amber-600 disabled:opacity-40 disabled:cursor-not-allowed transition motion-reduce:transition-none">
      Siguiente →
    </button>
  </div>
</div>
```

- [ ] **Step 5: Correr los tests y verificar que pasan**

Run: `bin/rails test test/controllers/guide_controller_test.rb`
Expected: PASS (todos los tests presentes en el archivo hasta ahora). Los tests del Acto 2/cierre se agregan recién en Task 4.

- [ ] **Step 6: Commit**

```bash
git add app/views/guide/slides/_slide.html.erb app/views/guide/index.html.erb test/controllers/guide_controller_test.rb
git commit -m "feat(guide): parcial de diapositiva, Acto 1 y bifurcación opcional"
```

---

## Task 4: Acto 2 (opcional) + cierre

**Files:**
- Modify: `app/views/guide/index.html.erb` (insertar antes del comentario `ACTO 2 y CIERRE se insertan aquí`)
- Test: `test/controllers/guide_controller_test.rb`

Índices: el Acto 2 ocupa los índices 9–17 (nueve conceptos) y el cierre es el índice 18 — que coincide con el `data-deck-index-param="18"` de la bifurcación.

- [ ] **Step 1: Escribir el test que falla**

Agregar a `test/controllers/guide_controller_test.rb`:

```ruby
  test "incluye los conceptos del Acto 2 y el cierre" do
    get guide_url
    assert_select "h2", text: "Una idea clave"
    assert_select "h2", text: "Nada se borra"
    assert_select "h2", text: "Eso es Yuntapp"
  end
```

- [ ] **Step 2: Correr el test y verificar que falla**

Run: `bin/rails test test/controllers/guide_controller_test.rb`
Expected: FAIL — no encuentra los `h2` del Acto 2/cierre (aún no existen).

- [ ] **Step 3: Insertar Acto 2 y cierre**

En `app/views/guide/index.html.erb`, reemplazar la línea:

```erb
    <%# ACTO 2 y CIERRE se insertan aquí en Task 4 %>
```

por:

```erb
    <%# --- Acto 2: cómo funciona por dentro (opcional) --- %>

    <%= render "guide/slides/slide", index: 9, icon: "🧩", eyebrow: "Para saber más",
          title: "Una idea clave",
          body: ["Por dentro, Yuntapp separa tres cosas que en la vida real son distintas:",
                 "quién eres · dónde vives · tu vínculo con la junta.",
                 "Así todo queda ordenado y seguro."] %>

    <%= render "guide/slides/slide", index: 10, icon: "🔑", eyebrow: "Para saber más",
          title: "Tu cuenta",
          body: ["Es tu llave para entrar (tu email y tu clave).",
                 "Si dejas de usarla, queda guardada como inactiva. Nunca se borra."] %>

    <%= render "guide/slides/slide", index: 11, icon: "🪪", eyebrow: "Para saber más",
          title: "Tu identidad",
          body: ["Es como tu carnet dentro del sistema, unido a tu RUN.",
                 "Te identifica siempre, aunque algún día uses otra cuenta."] %>

    <%= render "guide/slides/slide", index: 12, icon: "🤝", eyebrow: "Para saber más",
          title: "Tu membresía",
          body: ["Es tu \"carné de socio\" de una junta.",
                 "Si te cambias o te vas, queda inactiva con todo tu historial. Nunca se borra."] %>

    <%= render "guide/slides/slide", index: 13, icon: "👨‍👩‍👧", eyebrow: "Para saber más",
          title: "Tu casa y tu familia",
          body: ["Una misma dirección puede tener varias familias.",
                 "Y hay personas —como adultos mayores o niños— a quienes otro registra por ellas. Se les llama dependientes."] %>

    <%= render "guide/slides/slide", index: 14, icon: "🏛️", eyebrow: "Para saber más",
          title: "La junta de vecinos",
          body: ["Es quien emite el certificado, con validez oficial.",
                 "Para poder emitir, la junta debe estar constituida legalmente (tener su RUT)."] %>

    <%= render "guide/slides/slide", index: 15, icon: "📜", eyebrow: "Para saber más",
          title: "El certificado por dentro",
          body: ["Pasa por tres momentos: por pagar → pagado → emitido.",
                 "Regla de oro: nunca se emite sin el pago confirmado."] %>

    <%= render "guide/slides/slide", index: 16, icon: "🧑‍💼", eyebrow: "Para saber más",
          title: "Directiva y comunidad",
          body: ["La junta tiene su directiva (presidente, secretario, tesorero...).",
                 "Y los vecinos pueden publicar avisos en un espacio comunitario."] %>

    <%= render "guide/slides/slide", index: 17, icon: "🛡️", eyebrow: "Para saber más",
          title: "Nada se borra",
          body: ["Todo lo importante queda guardado como historial.",
                 "Los datos no se destruyen: solo se activan o desactivan. Así nada se pierde."] %>

    <%# --- Cierre (index 18) --- %>
    <section class="deck-slide hidden text-center bg-white rounded-3xl shadow-sm border border-amber-100 px-6 py-12 md:py-16"
             data-deck-target="slide" aria-hidden="true">
      <div class="text-6xl md:text-7xl mb-6" aria-hidden="true">🎉</div>
      <h2 tabindex="-1" class="text-2xl md:text-3xl font-bold text-stone-800 mb-4 outline-none">Eso es Yuntapp</h2>
      <div class="space-y-3 text-lg text-stone-600 max-w-prose mx-auto mb-8">
        <p>Un trámite que antes era presencial, ahora en tu celular.</p>
        <p>Simple para el vecino, seguro para la junta.</p>
      </div>
      <div class="flex flex-col sm:flex-row gap-3 justify-center">
        <%= link_to "Volver al inicio", root_path,
              class: "inline-flex items-center justify-center gap-2 rounded-full px-6 py-3 text-lg font-semibold bg-amber-500 text-white hover:bg-amber-600 transition motion-reduce:transition-none" %>
        <button type="button" data-action="click->deck#reset"
                class="inline-flex items-center justify-center gap-2 rounded-full px-6 py-3 text-lg font-semibold bg-white text-stone-700 border border-stone-300 hover:bg-stone-50 transition motion-reduce:transition-none">
          Ver de nuevo
        </button>
      </div>
    </section>
```

- [ ] **Step 4: Correr los tests y verificar que pasan**

Run: `bin/rails test test/controllers/guide_controller_test.rb`
Expected: PASS (todos los tests del archivo).

- [ ] **Step 5: Commit**

```bash
git add app/views/guide/index.html.erb test/controllers/guide_controller_test.rb
git commit -m "feat(guide): Acto 2 (cómo funciona por dentro) y cierre"
```

---

## Task 5: Enlace desde el home

**Files:**
- Modify: `app/views/home/index.html.erb`

- [ ] **Step 1: Abrir el home y localizar el hero/CTA**

Run: `grep -n "link_to\|hero\|<h1\|btn" app/views/home/index.html.erb`
Leer la zona del CTA principal para insertar el enlace de forma coherente con las clases existentes.

- [ ] **Step 2: Agregar el enlace a la guía**

Insertar, junto a los CTAs existentes del hero (o al final del contenedor principal si no hay CTAs claros), el siguiente enlace. Ajustar solo las clases de botón a las que ya use el home si difieren:

```erb
<%= link_to "¿Cómo funciona?", guide_path,
      class: "inline-flex items-center gap-2 rounded-full px-6 py-3 font-semibold bg-white text-amber-700 border border-amber-300 hover:bg-amber-50 transition" %>
```

- [ ] **Step 3: Verificar que el home sigue renderizando**

Run: `bin/rails test test/controllers/home_controller_test.rb 2>/dev/null || bin/rails runner "app = ActionDispatch::Integration::Session.new(Rails.application); app.get('/'); puts app.response.status"`
Expected: `200` (o los tests del home en verde si existen).

- [ ] **Step 4: Commit**

```bash
git add app/views/home/index.html.erb
git commit -m "feat(guide): enlace '¿Cómo funciona?' desde el home"
```

---

## Task 6: Verificación final (lint + tests + humo manual)

**Files:** ninguno (solo verificación).

- [ ] **Step 1: Lint Ruby**

Run: `bin/standardrb`
Expected: sin ofensas. Si las hay: `bin/standardrb --fix` y revisar.

- [ ] **Step 2: Lint ERB**

Run: `bundle exec erb_lint --lint-all`
Expected: sin ofensas en las vistas nuevas.

- [ ] **Step 3: Suite completa de tests**

Run: `bin/rails test`
Expected: PASS (sin regresiones).

- [ ] **Step 4: Humo manual del deck (comportamiento JS)**

Con `bin/dev` corriendo, abrir `http://localhost:3000/como-funciona` **sin estar logueado** y verificar:
- Carga la portada y la barra de progreso empieza baja.
- "Siguiente" / "Atrás", flechas ←/→, clic en la diapositiva y swipe en móvil avanzan/retroceden.
- En la bifurcación: "Con esto me basta" salta al cierre; "Sí, muéstrame" entra al Acto 2.
- "Atrás" está deshabilitado en la portada y "Siguiente" en el cierre.
- "Ver de nuevo" vuelve a la portada; "Volver al inicio" va a `/`.

- [ ] **Step 5: Commit final (si Task 4/5 dejaron cambios de lint)**

```bash
git add -A
git commit -m "chore(guide): lint y ajustes finales" || echo "nada que commitear"
```

---

## Self-review (cobertura del spec)

- Ruta pública sin login → Task 1 (test explícito de acceso sin auth). ✔
- Deck de diapositivas → Task 2 (controller) + Task 3 (chrome). ✔
- Dos niveles con Acto 2 opcional → Task 3 (bifurcación con `deck#goto`) + Task 4 (Acto 2 + cierre en índice 18). ✔
- Flujo simple (solicitar/pagar/emitir/verificar) → Task 3 slides 2–8. ✔
- Modelo de dominio (identidad/cuenta/membresía/casa/junta/certificado/directiva/nada-se-borra) → Task 4 slides 9–18. ✔
- Estilo cálido y cercano → paleta ámbar/stone, íconos grandes, frases cortas (Tasks 1,3,4). ✔
- Navegación accesible (teclado, swipe, clic, foco, aria, reduced-motion) → Task 2 + markup en 3/4. ✔
- Texto inline (no i18n) → Tasks 3/4. ✔
- Test de request 200 sin login + hitos → Tasks 1,3,4. ✔
- Enlace desde el home → Task 5. ✔
