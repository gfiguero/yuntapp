# Confirmación de email de MercadoPago para suscripciones — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que el socio confirme el email de su cuenta MercadoPago en un paso previo del flujo de suscripción, se persista, y se use como `payer_email` de la preapproval — evitando el rechazo del cobro cuando su email de MP difiere del de yuntapp.

**Architecture:** Nueva columna `users.mercadopago_email` (distinta del email de login inmutable). El GET `new` de suscripciones pasa de crear la preapproval directo a renderizar un formulario con el email prellenado; un nuevo POST `create` guarda el email y crea la preapproval con él. Solo aplica a suscripciones; el pago único no cambia.

**Tech Stack:** Rails 8.1, SQLite3, Minitest + fixtures.

**Spec:** `docs/superpowers/specs/2026-07-30-mercadopago-email-suscripcion-design.md`

---

## File Structure

- `db/migrate/<ts>_add_mercadopago_email_to_users.rb` — Crear. Columna nueva.
- `app/models/user.rb` — Modificar: validación de formato de `mercadopago_email`.
- `config/routes.rb` — Modificar: agregar `create` a `listing_subscriptions`.
- `app/controllers/panel/listing_subscriptions_controller.rb` — Modificar: `new` renderiza form; nuevo `create`.
- `app/views/panel/listing_subscriptions/new.html.erb` — Crear. Formulario del email.
- `config/locales/es.yml`, `config/locales/en.yml` — Modificar: i18n del form + errores.
- `CLAUDE.md` — Modificar: BR-142.
- `test/models/user_test.rb` — Modificar: validación.
- `test/controllers/panel/listing_subscriptions_controller_test.rb` — Modificar: adaptar test de `new`, agregar tests de `create`.

---

## Task 1: Columna `mercadopago_email` + validación en User

**Files:**
- Create: `db/migrate/<ts>_add_mercadopago_email_to_users.rb`
- Modify: `app/models/user.rb`
- Test: `test/models/user_test.rb`

- [ ] **Step 1: Generar y escribir la migración**

Run: `bin/rails g migration AddMercadopagoEmailToUsers`

Cuerpo:
```ruby
class AddMercadopagoEmailToUsers < ActiveRecord::Migration[8.1]
  def change
    # BR-142: email de la cuenta MercadoPago del socio, usado como payer_email
    # de las suscripciones (preapproval). Distinto del email de login (inmutable, BR-093).
    add_column :users, :mercadopago_email, :string
  end
end
```

- [ ] **Step 2: Aplicar**

Run: `bin/rails db:migrate`
Expected: `db/schema.rb` tiene `t.string "mercadopago_email"` en `users`.

- [ ] **Step 3: Escribir tests de validación (fallan)**

En `test/models/user_test.rb`, agregar dentro de la clase:
```ruby
  test "mercadopago_email accepts a valid email" do
    user = users(:selendis)
    user.mercadopago_email = "pagador@example.com"
    assert user.valid?, user.errors.full_messages.to_sentence
  end

  test "mercadopago_email rejects an invalid format" do
    user = users(:selendis)
    user.mercadopago_email = "no-es-un-email"
    assert_not user.valid?
    assert user.errors[:mercadopago_email].any?
  end

  test "mercadopago_email allows blank" do
    user = users(:selendis)
    user.mercadopago_email = ""
    assert user.valid?
  end
```

- [ ] **Step 4: Correr — deben fallar**

Run: `bin/rails test test/models/user_test.rb -n "/mercadopago_email/"`
Expected: FAIL (el formato inválido pasa porque no hay validación).

- [ ] **Step 5: Implementar la validación en `app/models/user.rb`**

Agregar junto al scope `filter_by_email` (cerca del inicio de la clase, después de los scopes):
```ruby
  # BR-142: email de la cuenta MercadoPago para suscripciones (payer_email).
  validates :mercadopago_email, format: {with: URI::MailTo::EMAIL_REGEXP}, allow_blank: true
```

- [ ] **Step 6: Correr — deben pasar**

Run: `bin/rails test test/models/user_test.rb -n "/mercadopago_email/"`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(BR-142): columna users.mercadopago_email + validación de formato"
```

---

## Task 2: Rutas + controller (new renderiza form, create procesa)

**Files:**
- Modify: `config/routes.rb`, `app/controllers/panel/listing_subscriptions_controller.rb`
- Test: `test/controllers/panel/listing_subscriptions_controller_test.rb`

- [ ] **Step 1: Agregar `create` a las rutas**

En `config/routes.rb`, cambiar:
```ruby
    resources :listing_subscriptions, only: [:new] do
