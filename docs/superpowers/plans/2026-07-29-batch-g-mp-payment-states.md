# Batch G — Manejo completo de estados de pago de MercadoPago — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Que el webhook de MercadoPago reaccione a TODOS los estados de pago (no solo `approved`): registrar pagos en revisión (#125) y, ante un refund/contracargo (#127), revertir o invalidar el certificado/publicación (BR-141), notificando al staff.

**Architecture:** Se agrega una columna `payment_status` (estado crudo de MP) a `residence_certificates` y `listings`, sin tocar el enum de negocio (BR-064). El webhook cambia su idempotencia de "¿vi este payment_id?" a "¿cambió el estado?", y delega en un método de modelo `apply_mp_payment_status!` la reacción por estado. La invalidación de un certificado emitido se deriva de `payment_status` (verificación pública "No válido" + descarga bloqueada), sin reescribir el certificado inmutable.

**Tech Stack:** Rails 8.1, SQLite3, Minitest + fixtures, Solid Queue (mailers `deliver_later`).

**Spec:** `docs/superpowers/specs/2026-07-29-batch-g-mp-payment-states-design.md`

---

## File Structure

- `db/migrate/<ts>_add_payment_status_to_payables.rb` — Crear. Columna en ambas tablas.
- `db/schema.rb` — auto.
- `app/models/residence_certificate.rb` — Modificar: `payment_status` const/query, `payment_reverted?`, `downloadable?`, `immutable_once_issued` (exceptuar payment_status), `apply_mp_payment_status!`.
- `app/models/listing.rb` — Modificar: `payment_reverted?` (n/a público pero simétrico), `apply_mp_payment_status!`.
- `app/controllers/webhooks/mercadopago_controller.rb` — Modificar: idempotencia por estado + reacciones + notificación.
- `app/mailers/payment_reversal_mailer.rb` — Crear.
- `app/views/payment_reversal_mailer/staff_alert.html.erb` + `.text.erb` — Crear.
- `app/views/verifications/show.html.erb` — Modificar: precedencia `payment_reverted?`.
- `app/views/panel/residence_certificates/show.html.erb` — Modificar: aviso "en revisión".
- `config/locales/es.yml`, `config/locales/en.yml` — Modificar: i18n del aviso + mailer.
- `CLAUDE.md` — Modificar: BR-141.
- Tests: `test/models/residence_certificate_test.rb`, `test/models/listing_publication_test.rb`, `test/controllers/webhooks/mercadopago_controller_test.rb`, `test/controllers/verifications_controller_test.rb`, `test/mailers/payment_reversal_mailer_test.rb` (crear).

---

## Task 1: Columna `payment_status` + queries de modelo + inmutabilidad

**Files:**
- Create: `db/migrate/<ts>_add_payment_status_to_payables.rb`
- Modify: `app/models/residence_certificate.rb`, `app/models/listing.rb`
- Test: `test/models/residence_certificate_test.rb`

- [ ] **Step 1: Generar y escribir la migración**

Run: `bin/rails g migration AddPaymentStatusToPayables`

Cuerpo:
```ruby
class AddPaymentStatusToPayables < ActiveRecord::Migration[8.1]
  def change
    # #125/#127: estado crudo del último pago reportado por MP (approved,
    # in_process, pending, rejected, cancelled, refunded, charged_back).
    # No cambia el enum de negocio status/publication_status (BR-064).
    add_column :residence_certificates, :payment_status, :string
    add_column :listings, :payment_status, :string
  end
end
```

- [ ] **Step 2: Aplicar**

Run: `bin/rails db:migrate`
Expected: `db/schema.rb` tiene `t.string "payment_status"` en ambas tablas.

- [ ] **Step 3: Escribir tests de modelo (fallan)**

