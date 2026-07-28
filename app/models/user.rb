class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable, :confirmable,
    :recoverable, :rememberable, :validatable

  # BR-100: la cuenta nunca se destruye. Reactivación auto-servicio vía correo: el
  # token es válido solo mientras la cuenta esté desactivada y se invalida al reactivar.
  generates_token_for :account_reactivation, expires_in: 1.day do
    deactivated_at&.to_i
  end

  scope :filter_by_email, ->(email) { where.like(email: "%#{email}%") }

  # BR-100: una cuenta nunca se destruye (ni por el usuario vía Devise, ni por consola).
  # Solo se desactiva o bloquea, conservando el historial. Guard de defensa en profundidad.
  before_destroy :prevent_destruction

  belongs_to :neighborhood_association, optional: true
  belongs_to :verified_identity, optional: true
  belongs_to :blocked_by, class_name: "User", optional: true
  has_many :identity_verification_requests
  has_many :residence_verification_requests
  has_many :onboarding_requests
  # Sin dependent:: User nunca se destruye (before_destroy :prevent_destruction),
  # y las solicitudes de administración se conservan como historial (BR-100).
  has_many :administration_requests

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

  def deactivated? = deactivated_at.present?

  def blocked? = blocked_at.present?

  # Devise: bloquea el login si la cuenta está desactivada (por el usuario) o
  # bloqueada (por un superadmin). BR-100: el registro se conserva como historial.
  def active_for_authentication?
    super && !deactivated? && !blocked?
  end

  def inactive_message
    if blocked?
      :account_blocked
    elsif deactivated?
      :account_deactivated
    else
      super
    end
  end

  # Auto-desactivación (reversible por el usuario vía correo). Cascada: nada se borra.
  def deactivate!
    return if deactivated?
    transaction do
      update!(deactivated_at: Time.current)
      cascade_account_deactivation!
    end
  end

  # Reactivación auto-servicio. Una cuenta bloqueada por un admin NO puede reactivarse
  # por el usuario: solo levanta el bloqueo un superadmin (unblock!).
  def reactivate!
    return if blocked?
    update!(deactivated_at: nil)
  end

  # Bloqueo por superadmin (no reversible por el usuario). Un superadmin no es bloqueable.
  def block!(by:, reason:)
    transaction do
      update!(blocked_at: Time.current, blocked_by: by, block_reason: reason)
      cascade_account_deactivation!
    end
  end

  def unblock!
    update!(blocked_at: nil, blocked_by: nil, block_reason: nil)
  end

  private

  # BR-100/BR-099: al desactivar/bloquear la cuenta, su historial se conserva pero
  # queda inerte: membresías activas → inactive (con cascada a dependientes),
  # solicitudes pendientes → canceladas, publicaciones despublicadas. Sin borrado.
  def cascade_account_deactivation!
    reason = I18n.t("users.deactivation.cascade_reason")
    verified_identity&.members&.active&.pluck(:id)&.each do |member_id|
      member = Member.find(member_id)
      member.deactivate!(reason: reason) unless member.inactive?
    end
    onboarding_requests.where(status: "pending").find_each(&:cancel!)
    listings.update_all(active: false)
  end

  def prevent_destruction
    errors.add(:base, I18n.t("users.errors.cannot_destroy"))
    throw :abort
  end

  # Encola los correos de Devise (confirmacion, reset de password, etc.) en
  # Solid Queue en vez de enviarlos sincronicamente dentro del request. Evita
  # que un fallo del backend SMTP tumbe el registro con un 500 (el default de
  # Devise es deliver_now). Consistente con el resto de mailers de la app, que
  # ya usan deliver_later.
  def send_devise_notification(notification, *args)
    devise_mailer.send(notification, self, *args).deliver_later
  end
end
