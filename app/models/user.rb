class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable, :confirmable,
    :recoverable, :rememberable, :validatable

  scope :filter_by_email, ->(email) { where.like(email: "%#{email}%") }

  belongs_to :neighborhood_association, optional: true
  belongs_to :verified_identity, optional: true
  has_many :identity_verification_requests
  has_many :residence_verification_requests
  has_many :onboarding_requests

  # La solicitud actual es cualquiera que esté en borrador o pendiente
  has_one :current_onboarding_request, -> { where(status: ["draft", "pending"]) }, class_name: "OnboardingRequest"

  has_many :listings
  has_many :approved_certificates, class_name: "ResidenceCertificate", foreign_key: :approved_by_id
  has_many :requested_members, class_name: "Member", foreign_key: :requested_by_id
  has_many :approved_members, class_name: "Member", foreign_key: :approved_by_id

  def name
    verified_identity&.name || email
  end

  def member
    verified_identity&.members&.active&.find_by(neighborhood_association: neighborhood_association)
  end

  def residency
    verified_identity&.residencies&.approved&.order(created_at: :desc)&.first
  end

  def household_unit
    residency&.household_unit
  end

  def family_group
    residency&.family_group
  end

  def household_admin?
    residency&.household_admin? || false
  end

  def verified?
    verified_identity.present?
  end

  private

  # Encola los correos de Devise (confirmacion, reset de password, etc.) en
  # Solid Queue en vez de enviarlos sincronicamente dentro del request. Evita
  # que un fallo del backend SMTP tumbe el registro con un 500 (el default de
  # Devise es deliver_now). Consistente con el resto de mailers de la app, que
  # ya usan deliver_later.
  def send_devise_notification(notification, *args)
    devise_mailer.send(notification, self, *args).deliver_later
  end
end
