require "test_helper"

class FamilyGroupTest < ActiveSupport::TestCase
  def setup
    @household_unit = household_units(:selendis_household)
    @family_group = FamilyGroup.create!(household_unit: @household_unit)
  end

  test "belongs to household_unit" do
    assert_equal @household_unit, @family_group.household_unit
  end

  test "is invalid without household_unit" do
    group = FamilyGroup.new
    assert_not group.valid?
    assert_includes group.errors[:household_unit], I18n.t("errors.messages.required")
  end

  test "household_unit has_many family_groups" do
    assert_includes @household_unit.family_groups, @family_group
  end

  test "household_admin returns the admin residency" do
    residency = residencies(:selendis_residency)
    residency.update!(family_group: @family_group)
    assert_equal residency, @family_group.household_admin
  end

  test "household_admin returns nil when no admin residency exists" do
    assert_nil @family_group.household_admin
  end

  test "residency can belong to a family_group" do
    residency = residencies(:selendis_residency)
    residency.update!(family_group: @family_group)
    assert_equal @family_group, residency.family_group
  end
end
