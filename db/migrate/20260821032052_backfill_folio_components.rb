class BackfillFolioComponents < ActiveRecord::Migration[8.1]
  # BR-008: los folios emitidos NO se reescriben. Solo se pueblan las columnas
  # nuevas, para que el correlativo continúe donde iba en vez de reiniciar y
  # chocar. El parseo del formato viejo (`CR-{junta}-{n}`) ocurre una única vez,
  # aquí, sobre datos conocidos — no en la ruta de emisión.
  def up
    ResidenceCertificate.where.not(folio: nil).find_each do |cert|
      sequence = cert.folio.to_s.split("-").last.to_i
      year = cert.issue_date&.year || cert.created_at.year

      say "backfill ##{cert.id} folio=#{cert.folio} -> year=#{year} sequence=#{sequence}"
      cert.update_columns(folio_year: year, folio_sequence: sequence)
    end
  end

  def down
    ResidenceCertificate.update_all(folio_year: nil, folio_sequence: nil)
  end
end