```
por:
```ruby
    resources :listing_subscriptions, only: [:new, :create] do
```
(El bloque `collection do get :success; delete :cancel end` no cambia.)

- [ ] **Step 2: Adaptar el test existente de `new` + escribir tests de `create` (fallan)**

En `test/controllers/panel/listing_subscriptions_controller_test.rb`:

(a) REEMPLAZAR el test `"creates preapproval, snapshots amount and redirects to MP (BR-088)"` (que hoy hace GET new) por su equivalente para el nuevo `new` (que solo renderiza el form):
```ruby
    test "new renders the email confirmation form prefilled" do
      sign_in @member_user
      get new_panel_listing_subscription_url(listing_id: @listing.id)
      assert_response :success
      # prellena con el email de login cuando no hay mercadopago_email
      assert_select "input[name=mercadopago_email][value=?]", @member_user.email
    end

    test "new prefills the saved mercadopago_email when present" do
      @member_user.update!(mercadopago_email: "pagador@mp.cl")
      sign_in @member_user
      get new_panel_listing_subscription_url(listing_id: @listing.id)
      assert_response :success
      assert_select "input[name=mercadopago_email][value=?]", "pagador@mp.cl"
    end
```

(b) AGREGAR tests del nuevo `create`:
```ruby
    test "create saves the email, snapshots amount, creates preapproval and redirects to MP (BR-088/BR-142)" do
      fake = Object.new
      fake.define_singleton_method(:create_listing_subscription) do |_listing, **_kw|
        {"id" => "PRE-CTRL-1", "init_point" => "https://mp.test/subscription/123"}
      end
      sign_in @member_user
      stub_class_method(MercadopagoService, :new, fake) do
        post panel_listing_subscriptions_url(listing_id: @listing.id),
          params: {mercadopago_email: "pagador@mp.cl"}
      end
      assert_redirected_to "https://mp.test/subscription/123"
      assert_equal "pagador@mp.cl", @member_user.reload.mercadopago_email
      @listing.reload
      assert_equal 1200, @listing.amount
      assert_equal "PRE-CTRL-1", @listing.preapproval_id
      assert_equal "pending", @listing.subscription_status
    end

    test "create uses the confirmed email as payer_email" do
      captured = {}
      fake = Object.new
      fake.define_singleton_method(:create_listing_subscription) do |_listing, **kw|
        captured[:payer_email] = kw[:payer_email]
        {"id" => "PRE-X", "init_point" => "https://mp.test/x"}
      end
      sign_in @member_user
      stub_class_method(MercadopagoService, :new, fake) do
        post panel_listing_subscriptions_url(listing_id: @listing.id),
          params: {mercadopago_email: "elegido@mp.cl"}
      end
      assert_equal "elegido@mp.cl", captured[:payer_email]
    end

    test "create with an invalid email redirects back to the form with an alert" do
      sign_in @member_user
      post panel_listing_subscriptions_url(listing_id: @listing.id),
        params: {mercadopago_email: "no-es-email"}
      assert_redirected_to new_panel_listing_subscription_url(listing_id: @listing.id)
      assert_equal I18n.t("panel.listing_subscriptions.flash.invalid_email"), flash[:alert]
      assert_nil @member_user.reload.mercadopago_email
    end

    test "create shows an actionable alert when MP does not return init_point" do
      fake = Object.new
      fake.define_singleton_method(:create_listing_subscription) { |_l, **_kw| {"message" => "Internal server error"} }
      sign_in @member_user
      stub_class_method(MercadopagoService, :new, fake) do
        post panel_listing_subscriptions_url(listing_id: @listing.id),
          params: {mercadopago_email: "pagador@mp.cl"}
      end
      assert_redirected_to panel_listing_url(@listing)
      assert_equal I18n.t("panel.listing_subscriptions.flash.subscription_failed"), flash[:alert]
      assert_nil @listing.reload.preapproval_id
    end
