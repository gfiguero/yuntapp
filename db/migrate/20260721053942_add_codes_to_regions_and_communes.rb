class AddCodesToRegionsAndCommunes < ActiveRecord::Migration[8.1]
  def change
    # Código Único Territorial (CUT) oficial. Nullable + índice único parcial
    # para una transición segura; el seed (db/seeds/chile.yml) los completa.
    add_column :regions, :code, :string
    add_column :regions, :position, :integer
    add_column :communes, :code, :string

    add_index :regions, :code, unique: true, where: "code IS NOT NULL"
    add_index :regions, :position, unique: true, where: "position IS NOT NULL"
    add_index :communes, :code, unique: true, where: "code IS NOT NULL"
  end
end
