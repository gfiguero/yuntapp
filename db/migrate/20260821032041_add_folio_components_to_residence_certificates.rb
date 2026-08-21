class AddFolioComponentsToResidenceCertificates < ActiveRecord::Migration[8.1]
  # El correlativo del folio pasa a vivir en columnas enteras: el folio deja de
  # ser el dato y pasa a ser su representación. Ambas son nullable porque un
  # certificado sin emitir no tiene folio (BR-064: nace en pending_payment).
  def change
    add_column :residence_certificates, :folio_year, :integer
    add_column :residence_certificates, :folio_sequence, :integer

    # Parcial: las filas sin emitir tienen NULL y no deben competir por el
    # índice. Mismo patrón que los índices únicos parciales de #108.
    add_index :residence_certificates,
      [:neighborhood_association_id, :folio_year, :folio_sequence],
      unique: true,
      where: "folio_sequence IS NOT NULL",
      name: "index_residence_certificates_on_association_year_sequence"
  end
end
