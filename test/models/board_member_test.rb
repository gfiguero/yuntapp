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
end
