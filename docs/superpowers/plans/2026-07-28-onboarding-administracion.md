# Onboarding de Administración — Implementation Plan (Plan 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permitir que un dirigente acreditado solicite administrar una junta (existente o nueva) desde el panel; solo el staff (superadmin) aprueba; al aprobar, el solicitante queda como admin + socio (Member) + directiva (BoardMember) en una transacción.

**Architecture:** Modelo nuevo `AdministrationRequest` (institucional, separado de `OnboardingRequest`). El panel usa un formulario de página única con selector en cascada región→comuna→junta (más opción "crear nueva"). La aprobación vive en `AdministrationApprovalService` (transacción atómica) reutilizando `IdentityTransferService` (ADR-006), `VerifiedIdentity`, `Member`, `BoardMember`. La revisión ocurre en el namespace `superadmin`. Notificaciones vía mailer + job recurrente.

**Tech Stack:** Rails 8.1, SQLite3, Hotwire (Turbo/Stimulus), Active Storage, Minitest + fixtures YAML, Standard Ruby.

**Prerrequisito:** Plan 1 (RUT en la junta) — ya mergeado (#120). `NeighborhoodAssociation.rut` es `NOT NULL`/único/validado.

**Reglas cubiertas:** BR-119…121 (RUT, ya vivas) + BR-122…140 (administración). Ver `docs/superpowers/specs/2026-07-27-onboarding-administracion-design.md`.

**Decisión de simplificación:** el panel es un formulario de **página única** (no 4 pasos como el onboarding de residente). Se crea la `AdministrationRequest` directamente en `pending` con validación de completitud. El estado `draft` existe en el modelo para "duplicar/reenviar" futuro (BR-131) pero la UI v1 no persiste borradores.

---

### Task 1: Migración — tabla `administration_requests`

**Files:**
- Create: `db/migrate/20260728120000_create_administration_requests.rb`
- Modify: `db/schema.rb` (se regenera)

- [ ] **Step 1: Escribir la migración**

```ruby
# db/migrate/20260728120000_create_administration_requests.rb
class CreateAdministrationRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :administration_requests do |t|
      t.references :user, null: false, foreign_key: true
      t.references :neighborhood_association, foreign_key: true # junta existente (opcional)
      t.references :region, foreign_key: true
      t.references :commune, foreign_key: true
      t.string :proposed_association_name # junta nueva (opcional)
      t.string :organization_rut          # RUT de la organización (obligatorio al enviar)
      t.string :position                  # cargo de directiva
      t.string :first_name
      t.string :last_name
      t.string :run
      t.string :phone
      t.string :status, null: false, default: "draft"
      t.references :reviewed_by, foreign_key: {to_table: :users}
      t.datetime :reviewed_at
      t.text :rejection_reason

      t.timestamps
    end

    add_index :administration_requests, :status
  end
end
```

- [ ] **Step 2: Migrar**

Run: `bin/rails db:migrate`
Expected: crea la tabla; `db/schema.rb` incluye `create_table "administration_requests"` con las columnas y los índices de las `references`.

- [ ] **Step 3: Commit**

```bash
git add db/migrate/20260728120000_create_administration_requests.rb db/schema.rb
git commit -m "feat(admin-onboarding): tabla administration_requests"
```

---

### Task 2: Modelo `AdministrationRequest` + fixtures

**Files:**
- Create: `app/models/administration_request.rb`
- Create: `test/fixtures/administration_requests.yml`
- Test: `test/models/administration_request_test.rb`

Patrones reutilizados: normalización de RUN/RUT/teléfono/nombres igual que `VerifiedIdentity`; `BoardMember::POSITIONS`; estados string estilo `OnboardingRequest`.

- [ ] **Step 1: Escribir tests que fallan**

```ruby
# test/models/administration_request_test.rb
require "test_helper"

class AdministrationRequestTest < ActiveSupport::TestCase
  def base_attrs(overrides = {})
    {
      user: users(:urunis),
      neighborhood_association: neighborhood_associations(:manios_de_buin),
      organization_rut: "83014859-0",
      position: "presidente",
      first_name: "juan",
      last_name: "pérez",
      run: "16.912.345-0",
      phone: "987654321",
      status: "pending"
    }.merge(overrides)
  end

  test "normaliza run, rut, telefono y nombres" do
    r = AdministrationRequest.new(base_attrs)
    r.valid?
    assert_equal "16912345-0", r.run
    assert_equal "83014859-0", r.organization_rut
    assert_equal "+56987654321", r.phone
    assert_equal "Juan", r.first_name
    assert_equal "Pérez", r.last_name
  end

  test "pending exige cargo valido" do
    r = AdministrationRequest.new(base_attrs(position: "capataz"))
    assert_not r.valid?
    assert_includes r.errors.attribute_names, :position
  end

  test "pending exige rut de organizacion valido" do
    r = AdministrationRequest.new(base_attrs(organization_rut: "83014859-5"))
    assert_not r.valid?
    assert_includes r.errors.attribute_names, :organization_rut
  end

  test "pending exige junta existente o nombre+comuna nuevos" do
    r = AdministrationRequest.new(base_attrs(neighborhood_association: nil, proposed_association_name: nil))
    assert_not r.valid?
    assert_includes r.errors.attribute_names, :base
  end

  test "acepta junta nueva con nombre y comuna" do
    r = AdministrationRequest.new(base_attrs(
      neighborhood_association: nil,
      proposed_association_name: "Junta Nueva Los Robles",
      commune: communes(:commune_0_0_0)
    ))
    assert r.valid?, r.errors.full_messages.to_sentence
  end

  test "un usuario no puede tener dos solicitudes activas" do
    AdministrationRequest.create!(base_attrs)
    dup = AdministrationRequest.new(base_attrs)
    assert_not dup.valid?
    assert_includes dup.errors.attribute_names, :base
  end

  test "submit! pasa de draft a pending" do
    r = AdministrationRequest.create!(base_attrs(status: "draft"))
    r.submit!
    assert r.pending?
  end

  test "cancel! solo desde pending" do
    r = AdministrationRequest.create!(base_attrs)
    r.cancel!
    assert r.cancelled?
  end
end
```

- [ ] **Step 2: Correr para ver fallar**

Run: `bin/rails test test/models/administration_request_test.rb`
Expected: FAIL (modelo no existe).

- [ ] **Step 3: Crear el modelo**

```ruby
# app/models/administration_request.rb
class AdministrationRequest < ApplicationRecord
  include Filterable

  STATUSES = %w[draft pending approved rejected cancelled].freeze

  belongs_to :user
  belongs_to :neighborhood_association, optional: true
  belongs_to :region, optional: true
  belongs_to :commune, optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true

  has_one_attached :directiva_validity_document
  has_many_attached :identity_documents

  before_validation :normalize_run_field
  before_validation :normalize_rut_field
  before_validation :normalize_phone
  before_validation :normalize_names

  validates :status, presence: true, inclusion: {in: STATUSES}

  # BR-123/BR-127: al enviar (pending) se exige la documentación y datos completos.
  with_options if: -> { pending? } do
    validates :position, presence: true, inclusion: {in: BoardMember::POSITIONS}
    validates :first_name, :last_name, :phone, presence: true
    validates :organization_rut, presence: true
    validates :run, presence: true
    validate :target_association_present
  end
  validates :organization_rut, run: true, if: -> { organization_rut.present? }
  validates :run, run: true, if: -> { run.present? }

  # BR-134: una sola solicitud activa (draft/pending) por usuario.
  validate :only_one_active_per_user

  scope :draft, -> { where(status: "draft") }
  scope :pending, -> { where(status: "pending") }
  scope :approved, -> { where(status: "approved") }
  scope :rejected, -> { where(status: "rejected") }
  scope :cancelled, -> { where(status: "cancelled") }
  scope :active, -> { where(status: %w[draft pending]) }

  def draft? = status == "draft"
  def pending? = status == "pending"
  def approved? = status == "approved"
  def rejected? = status == "rejected"
  def cancelled? = status == "cancelled"

  def new_association? = neighborhood_association_id.blank? && proposed_association_name.present?

  def applicant_name = [first_name, last_name].compact.join(" ")

  def target_association_label
    neighborhood_association&.name || proposed_association_name
  end

  def submit!
    update!(status: "pending")
    self
  end

  def cancel!
    raise "Only pending administration requests can be cancelled (current: #{status})" unless pending?
    update!(status: "cancelled")
    self
  end

  private

  def target_association_present
    return if neighborhood_association_id.present?
    return if proposed_association_name.present? && commune_id.present?
    errors.add(:base, I18n.t("activerecord.errors.models.administration_request.target_missing"))
  end

  def only_one_active_per_user
    return unless draft? || pending?
    scope = AdministrationRequest.active.where(user_id: user_id)
    scope = scope.where.not(id: id) if persisted?
    errors.add(:base, I18n.t("activerecord.errors.models.administration_request.already_active")) if scope.exists?
  end

  # Mismo patrón que VerifiedIdentity#normalize_run_field.
  def normalize_run_field
    return unless run.present?
    self.run = run.to_s.gsub(/[.\-\s]/, "").upcase
    self.run = "#{run[0..-2]}-#{run[-1]}" if run.match?(/\A\d{7,8}[0-9K]\z/)
  end

  def normalize_rut_field
    return unless organization_rut.present?
    self.organization_rut = organization_rut.to_s.gsub(/[.\-\s]/, "").upcase
    self.organization_rut = "#{organization_rut[0..-2]}-#{organization_rut[-1]}" if organization_rut.match?(/\A\d{7,8}[0-9K]\z/)
  end

  def normalize_phone
    return unless phone.present?
    digits = phone.to_s.gsub(/[^\d]/, "")
    digits = digits.delete_prefix("56") if digits.start_with?("56")
    self.phone = "+56#{digits}" if digits.length == 9
  end

  def normalize_names
    self.first_name = first_name.to_s.strip.split.map(&:capitalize).join(" ") if first_name.present?
    self.last_name = last_name.to_s.strip.split.map(&:capitalize).join(" ") if last_name.present?
  end
end
```

Nota: verifica el patrón exacto de `normalize_phone` contra `app/models/verified_identity.rb` y ajústalo si el proyecto normaliza distinto (el objetivo es `+569XXXXXXXX`). Reusa la misma lógica que ya existe.

- [ ] **Step 4: Crear fixtures mínimas**

```yaml
# test/fixtures/administration_requests.yml
pending_manios:
  user: urunis
  neighborhood_association: manios_de_buin
  organization_rut: "83312584-2"
  position: presidente
  first_name: Ana
  last_name: Soto
  run: "15111222-3"
  phone: "+56911112222"
  status: pending
```

Nota: verifica que `run: "15111222-3"` tenga DV válido (módulo 11); si no, usa uno válido. Igual para `organization_rut`.

- [ ] **Step 5: Correr tests para ver pasar**

Run: `bin/rails test test/models/administration_request_test.rb`
Expected: PASS. Ajusta RUN/RUT de fixtures/tests si el DV falla.

- [ ] **Step 6: i18n de errores del modelo**

En `config/locales/es.yml`, bajo `activerecord: errors: models:` agrega:
```yaml
        administration_request:
          target_missing: Debes seleccionar una junta existente o indicar nombre y comuna de una nueva
          already_active: Ya tienes una solicitud de administración en curso
```

- [ ] **Step 7: Commit**

```bash
git add app/models/administration_request.rb test/fixtures/administration_requests.yml test/models/administration_request_test.rb config/locales/es.yml
git commit -m "feat(admin-onboarding): modelo AdministrationRequest (BR-123/127/134)"
```

---

### Task 3: `AdministrationApprovalService` (transacción de aprobación)

**Files:**
- Create: `app/services/administration_approval_service.rb`
- Test: `test/services/administration_approval_service_test.rb`

Reutiliza el patrón de `Admin::OnboardingReviewsController#approve_step3` y `IdentityTransferService.deactivate_prior_memberships!`.

- [ ] **Step 1: Escribir tests que fallan**

```ruby
# test/services/administration_approval_service_test.rb
require "test_helper"

class AdministrationApprovalServiceTest < ActiveSupport::TestCase
  setup do
    @staff = users(:artanis) # superadmin
  end

  test "aprobar junta existente crea identidad, member, boardmember y marca admin" do
    req = AdministrationRequest.create!(
      user: users(:urunis),
      neighborhood_association: neighborhood_associations(:manios_de_buin),
      organization_rut: neighborhood_associations(:manios_de_buin).rut,
      position: "presidente",
      first_name: "Ana", last_name: "Soto", run: "15111222-3", phone: "+56911112222",
      status: "pending"
    )

    assert_difference -> { Member.count } => 1, -> { BoardMember.count } => 1, -> { VerifiedIdentity.count } => 1 do
      AdministrationApprovalService.approve!(req, approved_by: @staff)
    end

    req.reload
    assert req.approved?
    assert_equal @staff, req.reviewed_by
    user = users(:urunis).reload
    assert user.admin?
    assert_equal neighborhood_associations(:manios_de_buin), user.neighborhood_association
    member = user.verified_identity.members.approved.find_by(neighborhood_association: neighborhood_associations(:manios_de_buin))
    assert member
    assert_equal "presidente", member.board_members.first.position
  end

  test "aprobar junta nueva la crea con el rut declarado" do
    req = AdministrationRequest.create!(
      user: users(:urunis),
      proposed_association_name: "Junta Nueva Los Robles",
      commune: communes(:commune_0_0_0),
      organization_rut: "86429665-3",
      position: "secretario",
      first_name: "Luis", last_name: "Vera", run: "14222333-1", phone: "+56911113333",
      status: "pending"
    )

    assert_difference -> { NeighborhoodAssociation.count } => 1 do
      AdministrationApprovalService.approve!(req, approved_by: @staff)
    end

    junta = NeighborhoodAssociation.find_by(name: "Junta Nueva Los Robles")
    assert_equal "86429665-3", junta.rut
    assert_equal junta, users(:urunis).reload.neighborhood_association
  end

  test "aprobar desactiva la membresia previa en OTRA junta (BR-137)" do
    identidad = verified_identities(:selendis_persona)
    otra = neighborhood_associations(:association_0)
    prev = Member.create!(verified_identity: identidad, neighborhood_association: otra, status: "approved")
    req = AdministrationRequest.create!(
      user: users(:selendis),
      neighborhood_association: neighborhood_associations(:manios_de_buin),
      organization_rut: neighborhood_associations(:manios_de_buin).rut,
      position: "tesorero",
      first_name: identidad.first_name, last_name: identidad.last_name,
      run: identidad.run, phone: "+56911114444",
      status: "pending"
    )

    AdministrationApprovalService.approve!(req, approved_by: @staff)

    assert_equal "inactive", prev.reload.status
  end
end
```

- [ ] **Step 2: Correr para ver fallar**

Run: `bin/rails test test/services/administration_approval_service_test.rb`
Expected: FAIL (servicio no existe). Ajusta RUN/RUT de los tests si el DV falla.

- [ ] **Step 3: Implementar el servicio**

```ruby
# app/services/administration_approval_service.rb
class AdministrationApprovalService
  # BR-128: aprobación transaccional. Todo o nada.
  def self.approve!(administration_request, approved_by:)
    new(administration_request, approved_by).approve!
  end

  def initialize(administration_request, approved_by)
    @req = administration_request
    @approved_by = approved_by
  end

  def approve!
    ActiveRecord::Base.transaction do
      junta = resolve_association!
      identity = resolve_identity!
      deactivate_prior_memberships!(identity, junta)
      member = ensure_member!(identity, junta)
      ensure_board_member!(member)
      @req.user.update!(admin: true, neighborhood_association: junta, verified_identity: identity)
      @req.update!(status: "approved", reviewed_by: @approved_by, reviewed_at: Time.current)
    end
    @req
  end

  private

  # BR-125: la junta nueva se crea recién al aprobar. Existente → se enlaza.
  def resolve_association!
    return @req.neighborhood_association if @req.neighborhood_association_id.present?

    NeighborhoodAssociation.create!(
      name: @req.proposed_association_name,
      commune: @req.commune,
      rut: @req.organization_rut
    )
  end

  # BR-129: reutiliza VerifiedIdentity por RUN (transferencia si es de otra cuenta).
  def resolve_identity!
    identity = VerifiedIdentity.find_or_initialize_by(run: @req.run)
    identity.assign_attributes(
      first_name: @req.first_name,
      last_name: @req.last_name,
      phone: @req.phone,
      email: @req.user.email
    )
    identity.save!

    if @req.identity_documents.attached? && !identity.identity_document.attached?
      identity.identity_document.attach(@req.identity_documents.first.blob)
    end
    @req.user.update!(verified_identity: identity)
    identity
  end

  # BR-137: desactiva membresías activas en OTRAS juntas; conserva la de esta junta.
  def deactivate_prior_memberships!(identity, junta)
    identity.members.approved.where.not(neighborhood_association_id: junta.id).find_each do |member|
      member.deactivate!(reason: I18n.t("members.deactivation.administration_onboarding"))
    end
  end

  def ensure_member!(identity, junta)
    member = identity.members.find_or_initialize_by(neighborhood_association: junta)
    member.assign_attributes(
      status: "approved",
      requested_by: @req.user,
      approved_by: @approved_by,
      approved_at: Time.current
    )
    member.save!
    member
  end

  # BR-128: directiva con el cargo declarado.
  def ensure_board_member!(member)
    BoardMember.create!(
      neighborhood_association: member.neighborhood_association,
      member: member,
      position: @req.position,
      start_date: Date.current,
      active: true
    )
  end
end
```

- [ ] **Step 4: i18n del motivo de desactivación**

En `config/locales/es.yml`, bajo `members: deactivation:` agrega:
```yaml
    administration_onboarding: Transferencia de identidad por aprobación de administración de otra junta
```

- [ ] **Step 5: Correr tests para ver pasar**

Run: `bin/rails test test/services/administration_approval_service_test.rb`
Expected: PASS. Ajusta RUN/RUT si el DV falla.

- [ ] **Step 6: Commit**

```bash
git add app/services/administration_approval_service.rb test/services/administration_approval_service_test.rb config/locales/es.yml
git commit -m "feat(admin-onboarding): AdministrationApprovalService (BR-128/129/137)"
```

---

### Task 4: Rutas + controlador del panel + guardas + navegación

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/panel/administration_requests_controller.rb`
- Modify: `app/views/layouts/panel.html.erb` (link en sidebar)
- Modify: `config/locales/es.yml`
- Test: `test/controllers/panel/administration_requests_controller_test.rb`

- [ ] **Step 1: Rutas**

En `config/routes.rb`, dentro de `namespace :panel do ... end`, agrega:
```ruby
    resource :administration_request, only: [:new, :create, :show] do
      delete :cancel, on: :collection
    end
```

- [ ] **Step 2: Escribir tests de controller que fallan**

```ruby
# test/controllers/panel/administration_requests_controller_test.rb
require "test_helper"

module Panel
  class AdministrationRequestsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    test "new muestra el formulario para un usuario no admin" do
      sign_in users(:urunis)
      get new_panel_administration_request_url
      assert_response :success
      assert_select "select[name='administration_request[neighborhood_association_id]']"
    end

    test "un admin existente no puede solicitar (BR-136)" do
      sign_in users(:selendis) # admin: true
      get new_panel_administration_request_url
      assert_redirected_to panel_root_url
    end

    test "create con datos validos crea la solicitud en pending" do
      sign_in users(:urunis)
      assert_difference "AdministrationRequest.count", 1 do
        post panel_administration_request_url, params: {administration_request: {
          neighborhood_association_id: neighborhood_associations(:manios_de_buin).id,
          organization_rut: neighborhood_associations(:manios_de_buin).rut,
          position: "presidente",
          first_name: "Ana", last_name: "Soto", run: "15111222-3", phone: "987654321"
        }}
      end
      assert_equal "pending", AdministrationRequest.last.status
      assert_redirected_to panel_administration_request_url
    end
  end
end
```

- [ ] **Step 3: Correr para ver fallar**

Run: `bin/rails test test/controllers/panel/administration_requests_controller_test.rb`
Expected: FAIL (controlador no existe).

- [ ] **Step 4: Implementar el controlador**

```ruby
# app/controllers/panel/administration_requests_controller.rb
module Panel
  class AdministrationRequestsController < Panel::ApplicationController
    before_action :redirect_if_admin, only: %i[new create]
    before_action :redirect_if_active_request, only: %i[new create]

    def show
      @administration_request = current_user.administration_requests.order(created_at: :desc).first
      redirect_to new_panel_administration_request_path unless @administration_request
    end

    def new
      @administration_request = AdministrationRequest.new
      @cascading_data = build_cascading_data
    end

    def create
      @administration_request = AdministrationRequest.new(administration_request_params)
      @administration_request.user = current_user
      @administration_request.status = "pending"

      if @administration_request.save
        notify_existing_admins
        AdministrationRequestMailer.submitted(@administration_request).deliver_later
        redirect_to panel_administration_request_path, notice: I18n.t("panel.administration_requests.flash.submitted")
      else
        @cascading_data = build_cascading_data
        render :new, status: :unprocessable_content
      end
    end

    def cancel
      req = current_user.administration_requests.pending.first
      req&.cancel!
      redirect_to new_panel_administration_request_path, notice: I18n.t("panel.administration_requests.flash.cancelled")
    end

    private

    def administration_request_params
      params.require(:administration_request).permit(
        :neighborhood_association_id, :region_id, :commune_id, :proposed_association_name,
        :organization_rut, :position, :first_name, :last_name, :run, :phone,
        :directiva_validity_document, identity_documents: []
      )
    end

    # BR-136: un usuario solo administra una junta; si ya es admin, no puede solicitar otra.
    def redirect_if_admin
      redirect_to panel_root_path, alert: I18n.t("panel.administration_requests.flash.already_admin") if current_user.admin?
    end

    # BR-134: una solicitud activa a la vez.
    def redirect_if_active_request
      if current_user.administration_requests.active.exists?
        redirect_to panel_administration_request_path
      end
    end

    # BR-130: avisar a los admins vigentes de la junta objetivo.
    def notify_existing_admins
      junta = @administration_request.neighborhood_association
      return unless junta

      User.where(admin: true, neighborhood_association_id: junta.id).find_each do |admin|
        AdministrationRequestMailer.notify_existing_admin(admin, @administration_request).deliver_later
      end
    end

    # Mismo patrón que Panel::OnboardingController#build_cascading_data.
    def build_cascading_data
      associations_by_commune = NeighborhoodAssociation.active.where.not(commune_id: nil).order(:name).group_by(&:commune_id)
      communes = Commune.where(id: associations_by_commune.keys).order(:name).includes(:region)
      communes.group_by(&:region).map do |region, region_communes|
        {
          id: region.id, name: region.name,
          communes: region_communes.sort_by(&:name).map do |commune|
            {id: commune.id, name: commune.name,
             associations: (associations_by_commune[commune.id] || []).map { |a| {id: a.id, name: a.name} }}
          end
        }
      end.sort_by { |r| r[:name] }
    end
  end
end
```

Nota: agrega `has_many :administration_requests` a `app/models/user.rb` (junto a las otras asociaciones `has_many` del User). Verifica que `Panel::ApplicationController` exista y su nombre; si el panel no usa un `Panel::ApplicationController`, hereda de `::ApplicationController` como los otros controladores de panel.

- [ ] **Step 5: Link en el sidebar del panel**

En `app/views/layouts/panel.html.erb`, tras el bloque de onboarding y antes de `Mis Cosas`, agrega (mostrar solo si el usuario NO es admin):
```erb
  <% unless current_user.admin? %>
    <% admin_req = current_user.administration_requests.order(created_at: :desc).first %>
    <li>
      <%= link_to((admin_req&.pending? || admin_req&.approved?) ? panel_administration_request_path : new_panel_administration_request_path, class: ("active" if controller_name == "administration_requests")) do %>
        <%= I18n.t("panel.administration_requests.sidebar") %>
        <% if admin_req.present? && !admin_req.draft? %>
          <%= status_badge(admin_req.status) %>
        <% end %>
      <% end %>
    </li>
  <% end %>
```

- [ ] **Step 6: i18n del panel**

En `config/locales/es.yml`, agrega bajo `panel:`:
```yaml
    administration_requests:
      sidebar: Administrar mi junta
      title: Solicitar administración de junta
      flash:
        submitted: Solicitud enviada. El equipo de Yuntapp la revisará.
        cancelled: Solicitud cancelada.
        already_admin: Ya administras una junta.
```

- [ ] **Step 7: Correr tests para ver pasar**

Run: `bin/rails test test/controllers/panel/administration_requests_controller_test.rb`
Expected: PASS (las vistas se crean en Task 5; si `new`/`show` fallan por falta de template, avanza a Task 5 y vuelve a correr). Si el test de `new` requiere la vista, impleméntala en Task 5 primero y reordena.

- [ ] **Step 8: Commit**

```bash
git add config/routes.rb app/controllers/panel/administration_requests_controller.rb app/models/user.rb app/views/layouts/panel.html.erb config/locales/es.yml test/controllers/panel/administration_requests_controller_test.rb
git commit -m "feat(admin-onboarding): rutas + controlador panel + nav (BR-130/134/136)"
```

---

### Task 5: Vistas del panel (formulario de página única + estado)

**Files:**
- Create: `app/views/panel/administration_requests/new.html.erb`
- Create: `app/views/panel/administration_requests/show.html.erb`
- Create: `app/javascript/controllers/administration_cascade_controller.js` (cascada client-side)
- Modify: `config/importmap.rb` no requiere cambios (Stimulus auto-registra por convención de nombre)

- [ ] **Step 1: Controlador Stimulus para la cascada + toggle "junta nueva"**

```javascript
// app/javascript/controllers/administration_cascade_controller.js
import { Controller } from "@hotwired/stimulus"

// Cascada región→comuna→junta con datos embebidos como JSON, más toggle a "crear nueva junta".
export default class extends Controller {
  static targets = ["region", "commune", "association", "newToggle", "existingWrap", "newWrap", "communeNew"]
  static values = { data: Array }

  connect() { this.populateRegions() }

  populateRegions() {
    this.fill(this.regionTarget, this.dataValue.map(r => [r.name, r.id]))
    this.regionChanged()
  }

  regionChanged() {
    const region = this.dataValue.find(r => r.id === parseInt(this.regionTarget.value))
    const communes = region ? region.communes : []
    this.fill(this.communeTarget, communes.map(c => [c.name, c.id]))
    if (this.hasCommuneNewTarget) this.fill(this.communeNewTarget, communes.map(c => [c.name, c.id]))
    this.communeChanged()
  }

  communeChanged() {
    const region = this.dataValue.find(r => r.id === parseInt(this.regionTarget.value))
    const commune = region ? region.communes.find(c => c.id === parseInt(this.communeTarget.value)) : null
    const associations = commune ? commune.associations : []
    this.fill(this.associationTarget, associations.map(a => [a.name, a.id]))
  }

  toggleNew() {
    const isNew = this.newToggleTarget.checked
    this.existingWrapTarget.classList.toggle("hidden", isNew)
    this.newWrapTarget.classList.toggle("hidden", !isNew)
  }

  fill(select, pairs) {
    const prompt = select.dataset.prompt || ""
    select.innerHTML = ""
    if (prompt) select.add(new Option(prompt, ""))
    pairs.forEach(([label, value]) => select.add(new Option(label, value)))
  }
}
```

- [ ] **Step 2: Vista `new` (formulario)**

```erb
<%# app/views/panel/administration_requests/new.html.erb %>
<div class="w-full max-w-xl">
  <h1 class="font-bold text-4xl my-4"><%= I18n.t("panel.administration_requests.title") %></h1>

  <%= form_with(model: @administration_request, url: panel_administration_request_path, method: :post, html: { novalidate: true }) do |form| %>
    <% if @administration_request.errors.any? %>
      <div class="alert alert-error mb-4"><%= @administration_request.errors.full_messages.to_sentence %></div>
    <% end %>

    <div data-controller="administration-cascade" data-administration-cascade-data-value="<%= @cascading_data.to_json %>" class="grid gap-4">
      <label class="floating-label">
        <%= form.select :region_id, [], {}, class: "select w-full", data: {administration_cascade_target: "region", action: "change->administration-cascade#regionChanged", prompt: I18n.t("panel.onboarding.step1.select_region")} %>
        <span><%= I18n.t("panel.onboarding.step1.region_label") %></span>
      </label>

      <label class="floating-label">
        <%= form.select :commune_id, [], {}, class: "select w-full", data: {administration_cascade_target: "commune", action: "change->administration-cascade#communeChanged", prompt: I18n.t("panel.onboarding.step1.select_commune")} %>
        <span><%= I18n.t("panel.onboarding.step1.commune_label") %></span>
      </label>

      <label class="label cursor-pointer justify-start gap-2">
        <%= check_box_tag "new_toggle", "1", false, data: {administration_cascade_target: "newToggle", action: "change->administration-cascade#toggleNew"}, class: "checkbox" %>
        <span><%= I18n.t("panel.administration_requests.new_junta_toggle") %></span>
      </label>

      <div data-administration-cascade-target="existingWrap">
        <label class="floating-label">
          <%= form.select :neighborhood_association_id, [], {}, class: "select w-full", data: {administration_cascade_target: "association", prompt: I18n.t("panel.onboarding.step1.select_association")} %>
          <span><%= I18n.t("panel.onboarding.step1.association_label") %></span>
        </label>
      </div>

      <div data-administration-cascade-target="newWrap" class="hidden grid gap-2">
        <%= form.text_field :proposed_association_name, class: "input w-full", placeholder: I18n.t("activerecord.attributes.administration_request.proposed_association_name") %>
      </div>
    </div>

    <div class="grid gap-4 mt-6">
      <%= form.text_field :organization_rut, class: "input w-full", placeholder: I18n.t("activerecord.attributes.administration_request.organization_rut") %>
      <%= form.select :position, BoardMember::POSITIONS.map { |p| [I18n.t("board_members.positions.#{p}", default: p.capitalize), p] }, {include_blank: I18n.t("activerecord.attributes.administration_request.position")}, class: "select w-full" %>
      <%= form.text_field :first_name, class: "input w-full", placeholder: I18n.t("activerecord.attributes.administration_request.first_name") %>
      <%= form.text_field :last_name, class: "input w-full", placeholder: I18n.t("activerecord.attributes.administration_request.last_name") %>
      <%= form.text_field :run, class: "input w-full", placeholder: I18n.t("activerecord.attributes.administration_request.run") %>
      <%= form.text_field :phone, class: "input w-full", placeholder: I18n.t("activerecord.attributes.administration_request.phone") %>

      <div>
        <%= form.label :directiva_validity_document, I18n.t("activerecord.attributes.administration_request.directiva_validity_document"), class: "label" %>
        <%= form.file_field :directiva_validity_document, class: "file-input w-full" %>
      </div>
      <div>
        <%= form.label :identity_documents, I18n.t("activerecord.attributes.administration_request.identity_documents"), class: "label" %>
        <%= form.file_field :identity_documents, multiple: true, class: "file-input w-full" %>
      </div>
    </div>

    <%= form.submit I18n.t("panel.administration_requests.submit"), class: "btn btn-success mt-6" %>
  <% end %>
</div>
```

- [ ] **Step 3: Vista `show` (estado)**

```erb
<%# app/views/panel/administration_requests/show.html.erb %>
<div class="w-full max-w-xl">
  <h1 class="font-bold text-4xl my-4"><%= I18n.t("panel.administration_requests.status_title") %></h1>

  <div class="card bg-base-100 shadow border border-base-content/5">
    <div class="card-body">
      <div class="flex items-center justify-between">
        <span class="font-bold text-lg"><%= @administration_request.target_association_label %></span>
        <%= status_badge(@administration_request.status) %>
      </div>
      <p class="text-base-content/60"><%= I18n.t("board_members.positions.#{@administration_request.position}", default: @administration_request.position&.capitalize) %></p>

      <% if @administration_request.rejected? && @administration_request.rejection_reason.present? %>
        <div class="alert alert-error mt-2"><%= @administration_request.rejection_reason %></div>
      <% end %>

      <% if @administration_request.pending? %>
        <%= button_to I18n.t("panel.administration_requests.cancel"), cancel_panel_administration_request_path, method: :delete, class: "btn btn-warning btn-sm mt-4", data: {turbo_confirm: I18n.t("panel.administration_requests.cancel_confirm")} %>
      <% end %>
    </div>
  </div>
</div>
```

- [ ] **Step 4: i18n de atributos + labels**

En `config/locales/es.yml`: agrega bajo `activerecord: attributes:` la clave `administration_request:` con `proposed_association_name`, `organization_rut`, `position`, `first_name`, `last_name`, `run`, `phone`, `directiva_validity_document`, `identity_documents`. Y bajo `panel: administration_requests:` agrega `new_junta_toggle`, `submit`, `status_title`, `cancel`, `cancel_confirm`. Verifica si `board_members.positions.*` existe; si no, agrégalo (`presidente`, `secretario`, `tesorero`, `director`).

- [ ] **Step 5: Verificación manual + tests de controller**

Run: `bin/rails test test/controllers/panel/administration_requests_controller_test.rb`
Expected: PASS (ahora que las vistas existen).
Run: `bundle exec erb_lint app/views/panel/administration_requests/new.html.erb app/views/panel/administration_requests/show.html.erb`
Expected: sin ofensas.

- [ ] **Step 6: Commit**

```bash
git add app/views/panel/administration_requests app/javascript/controllers/administration_cascade_controller.js config/locales/es.yml
git commit -m "feat(admin-onboarding): vistas del panel (formulario + estado)"
```

---

### Task 6: Revisión del staff (namespace superadmin)

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/superadmin/administration_requests_controller.rb`
- Create: `app/views/superadmin/administration_requests/index.html.erb`
- Create: `app/views/superadmin/administration_requests/show.html.erb`
- Modify: `config/locales/es.yml`
- Test: `test/controllers/superadmin/administration_requests_controller_test.rb`

- [ ] **Step 1: Rutas**

En `config/routes.rb`, dentro de `namespace :superadmin do ... end`:
```ruby
    resources :administration_requests, only: %i[index show] do
      member do
        patch :approve
        patch :reject
      end
    end
```

- [ ] **Step 2: Tests de controller que fallan**

```ruby
# test/controllers/superadmin/administration_requests_controller_test.rb
require "test_helper"

module Superadmin
  class AdministrationRequestsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup { sign_in users(:artanis) } # superadmin

    test "index lista solicitudes" do
      get superadmin_administration_requests_url
      assert_response :success
    end

    test "approve aprueba y crea admin" do
      req = administration_requests(:pending_manios)
      patch approve_superadmin_administration_request_url(req)
      assert req.reload.approved?
      assert req.user.reload.admin?
    end

    test "reject exige motivo y marca rejected" do
      req = administration_requests(:pending_manios)
      patch reject_superadmin_administration_request_url(req), params: {administration_request: {rejection_reason: "Documentación insuficiente"}}
      assert req.reload.rejected?
      assert_equal "Documentación insuficiente", req.rejection_reason
    end

    test "un usuario no superadmin no accede" do
      sign_out users(:artanis)
      sign_in users(:selendis) # admin, no superadmin
      get superadmin_administration_requests_url
      assert_redirected_to root_url
    end
  end
end
```

- [ ] **Step 3: Correr para ver fallar**

Run: `bin/rails test test/controllers/superadmin/administration_requests_controller_test.rb`
Expected: FAIL.

- [ ] **Step 4: Implementar el controlador**

```ruby
# app/controllers/superadmin/administration_requests_controller.rb
module Superadmin
  class AdministrationRequestsController < Superadmin::ApplicationController
    include Pagy::Method

    before_action :set_administration_request, only: %i[show approve reject]

    def index
      scope = AdministrationRequest.includes(:user, :neighborhood_association).order(created_at: :desc)
      @pagy, @administration_requests = pagy(scope)
    end

    def show
    end

    # BR-122/BR-128: solo el staff aprueba; la transacción crea junta/identidad/member/directiva.
    def approve
      AdministrationApprovalService.approve!(@administration_request, approved_by: current_user)
      AdministrationRequestMailer.approved(@administration_request).deliver_later
      redirect_to superadmin_administration_request_path(@administration_request),
        notice: I18n.t("superadmin.administration_requests.flash.approved"), status: :see_other
    rescue ActiveRecord::RecordInvalid => e
      redirect_to superadmin_administration_request_path(@administration_request),
        alert: e.message, status: :see_other
    end

    # BR-131: rechazo con motivo obligatorio.
    def reject
      reason = params.dig(:administration_request, :rejection_reason).to_s.strip
      if reason.blank?
        redirect_to superadmin_administration_request_path(@administration_request),
          alert: I18n.t("superadmin.administration_requests.flash.reason_required"), status: :see_other
        return
      end
      @administration_request.update!(status: "rejected", reviewed_by: current_user, reviewed_at: Time.current, rejection_reason: reason)
      AdministrationRequestMailer.rejected(@administration_request).deliver_later
      redirect_to superadmin_administration_request_path(@administration_request),
        notice: I18n.t("superadmin.administration_requests.flash.rejected"), status: :see_other
    end

    private

    def set_administration_request
      @administration_request = AdministrationRequest.find(params[:id])
    end
  end
end
```

- [ ] **Step 5: Vistas index + show**

`index.html.erb`: tabla espejando `superadmin/neighborhood_associations/index` con columnas: solicitante (`request.user.email`), junta objetivo (`request.target_association_label`), cargo, estado (`status_badge`), y link a `show`. Paginación con `@pagy.series_nav`.

```erb
<%# app/views/superadmin/administration_requests/index.html.erb %>
<div class="w-full">
  <h1 class="font-bold text-4xl my-4"><%= I18n.t("superadmin.administration_requests.index.title") %></h1>
  <div class="my-4"><%== @pagy.series_nav %></div>
  <div class="overflow-x-auto rounded-box border border-base-content/5 bg-base-100">
    <table class="table table-zebra">
      <thead>
        <tr>
          <th><%= I18n.t("activerecord.attributes.administration_request.applicant") %></th>
          <th><%= I18n.t("activerecord.attributes.administration_request.target") %></th>
          <th><%= I18n.t("activerecord.attributes.administration_request.position") %></th>
          <th><%= I18n.t("shared.table.status") %></th>
          <th><%= I18n.t("shared.table.actions") %></th>
        </tr>
      </thead>
      <tbody>
        <% @administration_requests.each do |req| %>
          <tr>
            <td><%= req.user.email %></td>
            <td><%= req.target_association_label %></td>
            <td><%= I18n.t("board_members.positions.#{req.position}", default: req.position) %></td>
            <td><%= status_badge(req.status) %></td>
            <td><%= link_to I18n.t("shared.table.view"), superadmin_administration_request_path(req), class: "btn btn-sm" %></td>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>
  <div class="my-4"><%== @pagy.series_nav %></div>
</div>
```

`show.html.erb`: muestra todos los datos (solicitante, junta objetivo o "nueva: nombre + comuna", RUT, cargo, datos personales), enlaces de descarga de `directiva_validity_document` e `identity_documents`, una **advertencia si la junta ya tiene admin activo** (BR-130/BR-140) y si el RUN ya existe verificado (BR-129), y dos formularios: aprobar (`button_to` PATCH approve) y rechazar (form con `rejection_reason` + PATCH reject). Ejemplo del bloque de acciones:

```erb
<%# fragmento de app/views/superadmin/administration_requests/show.html.erb %>
<% junta = @administration_request.neighborhood_association %>
<% if junta && User.exists?(admin: true, neighborhood_association_id: junta.id) %>
  <div class="alert alert-warning">
    <%= I18n.t("superadmin.administration_requests.warn_existing_admin") %>
  </div>
<% end %>
<% if @administration_request.run.present? && VerifiedIdentity.exists?(run: @administration_request.run) %>
  <div class="alert alert-info">
    <%= I18n.t("superadmin.administration_requests.warn_duplicate_run") %>
  </div>
<% end %>

<% if @administration_request.pending? %>
  <div class="flex gap-2 mt-4">
    <%= button_to I18n.t("superadmin.administration_requests.approve"), approve_superadmin_administration_request_path(@administration_request), method: :patch, class: "btn btn-success", data: {turbo_confirm: I18n.t("superadmin.administration_requests.approve_confirm")} %>
  </div>
  <%= form_with url: reject_superadmin_administration_request_path(@administration_request), method: :patch, class: "mt-4 grid gap-2" do |f| %>
    <%= f.text_area "administration_request[rejection_reason]", class: "textarea w-full", placeholder: I18n.t("activerecord.attributes.administration_request.rejection_reason") %>
    <%= f.submit I18n.t("superadmin.administration_requests.reject"), class: "btn btn-error w-fit" %>
  <% end %>
<% end %>
```

- [ ] **Step 6: i18n superadmin**

En `config/locales/es.yml`, agrega bajo `superadmin:` la clave `administration_requests:` con `index.title`, `flash.approved`, `flash.rejected`, `flash.reason_required`, `approve`, `approve_confirm`, `reject`, `warn_existing_admin`, `warn_duplicate_run`. Y bajo `activerecord.attributes.administration_request` agrega `applicant`, `target`, `rejection_reason`. Verifica `shared.table.status/view` (si no existen, agrégalos).

- [ ] **Step 7: Link en el sidebar superadmin**

En el layout/sidebar de superadmin (busca `app/views/layouts/superadmin.html.erb` o su partial de nav), agrega un link a `superadmin_administration_requests_path` junto a los otros recursos (onboarding_requests, users, etc.).

- [ ] **Step 8: Correr tests para ver pasar**

Run: `bin/rails test test/controllers/superadmin/administration_requests_controller_test.rb`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add config/routes.rb app/controllers/superadmin/administration_requests_controller.rb app/views/superadmin/administration_requests config/locales/es.yml app/views/layouts/superadmin.html.erb test/controllers/superadmin/administration_requests_controller_test.rb
git commit -m "feat(admin-onboarding): revisión y aprobación del staff (BR-122/130/131)"
```

---

### Task 7: Notificaciones (mailer + digest recurrente)

**Files:**
- Create: `app/mailers/administration_request_mailer.rb`
- Create: `app/views/administration_request_mailer/submitted.html.erb`, `approved.html.erb`, `rejected.html.erb`, `notify_existing_admin.html.erb`
- Create: `app/jobs/administration_reminders_job.rb`
- Modify: `config/recurring.yml`
- Modify: `config/locales/es.yml`
- Test: `test/mailers/administration_request_mailer_test.rb`, `test/jobs/administration_reminders_job_test.rb`

- [ ] **Step 1: Mailer**

```ruby
# app/mailers/administration_request_mailer.rb
class AdministrationRequestMailer < ApplicationMailer
  def submitted(administration_request)
    @request = administration_request
    return if @request.user.email.blank?
    mail to: @request.user.email, subject: t(".subject")
  end

  def approved(administration_request)
    @request = administration_request
    return if @request.user.email.blank?
    mail to: @request.user.email, subject: t(".subject")
  end

  def rejected(administration_request)
    @request = administration_request
    return if @request.user.email.blank?
    mail to: @request.user.email, subject: t(".subject")
  end

  # BR-130: aviso a un admin vigente de la junta objetivo.
  def notify_existing_admin(admin, administration_request)
    @request = administration_request
    @admin = admin
    return if admin.email.blank?
    mail to: admin.email, subject: t(".subject")
  end
end
```

- [ ] **Step 2: Vistas del mailer**

Crea las 4 vistas `.html.erb` en `app/views/administration_request_mailer/` con un párrafo breve cada una usando `t("....")`. Ejemplo `submitted.html.erb`:
```erb
<p><%= t(".body", junta: @request.target_association_label) %></p>
<p><%= t(".signature") %></p>
```
(Repite el patrón para `approved`, `rejected` —incluye `@request.rejection_reason`— y `notify_existing_admin` —menciona la junta y que puede objetar.)

- [ ] **Step 3: Job de digest para el staff (BR-133)**

```ruby
# app/jobs/administration_reminders_job.rb
class AdministrationRemindersJob < ApplicationJob
  queue_as :default

  def perform
    pending = AdministrationRequest.pending.to_a
    return if pending.empty?

    User.where(superadmin: true).find_each do |staff|
      AdministrationRequestMailer.staff_digest(staff, pending).deliver_later if staff.email.present?
    end
  end
end
```
Y agrega el método `staff_digest(staff, requests)` al mailer (espejo de `submitted`), con su vista `staff_digest.html.erb` que lista `requests.each`.

- [ ] **Step 4: Recurring config**

En `config/recurring.yml`, agrega (junto a `onboarding_reminders`):
```yaml
administration_reminders:
  class: AdministrationRemindersJob
  schedule: every day at 8am
```

- [ ] **Step 5: Tests del mailer y del job**

```ruby
# test/mailers/administration_request_mailer_test.rb
require "test_helper"

class AdministrationRequestMailerTest < ActionMailer::TestCase
  test "submitted se envía al solicitante" do
    req = administration_requests(:pending_manios)
    mail = AdministrationRequestMailer.submitted(req)
    assert_equal [req.user.email], mail.to
    assert mail.subject.present?
  end

  test "approved se envía al solicitante" do
    req = administration_requests(:pending_manios)
    mail = AdministrationRequestMailer.approved(req)
    assert_equal [req.user.email], mail.to
  end
end
```

```ruby
# test/jobs/administration_reminders_job_test.rb
require "test_helper"

class AdministrationRemindersJobTest < ActiveJob::TestCase
  test "encola un digest por cada superadmin cuando hay pendientes" do
    assert_enqueued_emails 1 do # ajustar al número de superadmins fixture con email
      AdministrationRemindersJob.perform_now
    end
  end
end
```
Nota: ajusta el número esperado según cuántos `users` fixture tengan `superadmin: true` y email.

- [ ] **Step 6: i18n del mailer**

Agrega en `config/locales/es.yml` bajo `administration_request_mailer:` las claves `submitted/approved/rejected/notify_existing_admin/staff_digest` con `subject`, `body`, `signature` (patrón espejo de `onboarding_reminder_mailer`).

- [ ] **Step 7: Correr tests**

Run: `bin/rails test test/mailers/administration_request_mailer_test.rb test/jobs/administration_reminders_job_test.rb`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add app/mailers/administration_request_mailer.rb app/views/administration_request_mailer app/jobs/administration_reminders_job.rb config/recurring.yml config/locales/es.yml test/mailers/administration_request_mailer_test.rb test/jobs/administration_reminders_job_test.rb
git commit -m "feat(admin-onboarding): notificaciones + digest al staff (BR-130/133)"
```

---

### Task 8: Verificación integral + CLAUDE.md

**Files:**
- Modify: `CLAUDE.md` (UC-008 + BR-119…140)

- [ ] **Step 1: Suite completa**

Run: `bin/rails test`
Expected: 0 failures, 0 errors.

- [ ] **Step 2: Linters + zeitwerk**

Run: `bin/standardrb && bundle exec erb_lint --lint-all && bin/rails zeitwerk:check`
Expected: sin ofensas; zeitwerk OK.

- [ ] **Step 3: Llevar reglas a CLAUDE.md**

Agrega a la tabla de reglas de negocio de `CLAUDE.md` las filas **BR-119, BR-120, BR-121** (RUT, ya implementadas) y **BR-122…140** (administración), copiando el texto desde `docs/superpowers/specs/2026-07-27-onboarding-administracion-design.md`. Agrega **UC-008** a la sección de Casos de Uso. Agrega la categoría **Administración** a la lista de categorías. Marca las reglas de administración como implementadas por este plan.

- [ ] **Step 4: Commit final**

```bash
git add -A
git commit -m "docs: UC-008 + BR-119..140 en CLAUDE.md; verificación integral"
```

---

## Self-Review (cobertura del spec)

- BR-122 (solo staff aprueba) → Task 6 (namespace superadmin, `ensure_superadmin!`).
- BR-123 (cargo + vigencia + rut obligatorio) → Task 2 (validaciones on pending) + Task 5 (form).
- BR-124 (email confirmado) → precondición Devise `confirmable` (ya global); el panel exige login.
- BR-125 (junta nueva se crea al aprobar) → Task 3 (`resolve_association!`).
- BR-126 (estados) → Task 2 (STATUSES, submit!/cancel!).
- BR-127 (normalizaciones) → Task 2.
- BR-128 (aprobación transaccional) → Task 3.
- BR-129 (RUN duplicado) → Task 3 (`resolve_identity!` find_or_initialize por run).
- BR-130 (avisar admins vigentes) → Task 4 (`notify_existing_admins`) + Task 6 (warning) + Task 7 (mailer).
- BR-131 (rechazo con motivo) → Task 6 (`reject`).
- BR-132 (multi-tenant; member sin residency) → Task 3 (no se crea Residency).
- BR-133 (digest staff + notif solicitante) → Task 7.
- BR-134 (una solicitud activa) → Task 2 (`only_one_active_per_user`) + Task 4 (guard).
- BR-135 (junta nueva sin pricing) → sin acción de código (la junta nace sin pricing; el admin lo define luego). Documentar en CLAUDE.md.
- BR-136 (una junta por admin) → Task 4 (`redirect_if_admin`).
- BR-137 (consecuencia acoplamiento) → Task 3 (`deactivate_prior_memberships!`).
- BR-138 (acceso no caduca) → sin acción (no se implementa expiración). Documentar.
- BR-139/BR-140 (junta/cargo duplicados → advertencia) → Task 6 (warnings en `show`).

## Notas de implementación

- **RUN/RUT de fixtures y tests**: todos deben tener DV válido (módulo 11) — usa `valid_test_rut(n)` (helper existente) para RUTs de organización de prueba y verifica los RUN a mano.
- **`normalize_phone`**: confirma el patrón exacto contra `VerifiedIdentity`/`PhoneValidator` y reutilízalo.
- **Discrepancia de RUT en junta existente** (BR-119): la v1 usa el RUT ya constituido de la junta existente y no lo cambia; el `organization_rut` de la solicitud aplica solo a juntas nuevas. Si el staff detecta discrepancia, lo resuelve fuera de flujo. Documentar como decisión.
- **Draft/duplicar (BR-131)**: la UI v1 crea directo en `pending`; "duplicar solicitud rechazada" queda para una iteración futura (el modelo ya soporta `draft`).
