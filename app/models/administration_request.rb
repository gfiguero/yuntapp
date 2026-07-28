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

  with_options if: -> { pending? } do
    validates :position, presence: true, inclusion: {in: BoardMember::POSITIONS}
    validates :first_name, :last_name, :phone, presence: true
    validates :organization_rut, presence: true
    validates :run, presence: true
    validate :target_association_present
  end
  validates :organization_rut, run: true, if: -> { organization_rut.present? }
  validates :run, run: true, if: -> { run.present? }

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
  def target_association_label = neighborhood_association&.name || proposed_association_name

  def submit!
    update!(status: "pending")
    self
  end

  def cancel!
    raise "Only pending administration requests can be cancelled (current: #{status})" unless pending?
    update!(status: "cancelled")
    self
  end

  # Reutiliza el patrón exacto de VerifiedIdentity#normalize_phone para
  # llegar al formato +569XXXXXXXX de forma consistente en todo el proyecto.
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

  def normalize_names
    self.first_name = first_name.to_s.strip.split.map(&:capitalize).join(" ") if first_name.present?
    self.last_name = last_name.to_s.strip.split.map(&:capitalize).join(" ") if last_name.present?
  end
end
