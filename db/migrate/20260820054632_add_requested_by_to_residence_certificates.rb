class AddRequestedByToResidenceCertificates < ActiveRecord::Migration[8.1]
  # BR-098: el household_admin puede solicitar certificados a nombre de un
  # residente dependiente de su núcleo. Hasta ahora el certificado solo guardaba
  # al **titular** (`member`), así que no había forma de auditar quién lo pidió.
  #
  # `null: true` es deliberado: los certificados emitidos antes de esta columna
  # no tienen solicitante registrable y no se inventa uno. Un backfill con el
  # titular sería una afirmación falsa justamente en los casos que interesa
  # distinguir. Mismo patrón que `members.requested_by_id`.
  def change
    add_reference :residence_certificates, :requested_by,
      null: true,
      foreign_key: {to_table: :users}
  end
end
