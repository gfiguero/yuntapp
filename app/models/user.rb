class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
    :recoverable, :rememberable, :validatable

  belongs_to :neighborhood_association, optional: true
  belongs_to :persona, optional: true
  has_many :listings
  has_many :approved_certificates, class_name: "ResidenceCertificate", foreign_key: :approved_by_id
  has_many :requested_members, class_name: "Member", foreign_key: :requested_by_id
  has_many :approved_members, class_name: "Member", foreign_key: :approved_by_id

  def name
    persona&.name || email
  end

  def member
    persona&.members&.first
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
