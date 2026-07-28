class AddRutToNeighborhoodAssociations < ActiveRecord::Migration[8.1]
  # BR-119/BR-121: toda junta debe tener RUT. Expand-contract:
  # 1) columna nullable, 2) backfill determinístico válido, 3) NOT NULL + índice único.
  def up
    add_column :neighborhood_associations, :rut, :string

    # Backfill de juntas heredadas con un RUT válido y único por fila.
    # Rango 60.000.000+id: 8 dígitos, único (id único), DV módulo 11 correcto.
    # Los RUTs reales se corrigen luego desde el panel superadmin.
    execute("SELECT id FROM neighborhood_associations").each do |row|
      id = row.is_a?(Array) ? row.first : row["id"]
      body = (60_000_000 + id.to_i).to_s
      rut = "#{body}-#{dv(body)}"
      execute("UPDATE neighborhood_associations SET rut = #{connection.quote(rut)} WHERE id = #{id.to_i}")
    end

    change_column_null :neighborhood_associations, :rut, false
    add_index :neighborhood_associations, :rut, unique: true
  end

  def down
    remove_index :neighborhood_associations, :rut
    remove_column :neighborhood_associations, :rut
  end

  private

  # Dígito verificador módulo 11 (idéntico a RunValidator#calculate_dv).
  def dv(body)
    sum = 0
    multiplier = 2
    body.to_s.reverse.each_char do |char|
      sum += char.to_i * multiplier
      multiplier = (multiplier == 7) ? 2 : multiplier + 1
    end
    remainder = 11 - (sum % 11)
    case remainder
    when 11 then "0"
    when 10 then "K"
    else remainder.to_s
    end
  end
end
