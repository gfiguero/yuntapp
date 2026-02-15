require "test_helper"

class MemberTest < ActiveSupport::TestCase
  test "name delegates to persona" do
    member = members(:selendis_member)
    assert_equal "Selendis Daelaam", member.name
    assert_equal member.persona.name, member.name
  end

  test "run delegates to persona" do
    member = members(:selendis_member)
    assert_equal "11111111-1", member.run
    assert_equal member.persona.run, member.run
  end

  test "phone delegates to persona" do
    member = members(:selendis_member)
    assert_equal "+56912345678", member.phone
    assert_equal member.persona.phone, member.phone
  end

  test "user derives from persona" do
    member = members(:selendis_member)
    assert_equal users(:selendis), member.user
    assert_equal member.persona.user, member.user
  end

  test "first_name and last_name delegate to persona" do
    member = members(:karass_dependent)
    assert_equal "Karass", member.first_name
    assert_equal "Templar", member.last_name
  end

  test "filter_by_name searches persona fields" do
    results = Member.filter_by_name("Selendis")
    assert_includes results, members(:selendis_member)
  end

  test "filter_by_run searches persona fields" do
    results = Member.filter_by_run("11111111")
    assert_includes results, members(:selendis_member)
  end
end
