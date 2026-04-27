require "test_helper"

class MemberDeactivationTest < ActiveSupport::TestCase
  def setup
    @member = members(:selendis_member)
  end

  test "deactivate! sets status to inactive" do
    @member.deactivate!(reason: "Fallecimiento del socio")
    assert @member.reload.inactive?
  end

  test "deactivate! saves deactivation_reason" do
    @member.deactivate!(reason: "Se mudó fuera de la comuna")
    assert_equal "Se mudó fuera de la comuna", @member.reload.deactivation_reason
  end

  test "deactivate! without reason raises error" do
    assert_raises(ActiveRecord::RecordInvalid) do
      @member.deactivate!(reason: "")
    end
  end

  test "deactivate! preserves the member record" do
    member_id = @member.id
    @member.deactivate!(reason: "Solicitud del socio")
    assert Member.exists?(member_id)
  end
end
