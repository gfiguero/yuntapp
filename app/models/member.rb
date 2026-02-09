class Member < ApplicationRecord
  include Filterable

  STATUSES = %w[pending approved rejected].freeze

  belongs_to :household_unit
  belongs_to :user, optional: true
  belongs_to :requested_by, class_name: "User", optional: true
  belongs_to :approved_by, class_name: "User", optional: true
  has_many :board_members, dependent: :destroy
  has_many :residence_certificates, dependent: :destroy
  has_many_attached :documents

  before_validation :normalize_run_field

  validates :first_name, :last_name, :run, presence: true
  validates :status, presence: true, inclusion: {in: STATUSES}

  scope :filter_by_status, ->(status) { where(status: status) }
  scope :approved, -> { where(status: "approved") }
  scope :pending, -> { where(status: "pending") }

  def name
    "#{first_name} #{last_name}"
  end

  def pending?
    status == "pending"
  end

  def approved?
    status == "approved"
  end

  def rejected?
    status == "rejected"
  end

  private

  def normalize_run_field
    self.run = run.to_s.gsub(/[.\-\s]/, "").upcase if run.present?
  end
end
