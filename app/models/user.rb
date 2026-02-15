class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
    :recoverable, :rememberable, :validatable

  belongs_to :neighborhood_association, optional: true
  belongs_to :verified_identity, optional: true
  has_many :identity_verification_requests
  has_many :residence_verification_requests
  has_many :onboarding_requests

  # La solicitud actual es cualquiera que esté en borrador o pendiente
  has_one :current_onboarding_request, -> { where(status: ["draft", "pending"]) }, class_name: "OnboardingRequest"

  has_one :member
  has_one :household_unit, through: :member
  has_many :listings
  has_many :approved_certificates, class_name: "ResidenceCertificate", foreign_key: :approved_by_id
  has_many :requested_members, class_name: "Member", foreign_key: :requested_by_id
  has_many :approved_members, class_name: "Member", foreign_key: :approved_by_id

  def name
    verified_identity&.name || email
  end

  def member
    verified_identity&.members&.first
  end

  def household_unit
    member&.household_unit
  end

  def household_admin?
    member&.household_admin? || false
  end

  def verified?
    persona&.verified? || false
  end

  def pending_verification?
    persona&.pending_verification? || false
  end
end
