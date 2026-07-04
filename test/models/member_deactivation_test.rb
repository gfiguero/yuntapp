require "test_helper"

class MemberDeactivationTest < ActiveSupport::TestCase
  def setup
    @member = members(:selendis_member)
    @dependent = members(:dependent_member)
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

  # BR-037: al desactivar un household_admin, sus residentes dependientes
  # quedan desactivados en cascada automáticamente.
  test "deactivate! cascades to dependent residents (BR-037)" do
    assert @dependent.approved?, "el dependiente debe partir activo"

    @member.deactivate!(reason: "Se mudó fuera de la comuna")

    assert @dependent.reload.inactive?, "el dependiente debe quedar inactivo en cascada"
  end

  # BR-038: la desactivación en cascada conserva el registro con un motivo.
  test "deactivate! records a reason on cascaded dependents (BR-038)" do
    @member.deactivate!(reason: "Se mudó fuera de la comuna")

    assert @dependent.reload.deactivation_reason.present?,
      "el dependiente desactivado en cascada debe conservar un motivo"
  end

  # La desactivación de un dependiente (no jefe de hogar) no cascadea.
  test "deactivate! on a dependent does not cascade" do
    @member.deactivate!(reason: "Se mudó fuera de la comuna")
    @dependent.reload

    assert_nothing_raised { @dependent.deactivate!(reason: "Corrección administrativa") }
    assert @dependent.reload.inactive?
  end
end