En `test/models/residence_certificate_test.rb`, agregar dentro de la clase:
```ruby
  test "payment_reverted? is true only for refunded and charged_back" do
    cert = ResidenceCertificate.new
    %w[refunded charged_back].each do |s|
      cert.payment_status = s
      assert cert.payment_reverted?, "#{s} debería contar como revertido"
    end
    %w[approved in_process pending rejected cancelled].each do |s|
      cert.payment_status = s
      assert_not cert.payment_reverted?, "#{s} no debería contar como revertido"
    end
    cert.payment_status = nil
    assert_not cert.payment_reverted?
  end

  test "downloadable? is false when payment was reverted" do
    cert = ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit, neighborhood_association: @association,
      purpose: "trámite", status: "issued", folio: "CR-#{@association.id}-9001",
      issue_date: Date.current, expiration_date: 30.days.from_now.to_date, issued_at: Time.current,
      payment_status: "charged_back"
    )
    assert_not cert.downloadable?, "un cert con pago revertido no debe poder descargarse"
  end

  test "payment_status can be updated on an issued certificate (not blocked by immutability)" do
    cert = ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit, neighborhood_association: @association,
      purpose: "trámite", status: "issued", folio: "CR-#{@association.id}-9002",
      issue_date: Date.current, expiration_date: 30.days.from_now.to_date, issued_at: Time.current
    )
    assert cert.update(payment_status: "charged_back"), cert.errors.full_messages.to_sentence
    assert_equal "charged_back", cert.reload.payment_status
  end

  test "other fields remain immutable on an issued certificate" do
    cert = ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit, neighborhood_association: @association,
      purpose: "trámite", status: "issued", folio: "CR-#{@association.id}-9003",
      issue_date: Date.current, expiration_date: 30.days.from_now.to_date, issued_at: Time.current
    )
    assert_not cert.update(purpose: "otro")
    assert cert.errors[:base].any?
  end
```

- [ ] **Step 4: Correr — deben fallar**

Run: `bin/rails test test/models/residence_certificate_test.rb -n "/payment_reverted|downloadable.*reverted|immutab|payment_status can be updated/"`
Expected: FAIL (`payment_reverted?` no existe, o la inmutabilidad bloquea payment_status).

- [ ] **Step 5: Implementar en `residence_certificate.rb`**

Agregar la constante junto a las otras (`STATUSES`, etc.):
```ruby
  REVERTED_PAYMENT_STATUSES = %w[refunded charged_back].freeze
```
Agregar el query (junto a `paid?`/`issued?`):
```ruby
  # BR-141: un pago revertido por MP (refund/contracargo) invalida el certificado.
  def payment_reverted?
    REVERTED_PAYMENT_STATUSES.include?(payment_status)
  end
```
Cambiar `downloadable?`:
```ruby
  def downloadable?
    issued? && !expired? && !holder_deactivated? && !payment_reverted?
  end
```
Cambiar `immutable_once_issued` (exceptuar payment_status, igual que los attachments):
```ruby
  def immutable_once_issued
    return unless status_in_database == "issued"
    # payment_status registra eventos de MP posteriores a la emisión (refund/
    # chargeback, BR-141) y no forma parte del contenido inmutable (BR-008).
    return if (changed - ["payment_status"]).empty?
    errors.add(:base, :immutable)
  end
```

- [ ] **Step 6: Correr — deben pasar**

