class AddMercadopagoEmailToUsers < ActiveRecord::Migration[8.1]
  def change
    # BR-142: email de la cuenta MercadoPago del socio, usado como payer_email
    # de las suscripciones (preapproval). Distinto del email de login (inmutable, BR-093).
    add_column :users, :mercadopago_email, :string
  end
end
