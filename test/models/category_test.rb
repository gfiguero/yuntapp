require "test_helper"

class CategoryTest < ActiveSupport::TestCase
  # BR-100: borrar una categoría no destruye las publicaciones; las desvincula.
  test "destroying a category nullifies its listings instead of destroying them" do
    category = Category.create!(name: "Muebles")
    listing = Listing.create!(user: users(:selendis), name: "Silla de madera", category: category)

    category.destroy!

    assert Listing.exists?(listing.id), "la publicación debe sobrevivir"
    assert_nil listing.reload.category_id, "la publicación queda sin categoría"
  end
end
