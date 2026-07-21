require "prawn"
require "stringio"

# Crea (o reconstruye) una junta de vecinos de DEMO con datos ficticios
# coherentes, para ejercitar los flujos de revisión en cualquier entorno:
#
#   - Socios aprobados con grupo familiar, algunos con residentes dependientes.
#   - Onboardings PENDIENTES de aprobar (admin/onboarding_reviews).
#   - Dependientes PENDIENTES de revisar (admin/dependent_reviews).
#   - Un usuario admin de la junta y un precio de certificado vigente.
#
# Todo cuelga de la junta ASSOCIATION_NAME y usa emails con el patrón demo,
# de modo que `reset!` puede limpiarlo sin tocar datos reales. `call` primero
# limpia y luego reconstruye, por lo que es idempotente por construcción.
#
# Uso: DemoJuntaSeeder.call  /  DemoJuntaSeeder.reset!
class DemoJuntaSeeder
  ASSOCIATION_NAME = "[DEMO] Junta de Vecinos Los Aromos"
  EMAIL_LIKE = "gfiguero+demo-%@gmail.com"
  DEMO_PASSWORD = "demo1234"
  COMMUNE_NAME = "Ñuñoa"

  DELEGATIONS = ["Sector Norte", "Sector Sur", "Sector Oriente", "Villa Los Aromos"].freeze
  STREETS = ["Los Aromos", "Av. Grecia", "José Domingo Cañas", "Simón Bolívar",
    "Los Alerces", "Manuel Montt", "Pedro de Valdivia", "Dublé Almeyda"].freeze
  FIRST_NAMES = %w[María José Juan Rosa Pedro Carmen Luis Ana Carlos Francisca
    Jorge Marta Diego Valentina Felipe Camila Andrés Javiera Sebastián Daniela
    Ignacio Constanza Matías Antonia Rodrigo Paula Cristóbal Fernanda].freeze
  LAST_NAMES = %w[González Muñoz Rojas Díaz Pérez Soto Contreras Silva Martínez
    Sepúlveda Morales Rodríguez López Fuentes Hernández Torres Araya Flores
    Espinoza Valenzuela Castillo Tapia Reyes Gutiérrez Vergara].freeze
  DEPENDENT_FIRST_NAMES = %w[Benjamín Emilia Agustín Florencia Vicente Isidora
    Tomás Josefa Maximiliano Amanda].freeze

  APPROVED_HOUSEHOLDS = 15
  PENDING_ONBOARDINGS = 8
  PENDING_DEPENDENTS = 4

  def self.call = new.call

  def self.reset! = new.reset!

  def initialize
    @seq = 0
  end

  def call
    ChileGeographySeeder.call # garantiza que exista la geografía (comunas)
    ActiveRecord::Base.transaction do
      destroy_demo_data
      @commune = Commune.find_by!(name: COMMUNE_NAME)
      @association = NeighborhoodAssociation.create!(name: ASSOCIATION_NAME, commune: @commune)
      @admin = create_user("admin", admin: true, association: @association)
      CertificatePricing.create!(neighborhood_association: @association, price: 2000,
        created_by: @admin, effective_from: Time.current)
      @delegations = DELEGATIONS.map.with_index do |name, i|
        @association.neighborhood_delegations.create!(name: name)
      end
      APPROVED_HOUSEHOLDS.times { |i| create_approved_household(i) }
      PENDING_ONBOARDINGS.times { |i| create_pending_onboarding(i) }
      create_pending_dependents
    end
    summary
  end

  def reset!
    ActiveRecord::Base.transaction { destroy_demo_data }
    {association: ASSOCIATION_NAME, status: "eliminada"}
  end

  private

  # --- Construcción -------------------------------------------------------

  # Socio aprobado con su grupo familiar. Replica la transacción de
  # Admin::OnboardingReviewsController#approve_step3.
  def create_approved_household(index)
    delegation = @delegations[index % @delegations.size]
    user = create_user("h#{index}")
    identity = build_identity(user.email)
    residence = build_residence(delegation)
    household = HouseholdUnit.create!(neighborhood_delegation: delegation, commune: @commune,
      number: residence.number, street_name: residence.street_name, verified_residence: residence)
    family_group = FamilyGroup.create!(household_unit: household)

    user.update!(verified_identity: identity, neighborhood_association: @association)
    Residency.create!(verified_identity: identity, verified_residence: residence,
      household_unit: household, family_group: family_group, household_admin: true, status: "approved")
    Member.create!(verified_identity: identity, neighborhood_association: @association,
      status: "approved", requested_by: user, approved_by: @admin, approved_at: Time.current)

    # Cada tercer hogar suma un residente dependiente ya aprobado.
    create_approved_dependent(family_group, household, residence) if (index % 3).zero?
  end

  def create_approved_dependent(family_group, household, residence)
    identity = build_identity(nil, dependent: true)
    Residency.create!(verified_identity: identity, verified_residence: residence,
      household_unit: household, family_group: family_group, household_admin: false, status: "approved")
    Member.create!(verified_identity: identity, neighborhood_association: @association,
      status: "approved", dependent: true, approved_by: @admin, approved_at: Time.current)
  end

  # Onboarding pendiente de aprobar por el admin.
  def create_pending_onboarding(index)
    user = create_user("pending#{index}")
    onboarding = OnboardingRequest.create!(user: user, neighborhood_association: @association,
      region: @commune.region, commune: @commune, status: "pending", terms_accepted_at: Time.current)
    ivr = IdentityVerificationRequest.create!(onboarding_request: onboarding, status: "pending",
      first_name: FIRST_NAMES.sample, last_name: LAST_NAMES.sample, run: next_run, phone: next_phone)
    ivr.identity_documents.attach(placeholder("carnet"))
    delegation = @delegations[index % @delegations.size]
    rvr = ResidenceVerificationRequest.create!(onboarding_request: onboarding, user: user,
      neighborhood_association: @association, commune: @commune, status: "pending",
      neighborhood_delegation: delegation, number: (100 + index).to_s, manual_address: false)
    rvr.residence_documents.attach(placeholder("domicilio"))
  end

  # Dependientes pendientes de revisar, colgados de grupos familiares aprobados.
  def create_pending_dependents
    family_groups = FamilyGroup.where(household_unit: HouseholdUnit.where(neighborhood_delegation: @delegations)).limit(PENDING_DEPENDENTS)
    family_groups.each_with_index do |fg, i|
      admin_residency = fg.residencies.find_by(household_admin: true)
      requested_by = User.find_by(verified_identity_id: admin_residency&.verified_identity_id)
      ivr = IdentityVerificationRequest.create!(status: "pending", dependent: true,
        family_group: fg, requested_by: requested_by || @admin, neighborhood_association: @association,
        first_name: DEPENDENT_FIRST_NAMES[i % DEPENDENT_FIRST_NAMES.size], last_name: LAST_NAMES.sample, run: next_run)
      ivr.identity_documents.attach(placeholder("carnet_menor"))
    end
  end

  # --- Helpers de datos ---------------------------------------------------

  def build_identity(email, dependent: false)
    VerifiedIdentity.create!(first_name: FIRST_NAMES.sample,
      last_name: "#{LAST_NAMES.sample} #{LAST_NAMES.sample}", run: next_run,
      phone: dependent ? nil : next_phone, email: email)
  end

  def build_residence(delegation)
    VerifiedResidence.create!(neighborhood_association: @association, neighborhood_delegation: delegation,
      commune: @commune, street_name: STREETS.sample, number: rand(100..2000).to_s, manual_address: false)
  end

  def create_user(tag, admin: false, association: nil)
    User.create!(email: "gfiguero+demo-#{tag}@gmail.com", password: DEMO_PASSWORD,
      password_confirmation: DEMO_PASSWORD, confirmed_at: Time.current,
      admin: admin, neighborhood_association: association)
  end

  # RUN válido y único (dígito verificador módulo 11). Determinístico por índice.
  def next_run
    @seq += 1
    body = (30_000_000 + @seq).to_s
    "#{body}-#{run_dv(body)}"
  end

  def run_dv(body)
    sum = 0
    multiplier = 2
    body.reverse.each_char do |char|
      sum += char.to_i * multiplier
      multiplier = (multiplier == 7) ? 2 : multiplier + 1
    end
    remainder = 11 - (sum % 11)
    case remainder
    when 11 then "0"
    when 10 then "K"
    else remainder.to_s
    end
  end

  def next_phone
    @seq += 1
    "+569#{format("%08d", 40_000_000 + @seq)}"
  end

  def placeholder(label)
    pdf = Prawn::Document.new
    pdf.text "DOCUMENTO DE PRUEBA — #{label.upcase}", size: 18
    pdf.text "Junta de vecinos de demostración. No es un documento real."
    {io: StringIO.new(pdf.render), filename: "demo_#{label}.pdf", content_type: "application/pdf"}
  end

  # --- Limpieza -----------------------------------------------------------

  # Borra en orden hijo→padre para respetar las foreign keys de SQLite.
  def destroy_demo_data
    demo_users = User.where("email LIKE ?", EMAIL_LIKE)
    assoc = NeighborhoodAssociation.find_by(name: ASSOCIATION_NAME)
    onboarding_ids = OnboardingRequest.where(user_id: demo_users.ids).ids

    if assoc
      deleg_ids = assoc.neighborhood_delegations.ids
      hu_ids = HouseholdUnit.where(neighborhood_delegation_id: deleg_ids).ids
      vres_ids = VerifiedResidence.where(neighborhood_association_id: assoc.id).ids
      vi_ids = (Member.where(neighborhood_association_id: assoc.id).pluck(:verified_identity_id) +
        demo_users.pluck(:verified_identity_id)).compact.uniq
      ivr_ids = (IdentityVerificationRequest.where(onboarding_request_id: onboarding_ids).ids +
        IdentityVerificationRequest.where(neighborhood_association_id: assoc.id).ids +
        VerifiedIdentity.where(id: vi_ids).pluck(:identity_verification_request_id).compact).uniq

      purge_attachments(IdentityVerificationRequest.where(id: ivr_ids))
      purge_attachments(VerifiedResidence.where(id: vres_ids))
      purge_attachments(VerifiedIdentity.where(id: vi_ids))

      Residency.where(household_unit_id: hu_ids).delete_all
      Member.where(neighborhood_association_id: assoc.id).delete_all
      # IVR antes que FamilyGroup y OnboardingRequest: los referencia (family_group_id / onboarding_request_id).
      IdentityVerificationRequest.where(id: ivr_ids).delete_all
      FamilyGroup.where(household_unit_id: hu_ids).delete_all
      ResidenceVerificationRequest.where(onboarding_request_id: onboarding_ids).delete_all
      OnboardingRequest.where(id: onboarding_ids).delete_all
      demo_users.update_all(verified_identity_id: nil)
      VerifiedIdentity.where(id: vi_ids).delete_all
      HouseholdUnit.where(id: hu_ids).delete_all # referencia verified_residence: antes que VerifiedResidence
      VerifiedResidence.where(id: vres_ids).delete_all
      CertificatePricing.where(neighborhood_association_id: assoc.id).delete_all
      NeighborhoodDelegation.where(id: deleg_ids).delete_all
    end

    # Usuarios antes que la junta: la referencian por neighborhood_association_id.
    demo_users.destroy_all
    assoc&.destroy
  end

  def purge_attachments(scope)
    scope.each do |record|
      record.attachment_reflections.each_key do |name|
        record.public_send(name).purge
      end
    end
  end

  def summary
    {
      association: @association.name,
      delegations: @delegations.size,
      approved_members: Member.where(neighborhood_association: @association, status: "approved").count,
      pending_onboardings: OnboardingRequest.where(neighborhood_association: @association, status: "pending").count,
      pending_dependents: IdentityVerificationRequest.where(neighborhood_association: @association, dependent: true, status: "pending").count,
      admin_email: @admin.email,
      password: DEMO_PASSWORD
    }
  end
end
