require "test_helper"

class MemberTest < ActiveSupport::TestCase
  test "name delegates to verified_identity" do
    member = members(:selendis_member)
    assert_equal "Selendis Daelaam", member.name
    assert_equal member.verified_identity.name, member.name
  end

  test "run delegates to verified_identity" do
    member = members(:selendis_member)
    assert_equal "11111111-1", member.run
    assert_equal member.verified_identity.run, member.run
  end

  test "phone delegates to verified_identity" do
    member = members(:selendis_member)
    assert_equal "+56912345678", member.phone
    assert_equal member.verified_identity.phone, member.phone
  end

  test "user derives from verified_identity" do
    member = members(:selendis_member)
    assert_equal users(:selendis), member.user
    assert_equal member.verified_identity.users.first, member.user
  end

  test "first_name and last_name delegate to verified_identity" do
    member = members(:karass_dependent)
    assert_equal "Karass", member.first_name
    assert_equal "Templar", member.last_name
  end

  test "filter_by_name searches verified_identity fields" do
    results = Member.filter_by_name("Selendis")
    assert_includes results, members(:selendis_member)
  end

  test "filter_by_run searches verified_identity fields" do
    results = Member.filter_by_run("11111111")
    assert_includes results, members(:selendis_member)
  end
end
