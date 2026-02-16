class VerifiedIdentity < ApplicationRecord
  self.table_name = "verified_identities"

  VERIFICATION_STATUSES = %w[pending verified rejected].freeze

  has_many :users
  has_many :members
  has_one_attached :identity_document

  before_validation :normalize_run_field
  before_validation :normalize_names
  before_validation :normalize_phone

  validates :first_name, :last_name, :run, presence: true
  validates :run, uniqueness: true, run: true, if: -> { run.present? }
  validates :phone, phone: true, if: -> { phone.present? }
  validates :verification_status, presence: true, inclusion: {in: VERIFICATION_STATUSES}

  def normalize_phone
    return if phone.blank?
    clean_phone = phone.to_s.gsub(/[^0-9+]/, "")
    self.phone = if clean_phone.match?(/\A9\d{8}\z/)
      "+56#{clean_phone}"
    elsif clean_phone.match?(/\A569\d{8}\z/)
      "+#{clean_phone}"
    else
      clean_phone
    end
  end

  scope :verified, -> { where(verification_status: "verified") }
  scope :pending, -> { where(verification_status: "pending") }

  def name = "#{first_name} #{last_name}"
  def verified? = verification_status == "verified"
  def pending_verification? = verification_status == "pending"
  def rejected_verification? = verification_status == "rejected"

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
