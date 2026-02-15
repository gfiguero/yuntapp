class IdentityVerificationRequest < ApplicationRecord
  belongs_to :user
  belongs_to :neighborhood_association
  belongs_to :onboarding_request, optional: true

  has_one_attached :identity_document

  STATUSES = %w[draft pending approved rejected].freeze

  validates :status, inclusion: { in: STATUSES }

  # Validaciones solo si no está en borrador
  validates :first_name, :last_name, :run, :phone, presence: true, unless: :draft?

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
