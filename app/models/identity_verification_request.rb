class IdentityVerificationRequest < ApplicationRecord
  belongs_to :user
  belongs_to :neighborhood_association
  belongs_to :onboarding_request, optional: true

  has_many_attached :identity_documents

  STATUSES = %w[draft pending approved rejected].freeze

  validates :status, inclusion: {in: STATUSES}

  # Validaciones solo si no está en borrador
  validates :first_name, :last_name, :run, :phone, presence: true, unless: -> { draft? || status == "draft" }

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

  before_validation :normalize_run_field
  before_validation :normalize_names

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
