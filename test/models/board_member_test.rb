require "test_helper"

class BoardMemberTest < ActiveSupport::TestCase
  # BR-100: la baja de un cargo cierra el registro, no lo destruye.
  test "end_term! closes the term without destroying the record" do
    board_member = board_members(:selendis_board_member)
    assert board_member.active?

    board_member.end_term!

    assert_not board_member.reload.active?, "el cargo queda inactivo"
    assert_equal Date.current, board_member.end_date
    assert BoardMember.exists?(board_member.id), "el registro se conserva"
  end

  # BR-007: aislamiento multi-tenant. `member_id` viaja por strong params, así
  # que un POST manipulado podía colar un socio de otra junta en la directiva y
  # filtrar su identidad en las vistas (incluida la pública de la junta).
  test "no acepta un member de otra junta (BR-007)" do
    otra_junta = neighborhood_associations(:association_0)
    socio_ajeno = members(:selendis_member)
    assert_not_equal otra_junta.id, socio_ajeno.neighborhood_association_id

    board_member = BoardMember.new(
      neighborhood_association: otra_junta,
      member: socio_ajeno,
      position: "presidente",
      start_date: Date.current
    )

    assert_not board_member.valid?
    assert_includes board_member.errors[:member], "debe ser un socio de esta junta de vecinos"
  end

  test "acepta un member de la misma junta" do
    socio = members(:selendis_member)

    board_member = BoardMember.new(
      neighborhood_association: socio.neighborhood_association,
      member: socio,
      position: "tesorero",
      start_date: Date.current
    )

    assert board_member.valid?, board_member.errors.full_messages.to_sentence
  end
end
