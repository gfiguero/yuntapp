class RemoveApprovedByFromResidenceCertificates < ActiveRecord::Migration[8.0]
  # BR-062/BR-064/BR-077: los certificados se emiten automáticamente tras el
  # pago; no existe aprobación de admin ni estados approved/rejected. La columna
  # `approved_by_id` era un residuo del flujo anterior: nunca se asignaba en
  # ningún camino del código y la vista admin mostraba siempre "—", sugiriendo
  # una semántica de "aprobador" que ya no existe.
  def change
    remove_reference :residence_certificates, :approved_by,
      foreign_key: {to_table: :users}, index: true, type: :integer
  end
end
