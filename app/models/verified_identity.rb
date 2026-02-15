class VerifiedIdentity < ApplicationRecord
  self.table_name = "verified_identities"

  VERIFICATION_STATUSES = %w[pending verified rejected].freeze

  has_many :users
  has_many :members
  has_one_attached :identity_document

  before_validation :normalize_run_field
  before_validation :normalize_names

  validates :first_name, :last_name, :run, presence: true
  validates :run, uniqueness: true
  validate :run_must_be_valid_chilean_rut, if: -> { run.present? }
  validates :verification_status, presence: true, inclusion: {in: VERIFICATION_STATUSES}

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

  def run_must_be_valid_chilean_rut
    unless run.match?(/\A\d{7,8}-[0-9K]\z/)
      errors.add(:run, :invalid_rut_format)
      return
    end

    body, dv = run.split("-")
    errors.add(:run, :invalid_rut_check_digit) unless dv == compute_rut_check_digit(body)
  end

  def compute_rut_check_digit(body)
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

  def normalize_names
    self.first_name = capitalize_each_word(first_name) if first_name.present?
    self.last_name = capitalize_each_word(last_name) if last_name.present?
  end

  def capitalize_each_word(value)
    value.strip.split(/\s+/).map { |word| word.downcase.capitalize }.join(" ")
  end
end
