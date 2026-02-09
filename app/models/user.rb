class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
    :recoverable, :rememberable, :validatable

  belongs_to :neighborhood_association, optional: true
  belongs_to :household_unit, optional: true
  has_one :member
  has_many :listings
  has_many :approved_certificates, class_name: "ResidenceCertificate", foreign_key: :approved_by_id
  has_many :requested_members, class_name: "Member", foreign_key: :requested_by_id
  has_many :approved_members, class_name: "Member", foreign_key: :approved_by_id

  def household_admin?
    member&.household_admin? || false
  end
end
