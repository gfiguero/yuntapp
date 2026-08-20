class IdentityVerificationRequest < ApplicationRecord
  include PhoneNormalization

  belongs_to :user, optional: true
  belongs_to :onboarding_request, optional: true
  belongs_to :family_group, optional: true
  belongs_to :requested_by, class_name: "User", optional: true
  belongs_to :neighborhood_association, optional: true

  has_many_attached :identity_documents

  STATUSES = %w[draft pending approved rejected cancelled].freeze

  validates :status, inclusion: {in: STATUSES}

  # Validaciones de presencia para nombre/apellido/RUN solo si no es draft
  validates :first_name, :last_name, :run, presence: true, unless: -> { draft? || status == "draft" }

  # Teléfono requerido solo para solicitudes no-draft y no-dependientes (BR-068)
  validates :phone, presence: true, unless: -> { draft? || status == "draft" || dependent? }

  # Para solicitudes dependientes, el contexto de familia/usuario es obligatorio
  validates :family_group, :requested_by, :neighborhood_association, presence: true, if: :dependent?

  # BR-047/BR-060 (#105): el rechazo de un DEPENDIENTE debe registrar el motivo
  # (en el onboarding estándar el motivo vive en OnboardingRequest y el IVR se
  # rechaza en cascada sin motivo propio).
  validates :rejection_reason, presence: true, if: -> { rejected? && dependent? }

  # Validaciones de formato siempre (incluso en draft, si el campo no está vacío)
  validates :run, run: true, allow_blank: true
  validates :phone, phone: true, allow_blank: true

  scope :draft, -> { where(status: "draft") }
  scope :pending, -> { where(status: "pending") }
  scope :approved, -> { where(status: "approved") }
  scope :rejected, -> { where(status: "rejected") }
  scope :dependent_requests, -> { where(dependent: true) }
  scope :independent_requests, -> { where(dependent: false) }

  before_validation :normalize_run_field
  before_validation :normalize_names

  def full_name
    "#{first_name} #{last_name}".strip
  end

  def draft? = status == "draft"
  def pending? = status == "pending"
  def approved? = status == "approved"
  def rejected? = status == "rejected"

  private

  def normalize_run_field
    return if run.blank?
    self.run = run.to_s.gsub(/[.\-\s]/, "").upcase
    # Insertar guión antes del dígito verificador: 12345678K → 12345678-K
    self.run = "#{run[0..-2]}-#{run[-1]}" if run.match?(/\A\d{7,8}[0-9K]\z/)
  end

  def normalize_names
    self.first_name = capitalize_each_word(first_name) if first_name.present?
    self.last_name = capitalize_each_word(last_name) if last_name.present?
  end

  def capitalize_each_word(value)
    value.strip.split(/\s+/).map { |word| word.downcase.capitalize }.join(" ")
  end
end
