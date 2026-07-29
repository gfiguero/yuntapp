module MercadopagoPayer
  extend ActiveSupport::Concern

  private

  # Datos del pagador (current_user = quien realiza la transacción; para
  # certificados de dependientes el pagador es el household_admin — BR-098).
  def mercadopago_payer
    payer = {email: current_user.email}
    identity = current_user.verified_identity
    if identity
      payer[:name] = identity.first_name
      payer[:surname] = identity.last_name
      payer[:identification] = {type: "RUT", number: identity.run} if identity.run.present?
    end
    payer
  end
end