```

- [ ] **Step 3: Correr — deben fallar**

Run: `bin/rails test test/controllers/panel/listing_subscriptions_controller_test.rb`
Expected: FAIL (no existe la ruta create ni el form; `new` aún crea la preapproval).

- [ ] **Step 4: Reescribir el controller** `app/controllers/panel/listing_subscriptions_controller.rb`

Cambiar el `before_action` para incluir `create`, reemplazar `new`, y agregar `create`:
```ruby
    before_action :set_listing, only: [:new, :create, :cancel]

    # GET /panel/listing_subscriptions/new?listing_id=X
    # Muestra el formulario para confirmar el email de MercadoPago (BR-142).
    def new
      unless @listing.subscribable?
        redirect_to panel_listing_path(@listing),
          alert: I18n.t("panel.listing_subscriptions.flash.not_subscribable")
        return
      end
      return unless ensure_priced_association!

      @payer_email = current_user.mercadopago_email.presence || current_user.email
    end

    # POST /panel/listing_subscriptions?listing_id=X
    # Guarda el email confirmado, crea la preapproval con ese payer_email y
    # redirige a MP para autorizar (BR-088/BR-142).
    def create
      unless @listing.subscribable?
        redirect_to panel_listing_path(@listing),
          alert: I18n.t("panel.listing_subscriptions.flash.not_subscribable")
        return
      end
      return unless ensure_priced_association!

      email = params[:mercadopago_email].to_s.strip
      unless email.match?(URI::MailTo::EMAIL_REGEXP)
        redirect_to new_panel_listing_subscription_path(listing_id: @listing.id),
          alert: I18n.t("panel.listing_subscriptions.flash.invalid_email")
        return
      end

      current_user.update!(mercadopago_email: email)
      @listing.update!(amount: @pricing.price, platform_fee: nil, neighborhood_association: @association)

      preapproval = mercadopago.create_listing_subscription(
        @listing, payer_email: email, back_url: success_panel_listing_subscriptions_url
      )
      init_point = preapproval["init_point"] || preapproval[:init_point]
      preapproval_id = (preapproval["id"] || preapproval[:id]).to_s

      if init_point.blank? || preapproval_id.blank?
        Rails.logger.error("MercadoPago returned no init_point/id for preapproval: #{preapproval.inspect}")
        redirect_to panel_listing_path(@listing),
          alert: I18n.t("panel.listing_subscriptions.flash.subscription_failed", email: email)
        return
      end

      @listing.update!(preapproval_id: preapproval_id, subscription_status: "pending")
      redirect_to init_point, allow_other_host: true
    rescue MercadopagoService::ConfigurationError => e
      Rails.logger.error("MercadoPago not configured: #{e.message}")
      redirect_to panel_listing_path(@listing),
        alert: I18n.t("panel.payments.flash.misconfigured")
    end
```
(El resto del controller — `success`, `cancel`, `mercadopago`, `set_listing`, `ensure_priced_association!` — no cambia. IMPORTANTE: eliminá el viejo cuerpo de `new` que creaba la preapproval.)

- [ ] **Step 5: Correr — el controller test aún fallará por la vista faltante**

Run: `bin/rails test test/controllers/panel/listing_subscriptions_controller_test.rb`
Expected: los tests de `create` (que redirigen) pasan; los de `new` FALLAN con "missing template listing_subscriptions/new". Se resuelve en Task 3.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(BR-142): ruta create + controller de suscripción con confirmación de email"
```

---

## Task 3: Vista del formulario + i18n

**Files:**
- Create: `app/views/panel/listing_subscriptions/new.html.erb`
- Modify: `config/locales/es.yml`, `config/locales/en.yml`

- [ ] **Step 1: Crear la vista** `app/views/panel/listing_subscriptions/new.html.erb`
```erb
<div class="max-w-lg mx-auto p-4">
  <h1 class="text-xl font-bold mb-4"><%= I18n.t("panel.listing_subscriptions.new.title") %></h1>

  <%= form_with url: panel_listing_subscriptions_path(listing_id: @listing.id), method: :post do |f| %>
    <label class="form-control w-full">
      <span class="label-text"><%= I18n.t("panel.listing_subscriptions.new.email_label") %></span>
      <%= f.email_field :mercadopago_email, value: @payer_email, required: true,
            class: "input input-bordered w-full" %>
    </label>
    <p class="text-sm text-warning mt-2"><%= I18n.t("panel.listing_subscriptions.new.email_hint") %></p>

    <div class="card-actions justify-end mt-4">
      <%= link_to I18n.t("actions.cancel"), panel_listing_path(@listing), class: "btn btn-ghost" %>
      <%= f.submit I18n.t("panel.listing_subscriptions.new.submit"), class: "btn btn-primary" %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 2: Agregar i18n en `config/locales/es.yml`** bajo `panel.listing_subscriptions` (después de la key `active_description` / antes de `success:`, respetando la indentación de 6 espacios):
```yaml
      new:
        title: Activar renovación automática
        email_label: Correo de tu cuenta MercadoPago
        email_hint: "Debe coincidir con el correo de tu cuenta de MercadoPago, o el cobro se rechazará."
        submit: Continuar a MercadoPago