Run: `bin/rails test test/models/residence_certificate_test.rb`
Expected: PASS (0 failures).

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(#125,#127): columna payment_status + payment_reverted?/downloadable? + excepción de inmutabilidad"
```

---

## Task 2: `apply_mp_payment_status!` en ambos modelos

**Files:**
- Modify: `app/models/residence_certificate.rb`, `app/models/listing.rb`
- Test: `test/models/residence_certificate_test.rb`, `test/models/listing_publication_test.rb`

- [ ] **Step 1: Tests de `ResidenceCertificate#apply_mp_payment_status!` (fallan)**

En `test/models/residence_certificate_test.rb`:
```ruby
  test "apply_mp_payment_status! registers non-approved status without changing business status" do
    cert = ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit, neighborhood_association: @association,
      purpose: "trámite", status: "pending_payment", amount: 1500
    )
    cert.apply_mp_payment_status!("in_process")
    assert_equal "in_process", cert.payment_status
    assert cert.pending_payment?, "in_process no debe cambiar el status de negocio"
  end

  test "apply_mp_payment_status! reverts a paid (not issued) certificate to pending_payment" do
    cert = ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit, neighborhood_association: @association,
      purpose: "trámite", status: "paid", amount: 1500, payment_id: "MP-REV-1", paid_at: Time.current
    )
    cert.apply_mp_payment_status!("refunded")
    assert_equal "refunded", cert.payment_status
    assert cert.pending_payment?, "un paid no emitido revierte a pending_payment (BR-073)"
  end

  test "apply_mp_payment_status! keeps an issued certificate issued but marks it reverted" do
    cert = ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit, neighborhood_association: @association,
      purpose: "trámite", status: "issued", folio: "CR-#{@association.id}-9101",
      issue_date: Date.current, expiration_date: 30.days.from_now.to_date, issued_at: Time.current
    )
    cert.apply_mp_payment_status!("charged_back")
    assert cert.issued?, "el cert emitido sigue issued (BR-008), no se reescribe"
    assert cert.payment_reverted?
  end

  test "apply_mp_payment_status! is idempotent for the same status" do
    cert = ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit, neighborhood_association: @association,
      purpose: "trámite", status: "pending_payment", amount: 1500, payment_status: "in_process"
    )
    assert_no_changes -> { cert.reload.updated_at } do
      cert.apply_mp_payment_status!("in_process")
    end
  end
```

- [ ] **Step 2: Correr — fallan**

Run: `bin/rails test test/models/residence_certificate_test.rb -n "/apply_mp_payment_status/"`
Expected: FAIL (método no existe).

- [ ] **Step 3: Implementar en `residence_certificate.rb`** (público, junto a `mark_as_paid!`/`issue!`)
```ruby
  # Registra el estado crudo de un pago no-`approved` de MP y aplica la reacción
  # de negocio (BR-141, BR-073). Idempotente por estado. `approved` NO pasa por
  # aquí — el webhook usa mark_as_paid!.
  def apply_mp_payment_status!(mp_status)
    return self if payment_status == mp_status

    if REVERTED_PAYMENT_STATUSES.include?(mp_status) && paid?
      # Pago revertido antes de emitir → vuelve a pending_payment (BR-073).
      update!(payment_status: mp_status, status: "pending_payment")
    else
      # Emitido revertido (queda inválido vía payment_reverted?), o estados
      # en revisión / rechazados: solo se registra el estado crudo.
      update!(payment_status: mp_status)
    end
    self
  end
```

- [ ] **Step 4: Correr — pasan**

Run: `bin/rails test test/models/residence_certificate_test.rb -n "/apply_mp_payment_status/"`
Expected: PASS.

- [ ] **Step 5: Test de `Listing#apply_mp_payment_status!` (falla)**

En `test/models/listing_publication_test.rb`:
```ruby
  test "apply_mp_payment_status! unpublishes a listing whose payment was reverted" do
    listing = Listing.create!(name: "Pub", user: users(:artanis), amount: 1200)
    listing.mark_as_paid!(payment_id: "MP-LREV-1")
    assert listing.published?

    listing.apply_mp_payment_status!("charged_back")
    assert_equal "charged_back", listing.payment_status
    assert listing.pending_payment?, "el listing revertido se despublica"
    assert_nil listing.published_until
  end

  test "apply_mp_payment_status! registers non-reverted status without unpublishing" do
    listing = Listing.create!(name: "Pub", user: users(:artanis), amount: 1200)
    listing.mark_as_paid!(payment_id: "MP-LREV-2")
    listing.apply_mp_payment_status!("in_process")
    assert_equal "in_process", listing.payment_status
    assert listing.published?, "in_process no despublica"
  end
```

- [ ] **Step 6: Implementar en `listing.rb`** (público)
```ruby
  REVERTED_PAYMENT_STATUSES = %w[refunded charged_back].freeze

  def payment_reverted?
    REVERTED_PAYMENT_STATUSES.include?(payment_status)
  end

  # Espejo de ResidenceCertificate#apply_mp_payment_status! para publicaciones
  # (BR-141). Un pago revertido despublica; los demás estados solo se registran.
  def apply_mp_payment_status!(mp_status)
    return self if payment_status == mp_status

    if REVERTED_PAYMENT_STATUSES.include?(mp_status) && published?
      update!(payment_status: mp_status, publication_status: "pending_payment", published_until: nil)
    else
      update!(payment_status: mp_status)
    end
    self
  end
```

- [ ] **Step 7: Correr — pasan**

Run: `bin/rails test test/models/listing_publication_test.rb`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(#125,#127): apply_mp_payment_status! en cert y listing (revierte/despublica/registra)"
```

---

## Task 3: Mailer de alerta al staff

**Files:**
- Create: `app/mailers/payment_reversal_mailer.rb`, `app/views/payment_reversal_mailer/staff_alert.html.erb`, `.text.erb`
- Modify: `config/locales/es.yml`, `config/locales/en.yml`
- Test: `test/mailers/payment_reversal_mailer_test.rb` (crear)

- [ ] **Step 1: Test del mailer (falla)**

Crear `test/mailers/payment_reversal_mailer_test.rb`:
```ruby
require "test_helper"

class PaymentReversalMailerTest < ActionMailer::TestCase
  test "staff_alert is addressed to the staff and names the payable" do
    staff = users(:selendis) # tiene email
    cert = residence_certificates(:selendis_issued) rescue ResidenceCertificate.create!(
      member: members(:selendis_member), household_unit: household_units(:selendis_household),
      neighborhood_association: neighborhood_associations(:manios_de_buin), purpose: "t",
      status: "issued", folio: "CR-1-7777", issue_date: Date.current,
      expiration_date: 30.days.from_now.to_date, issued_at: Time.current, payment_status: "charged_back"
    )
    mail = PaymentReversalMailer.staff_alert(staff, cert)
    assert_equal [staff.email], mail.to
    assert_match cert.folio.to_s, mail.body.encoded
  end

  test "staff_alert returns early when staff has no email" do
    staff = User.new(email: "")
    cert = ResidenceCertificate.new(id: 1, folio: "CR-1-1", payment_status: "refunded")
    mail = PaymentReversalMailer.staff_alert(staff, cert)
    assert_nil mail.message.to # or message is NullMail
  end
end
```

- [ ] **Step 2: Correr — falla**

Run: `bin/rails test test/mailers/payment_reversal_mailer_test.rb`
Expected: FAIL (mailer no existe).

- [ ] **Step 3: Crear el mailer** `app/mailers/payment_reversal_mailer.rb`
```ruby
class PaymentReversalMailer < ApplicationMailer
  # BR-141: aviso al staff (superadmin) de que un pago fue revertido
  # (refund/contracargo). El payable es un ResidenceCertificate o Listing.
  def staff_alert(staff, payable)
    return if staff.email.blank?
    @payable = payable
    @kind = payable.is_a?(ResidenceCertificate) ? :certificate : :listing
    mail to: staff.email, subject: t(".subject")
  end
end
```

- [ ] **Step 4: Crear las vistas**

`app/views/payment_reversal_mailer/staff_alert.text.erb`:
```erb
<%= t("payment_reversal_mailer.staff_alert.body_intro") %>

<% if @kind == :certificate %>
- <%= t("payment_reversal_mailer.staff_alert.folio") %>: <%= @payable.folio %>
<% else %>
- <%= t("payment_reversal_mailer.staff_alert.listing") %>: <%= @payable.name %>
<% end %>
- <%= t("payment_reversal_mailer.staff_alert.payment_status") %>: <%= @payable.payment_status %>
- <%= t("payment_reversal_mailer.staff_alert.payment_id") %>: <%= @payable.payment_id %>

<%= t("payment_reversal_mailer.staff_alert.body_action") %>
```

`app/views/payment_reversal_mailer/staff_alert.html.erb`:
```erb
<h2><%= t("payment_reversal_mailer.staff_alert.body_intro") %></h2>
<ul>
  <% if @kind == :certificate %>
    <li><strong><%= t("payment_reversal_mailer.staff_alert.folio") %>:</strong> <%= @payable.folio %></li>
  <% else %>
    <li><strong><%= t("payment_reversal_mailer.staff_alert.listing") %>:</strong> <%= @payable.name %></li>
  <% end %>
  <li><strong><%= t("payment_reversal_mailer.staff_alert.payment_status") %>:</strong> <%= @payable.payment_status %></li>
  <li><strong><%= t("payment_reversal_mailer.staff_alert.payment_id") %>:</strong> <%= @payable.payment_id %></li>
</ul>
<p><%= t("payment_reversal_mailer.staff_alert.body_action") %></p>
```

- [ ] **Step 5: i18n (es.yml y en.yml)**

En `config/locales/es.yml`, bajo la raíz `es:` (junto a otros mailers), agregar:
```yaml
  payment_reversal_mailer:
    staff_alert:
      subject: "Alerta: pago revertido en Yuntapp"
      body_intro: "Se revirtió un pago (reembolso o contracargo). Revisar posible fraude."
      folio: "Folio del certificado"
      listing: "Publicación"
      payment_status: "Estado del pago"
      payment_id: "ID de pago MercadoPago"
      body_action: "El documento quedó invalidado automáticamente. Si corresponde, evaluar desactivar al socio (BR-091)."
```
En `config/locales/en.yml`, bajo `en:`:
```yaml
  payment_reversal_mailer:
    staff_alert:
      subject: "Alert: reverted payment in Yuntapp"
      body_intro: "A payment was reverted (refund or chargeback). Review for possible fraud."
      folio: "Certificate folio"
      listing: "Listing"
      payment_status: "Payment status"
      payment_id: "MercadoPago payment id"
      body_action: "The document was automatically invalidated. If warranted, consider deactivating the member (BR-091)."
```

- [ ] **Step 6: Correr — pasa**

Run: `bin/rails test test/mailers/payment_reversal_mailer_test.rb`
Expected: PASS. Si `users(:selendis)` no tiene email o `members(:selendis_member)` no existe, ajustar a fixtures válidas (revisar `test/fixtures/users.yml`, `members.yml`).

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(#127): PaymentReversalMailer#staff_alert + i18n"
```

---

## Task 4: Rediseño del webhook — idempotencia por estado + reacciones + notificación

**Files:**
- Modify: `app/controllers/webhooks/mercadopago_controller.rb`
- Test: `test/controllers/webhooks/mercadopago_controller_test.rb`

- [ ] **Step 1: Escribir tests del webhook (fallan)**

En `test/controllers/webhooks/mercadopago_controller_test.rb`, agregar dentro de la clase (usar el helper `stub_fetch_payment` existente):
```ruby
    test "in_process payment is registered without issuing the certificate (#125)" do
      stub_fetch_payment({
        "id" => "MP-INPROC", "transaction_amount" => 1500, "status" => "in_process",
        "external_reference" => @certificate.id.to_s
      }) do
        post webhooks_mercadopago_url, params: {topic: "payment", data: {id: "MP-INPROC"}}
      end
      assert_response :ok
      @certificate.reload
      assert_equal "in_process", @certificate.payment_status
      assert @certificate.pending_payment?
    end

    test "charged_back on an issued certificate invalidates it and alerts staff (#127, BR-141)" do
      @certificate.update!(status: "paid", payment_id: "MP-OK", paid_at: Time.current)
      @certificate.issue!
      assert @certificate.issued?

      assert_enqueued_emails 1 do
        stub_fetch_payment({
          "id" => "MP-OK", "transaction_amount" => 1500, "status" => "charged_back",
          "external_reference" => @certificate.id.to_s
        }) do
          post webhooks_mercadopago_url, params: {topic: "payment", data: {id: "MP-OK"}}
        end
      end
      assert_response :ok
      @certificate.reload
      assert @certificate.issued?, "sigue issued (BR-008)"
      assert @certificate.payment_reverted?
      assert_not @certificate.downloadable?
    end

    test "refund on a paid (not issued) certificate reverts it to pending_payment (#127)" do
      @certificate.update!(status: "paid", payment_id: "MP-PAID", paid_at: Time.current)
      stub_fetch_payment({
        "id" => "MP-PAID", "transaction_amount" => 1500, "status" => "refunded",
        "external_reference" => @certificate.id.to_s
      }) do
        post webhooks_mercadopago_url, params: {topic: "payment", data: {id: "MP-PAID"}}
      end
      assert_response :ok
      @certificate.reload
      assert @certificate.pending_payment?
      assert_equal "refunded", @certificate.payment_status
    end

    test "re-notification of the same payment_status is a no-op" do
      @certificate.update!(payment_status: "in_process")
      stub_fetch_payment({
        "id" => "MP-SAME", "transaction_amount" => 1500, "status" => "in_process",
        "external_reference" => @certificate.id.to_s
      }) do
        assert_no_enqueued_emails do
          post webhooks_mercadopago_url, params: {topic: "payment", data: {id: "MP-SAME"}}
        end
      end
      assert_response :ok
    end
```

- [ ] **Step 2: Correr — fallan**

Run: `bin/rails test test/controllers/webhooks/mercadopago_controller_test.rb -n "/in_process|charged_back|refund on a paid|re-notification/"`
Expected: FAIL (hoy solo maneja approved; y el short-circuit por payment_id bloquea MP-OK).

- [ ] **Step 3: Reescribir `process_payment_notification`** (quitar short-circuit por payment_id; siempre fetch)
```ruby
    # topic=payment: data_id es un payment_id. Siempre consultamos el estado
    # real; la idempotencia es por estado (ver mark_payable_paid), no por
    # "payment_id ya visto" — un refund/contracargo reusa el payment_id.
    def process_payment_notification(payment_id)
      payment = mercadopago.fetch_payment(payment_id)
      return unless payment.is_a?(Hash)
      mark_payable_paid(payment, payment_id)
    end
```
Y en `process_merchant_order`, quitar el `next if ... payment_already_processed?(pid.to_s)` (dejar solo `next if pid.nil?`):
```ruby
      payments.each do |payment_entry|
        pid = payment_entry["id"]
        next if pid.nil?
        payment = mercadopago.fetch_payment(pid.to_s)
        mark_payable_paid(payment, pid.to_s)
      end
```

- [ ] **Step 4: Reescribir `mark_certificate_paid` y `mark_listing_paid`** con la reacción por estado

`mark_certificate_paid`:
```ruby
    def mark_certificate_paid(certificate_id, status, payment_id, amount)
      certificate = ResidenceCertificate.find_by(id: certificate_id)
      unless certificate
        Rails.logger.warn("MercadoPago webhook: certificate ##{certificate_id} not found")
        return
      end

      unless amount_matches?(amount, certificate.amount)
        Rails.logger.warn("MercadoPago webhook: payment #{payment_id} amount #{amount.inspect} != certificate ##{certificate.id} amount #{certificate.amount.inspect} — rejected")
        return
      end

      case status.to_s
      when "approved"
        certificate.mark_as_paid!(payment_id: payment_id)
        certificate.update!(payment_status: "approved") unless certificate.payment_status == "approved"
        Rails.logger.info("MercadoPago webhook: certificate ##{certificate.id} marked paid (payment_id=#{payment_id})")
      else
        handle_non_approved(certificate, status.to_s, payment_id)
      end
    end
```
`mark_listing_paid` (análogo):
```ruby
    def mark_listing_paid(listing_id, status, payment_id, amount)
      listing = Listing.find_by(id: listing_id)
      unless listing
        Rails.logger.warn("MercadoPago webhook: listing ##{listing_id} not found")
        return
      end

      unless amount_matches?(amount, listing.amount)
        Rails.logger.warn("MercadoPago webhook: payment #{payment_id} amount #{amount.inspect} != listing ##{listing.id} amount #{listing.amount.inspect} — rejected")
        return
      end

      case status.to_s
      when "approved"
        listing.mark_as_paid!(payment_id: payment_id)
        listing.update!(payment_status: "approved") unless listing.payment_status == "approved"
        Rails.logger.info("MercadoPago webhook: listing ##{listing.id} published (payment_id=#{payment_id})")
      else
        handle_non_approved(listing, status.to_s, payment_id)
      end
    end
```

- [ ] **Step 5: Agregar el helper `handle_non_approved`** (private)
```ruby
    # #125/#127: aplica un estado no-approved de MP al payable. Idempotente por
    # estado (apply_mp_payment_status! no hace nada si el estado no cambió).
    # Ante un pago revertido (refund/contracargo) notifica al staff (BR-141).
    def handle_non_approved(payable, status, payment_id)
      changed = payable.payment_status != status
      payable.apply_mp_payment_status!(status)
      unless changed
        Rails.logger.info("MercadoPago webhook: #{payable.class}##{payable.id} status=#{status} unchanged — no-op")
        return
      end

      if ResidenceCertificate::REVERTED_PAYMENT_STATUSES.include?(status)
        Rails.logger.error("MercadoPago webhook: PAYMENT REVERTED #{payable.class}##{payable.id} status=#{status} (payment_id=#{payment_id})")
        notify_staff_of_reversal(payable)
      else
        Rails.logger.info("MercadoPago webhook: #{payable.class}##{payable.id} payment_status=#{status} registered")
      end
    end

    def notify_staff_of_reversal(payable)
      User.where(superadmin: true).find_each do |staff|
        PaymentReversalMailer.staff_alert(staff, payable).deliver_later if staff.email.present?
      end
    end
```

- [ ] **Step 6: Correr los tests del webhook**

Run: `bin/rails test test/controllers/webhooks/mercadopago_controller_test.rb`
Expected: PASS. Ojo: algún test viejo asumía el short-circuit por payment_id (`ignores duplicate webhook for already-processed payment_id`). Ese test cambia de semántica: ahora un re-envío del MISMO estado approved debe seguir siendo no-op porque `mark_as_paid!` es idempotente y `apply_mp_payment_status!` no aplica a approved. Verificar ese test y ajustarlo si su intención (no doble-emisión) se mantiene: el certificado no debe re-emitirse. Si el test consultaba `payment_already_processed?`, reescribirlo para afirmar el comportamiento observable (status/payment_id sin cambios, sin doble efecto).

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(#125,#127): webhook idempotente por estado + reacciones + alerta al staff"
```

---

## Task 5: Verificación pública + UI del socio "en revisión"

**Files:**
- Modify: `app/views/verifications/show.html.erb`, `app/views/panel/residence_certificates/show.html.erb`, `config/locales/es.yml`, `config/locales/en.yml`
- Test: `test/controllers/verifications_controller_test.rb`

- [ ] **Step 1: Test de verificación pública (falla)**

En `test/controllers/verifications_controller_test.rb`, agregar:
```ruby
  test "reverted certificate shows as No válido (revoked) with 200" do
    cert = residence_certificates(:one) rescue nil
    # usar un cert issued verificable; si no hay fixture, crear uno:
    cert = ResidenceCertificate.create!(
      member: members(:selendis_member), household_unit: household_units(:selendis_household),
      neighborhood_association: neighborhood_associations(:manios_de_buin), purpose: "t",
      status: "issued", folio: "CR-1-7001", validation_token: "tok-revert-1", validation_code: "REVRT123",
      issue_date: Date.current, expiration_date: 30.days.from_now.to_date, issued_at: Time.current,
      payment_status: "charged_back"
    )
    get verification_url(cert.validation_token)
    assert_response :ok
    assert_match I18n.t("verifications.show.status.revoked_badge"), @response.body
  end
```

- [ ] **Step 2: Correr — falla**

Run: `bin/rails test test/controllers/verifications_controller_test.rb -n "/reverted certificate/"`
Expected: FAIL (hoy un cert con pago revertido pero titular activo se muestra "Vigente").

- [ ] **Step 3: Modificar la precedencia en `verifications/show.html.erb`**

Cambiar la condición inicial:
```erb
  # BR-091/BR-141: el certificado es "No válido" si el titular fue desactivado
  # O si el pago fue revertido (refund/contracargo). Precedencia sobre vencido.
  # Siempre responde 200 (BR-009/BR-080).
  if @certificate.holder_deactivated? || @certificate.payment_reverted?
    status_key, badge_class, alert_class = "revoked", "badge-error", "alert-error"
  elsif @certificate.expired?
```
(El resto de la vista no cambia; reutiliza el badge/descr `revoked` — no se expone el motivo al verificador.)

- [ ] **Step 4: Correr — pasa**

Run: `bin/rails test test/controllers/verifications_controller_test.rb`
Expected: PASS.

- [ ] **Step 5: Aviso "Pago en revisión" en `panel/residence_certificates/show.html.erb`**

Después del bloque `if @residence_certificate.pending_payment? && amount.present?` (que muestra el botón pagar), agregar:
```erb
      <% if @residence_certificate.pending_payment? && %w[in_process pending].include?(@residence_certificate.payment_status) %>
        <div class="alert alert-warning mt-4">
          <%= I18n.t('panel.residence_certificates.show.payment_in_review') %>
        </div>
      <% end %>
```

- [ ] **Step 6: i18n del aviso**

En `config/locales/es.yml`, bajo `panel.residence_certificates.show` (donde está `processing:`), agregar:
```yaml
        payment_in_review: "Tu pago está siendo revisado por MercadoPago. En cuanto se apruebe, el certificado se emitirá automáticamente."
```
En `config/locales/en.yml`, la key equivalente:
```yaml
        payment_in_review: "Your payment is under review by MercadoPago. Once approved, the certificate will be issued automatically."
```

- [ ] **Step 7: Correr la suite + linters**

Run: `bin/rails test && bin/standardrb && bundle exec erb_lint --lint-all`
Expected: PASS / sin ofensas.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat(#125,#127): verificación pública 'No válido' ante pago revertido + aviso 'en revisión' en el panel"
```

---

## Task 6: Documentar BR-141 en CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Agregar la fila BR-141** a la tabla de reglas de negocio (después de BR-140):
```markdown
| BR-141 | Certificados | Un pago revertido por MercadoPago (`refunded`/`charged_back`, típicamente un contracargo iniciado por el banco del comprador días/semanas después) invalida el certificado. Se registra en `payment_status` (columna cruda de MP, no cambia el enum `status`/BR-064). Si el certificado ya fue **emitido**: sigue `issued` (inmutable, BR-008) pero la verificación pública lo muestra **No válido** (precedencia sobre Vencido, junto con BR-091 — `payment_reverted?`) y la descarga desde el panel queda bloqueada (`downloadable?`); el PDF ya descargado queda fuera de alcance pero sin valor de verificación. Si aún estaba **`paid`** (no emitido): vuelve a `pending_payment` (BR-073). Si es una **publicación** `published`: se despublica. Es la **primera vía de invalidación individual** de un certificado (matiza BR-008/BR-064/BR-097). El staff (superadmin) es notificado (`PaymentReversalMailer`) para evaluar fraude y, si corresponde, desactivar al socio (BR-091). Implementado vía `ResidenceCertificate#apply_mp_payment_status!` + webhook idempotente por estado |
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: BR-141 — invalidación de certificado por pago revertido (#127)"
```

---

## Task 7: Verificación final (bin/ci)

- [ ] **Step 1: Pipeline completo**

Run: `bin/ci`
Expected: verde en estilo, seguridad, zeitwerk, tests locales, build de imagen de producción y tests containerizados. (Requiere Docker.) Corregir lo que aparezca.

---

## Self-Review (autor del plan)

- **Cobertura del spec:** §1 modelo→Task 1; §2 idempotencia→Task 4; §3 reacciones→Task 2+4; §4 verificación→Task 5; §5 descarga→Task 1 (`downloadable?`); §6 UI→Task 5; §7 notificación→Task 3+4; §8 BR-141→Task 6; §9 testing→cada task + Task 7. Sin gaps.
- **Placeholders:** ninguno; código y comandos concretos. Los `rescue nil` en tests son fallbacks explícitos por si falta una fixture, con instrucción de ajustar.
- **Consistencia:** `apply_mp_payment_status!`, `payment_reverted?`, `REVERTED_PAYMENT_STATUSES`, `handle_non_approved`, `notify_staff_of_reversal`, `PaymentReversalMailer.staff_alert` — nombres usados idénticos entre tasks. `payment_status` string en ambos modelos.
