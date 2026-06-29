class IdentityVerificationRequest < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :onboarding_request, optional: true
  belongs_to :family_group, optional: true
  belongs_to :requested_by, class_name: "User", optional: true
  belongs_to :neighborhood_association, optional: true

  has_many_attached :identity_documents

  STATUSES = %w[draft pending approved rejected].freeze

  validates :status, inclusion: { in: STATUSES }

  # Validaciones de presencia para nombre/apellido/RUN solo si no es draft
  validates :first_name, :last_name, :run, presence: true, unless: -> { draft? || status == "draft" }

  # Teléfono requerido solo para solicitudes no-draft y no-dependientes (BR-068)
  validates :phone, presence: true, unless: -> { draft? || status == "draft" || dependent? }

  # Para solicitudes dependientes, el contexto de familia/usuario es obligatorio
  validates :family_group, :requested_by, :neighborhood_association, presence: true, if: :dependent?

  # Validaciones de formato siempre (incluso en draft, si el campo no está vacío)
  validates :run, run: true, allow_blank: true
  validates :phone, phone: true, allow_blank: true

  # Normalización de teléfono antes de validar
  before_validation :normalize_phone

  def normalize_phone
    return if phone.blank?

    # Limpiamos caracteres no numéricos excepto el + inicial
    clean_phone = phone.to_s.gsub(/[^0-9+]/, "")

    # Si empieza con 9 y tiene 9 dígitos (ej: 912345678), agregamos +56
    self.phone = if clean_phone.match?(/\A9\d{8}\z/)
      "+56#{clean_phone}"
    # Si empieza con 569 y tiene 11 dígitos, agregamos +
    elsif clean_phone.match?(/\A569\d{8}\z/)
      "+#{clean_phone}"
    # Si ya tiene formato correcto (+569...), lo dejamos igual (o limpiamos espacios extra si hubiera)
    else
      clean_phone
    end
  end

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
    return unless run.present?
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