```
Y en el bloque `flash:` de `listing_subscriptions` (junto a `not_subscribable`), agregar:
```yaml
        invalid_email: Ingresa un correo electrónico válido.
        subscription_failed: "No se pudo iniciar la suscripción. Verifica que el correo (%{email}) coincida con el de tu cuenta de MercadoPago."
```

- [ ] **Step 3: Agregar i18n en `config/locales/en.yml`**

Buscá si existe `panel.listing_subscriptions` en `en.yml`. Si NO existe (en.yml es un stub parcial), creá el bloque mínimo bajo `en > panel`:
```yaml
    listing_subscriptions:
      new:
        title: Enable auto-renewal
        email_label: Your MercadoPago account email
        email_hint: "It must match your MercadoPago account email, or the charge will be rejected."
        submit: Continue to MercadoPago
      flash:
        invalid_email: Enter a valid email address.
        subscription_failed: "The subscription couldn't be started. Check that the email (%{email}) matches your MercadoPago account."
```
Si YA existe, agregá solo las keys `new.*` y las de flash faltantes en el path correcto.
Verificá: `bin/rails runner "puts I18n.t('panel.listing_subscriptions.new.title'); puts I18n.t('panel.listing_subscriptions.flash.invalid_email')"` no debe dar "translation missing".

- [ ] **Step 4: Correr la suite del controller + modelo**

Run: `bin/rails test test/controllers/panel/listing_subscriptions_controller_test.rb test/models/user_test.rb`
Expected: PASS (0 failures). Si `actions.cancel` no existe como key i18n, usá una que exista (verificá con `grep -n 'cancel:' config/locales/es.yml`) o agregá `actions.cancel: Cancelar`.

- [ ] **Step 5: Correr la suite completa + linters**

Run: `bin/rails test && bin/standardrb && bundle exec erb_lint app/views/panel/listing_subscriptions/new.html.erb`
Expected: PASS / sin ofensas.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat(BR-142): formulario de confirmación de email + i18n"
```

---

## Task 4: Documentar BR-142 en CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Agregar la fila BR-142** a la tabla de reglas (después de BR-141):
```markdown
| BR-142 | Pagos | Para la auto-renovación de publicaciones (suscripción/preapproval, BR-088), el socio confirma en un paso previo el email de su cuenta de MercadoPago (`users.mercadopago_email`, distinto del email de login inmutable BR-093, prellenado y editable, persistido). Se envía como `payer_email` de la preapproval. MP valida que ese email coincida con el del pagador al autorizar/cobrar la suscripción sin plan asociado; si no coincide, rechaza el cobro (en sandbox, un email que no es test user hace fallar la creación con 500). NO aplica al pago único, donde el `payer.email` (BR-129/#129) es solo informativo. Implementado en `Panel::ListingSubscriptionsController#new` (form) + `#create` |
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: BR-142 — confirmación de email de MercadoPago para suscripciones"
```

---

## Task 5: Verificación final (bin/ci)

- [ ] **Step 1: Pipeline completo**

Run: `bin/ci`
Expected: verde en estilo, seguridad, zeitwerk, tests locales, build de imagen de producción y tests containerizados. Corregir lo que aparezca.

---

## Self-Review (autor del plan)

- **Cobertura del spec:** §1 modelo→Task 1; §2 rutas→Task 2 (step 1); §3 controller→Task 2; §4 vista→Task 3; §5 alcance (solo suscripción, no toca pago único)→respetado (Task 2 no toca PaymentsController); §6 i18n→Task 3; §7 BR-142→Task 4; testing→cada task + Task 5. Sin gaps.
- **Placeholders:** ninguno; código y comandos concretos. Los `if ... existe` de i18n en.yml traen ambas ramas explícitas.
- **Consistencia:** `mercadopago_email` (columna + param + validación), `@payer_email` (var de `new` usada en la vista), `flash.invalid_email`/`flash.subscription_failed`/`new.*` (mismas keys entre controller, vista y i18n). `create_listing_subscription(payer_email:)` — la firma del service ya existe y no cambia.
