class AddSubscriptionAmountToListings < ActiveRecord::Migration[8.1]
  # BR-088/BR-090: el monto de la suscripción queda FIJO al autorizarla en MP
  # (`auto_recurring.transaction_amount`), pero localmente el gate del cobro
  # recurrente comparaba contra `listings.amount`, que se reescribe con el precio
  # vigente cada vez que el usuario abre pagar/suscribirse. Si la junta subía el
  # precio, el cobro legítimo de MP (por el monto viejo) dejaba de coincidir y la
  # renovación se rechazaba: el usuario pagaba y su publicación vencía igual.
  #
  # Esta columna guarda el snapshot inmutable de la suscripción, independiente
  # del snapshot del pago único (`amount`).
  def up
    add_column :listings, :subscription_amount, :integer

    # Backfill: las suscripciones ya creadas cobran el `amount` con el que se
    # autorizaron; hoy es el único dato disponible del monto pactado.
    execute <<~SQL
      UPDATE listings
         SET subscription_amount = amount
       WHERE preapproval_id IS NOT NULL
         AND amount IS NOT NULL
    SQL
  end

  def down
    remove_column :listings, :subscription_amount
  end
end
