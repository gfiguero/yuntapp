class Member < ApplicationRecord
  include Filterable

  STATUSES = %w[pending approved rejected].freeze

  belongs_to :household_unit
  belongs_to :persona
  belongs_to :requested_by, class_name: "User", optional: true
  belongs_to :approved_by, class_name: "User", optional: true
  has_many :board_members, dependent: :destroy
  has_many :residence_certificates, dependent: :destroy
  has_many_attached :documents

  delegate :name, :run, :phone, :email, :first_name, :last_name, to: :persona, allow_nil: true

  validates :status, presence: true, inclusion: {in: STATUSES}

  scope :filter_by_status, ->(status) { where(status: status) }
  scope :filter_by_name, ->(name) { joins(:persona).where("personas.first_name LIKE :q OR personas.last_name LIKE :q", q: "%#{name}%") }
  scope :filter_by_run, ->(run) { joins(:persona).where("personas.run LIKE :q", q: "%#{run}%") }
  scope :approved, -> { where(status: "approved") }
  scope :pending, -> { where(status: "pending") }

  def user
    persona&.user
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
end
