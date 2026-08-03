require "test_helper"

module Admin
  # BR-046: la identidad verificada no se edita libremente desde el panel del
  # admin. El RUN es el identificador con el que se verificó la documentación y
  # del que cuelgan los certificados ya emitidos.
  class MembersControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @admin = users(:selendis) # admin de manios_de_buin
      @member = members(:selendis_member)
      sign_in @admin
    end

    def update_params(overrides = {})
      {
        member: {
          first_name: "Selendis",
          last_name: "Daelaam",
          run: @member.run,
          phone: "+56912345678",
          email: "selendis@daelaam.io"
        }.merge(overrides)
      }
    end

    test "update ignores a tampered RUN (BR-046)" do
      original_run = @member.run

      patch admin_member_url(@member), params: update_params(run: "99999999-9")

      assert_redirected_to admin_member_url(@member)
      assert_equal original_run, @member.reload.run,
        "el RUN de una identidad verificada es inmutable"
    end

    test "update still applies the editable fields (BR-046)" do
      patch admin_member_url(@member), params: update_params(first_name: "Selendis Renombrada", run: "99999999-9")

      @member.reload
      assert_equal "Selendis Renombrada", @member.first_name
      assert_equal "11111111-1", @member.run
    end

    # El RUN reescrito no puede tampoco robar la identidad de otro socio: el
    # parámetro se descarta antes de tocar la VerifiedIdentity.
    test "update cannot repoint an identity to another member's RUN (BR-012/BR-046)" do
      other_run = members(:dependent_member).run
      assert_not_equal other_run, @member.run

      patch admin_member_url(@member), params: update_params(run: other_run)

      assert_equal "11111111-1", @member.reload.run
    end

    test "edit renders the RUN field disabled (BR-046)" do
      get edit_admin_member_url(@member)

      assert_response :success
      assert_select "input[name='member[run]'][disabled]"
    end

    test "new renders the RUN field editable" do
      get new_admin_member_url

      assert_response :success
      assert_select "input[name='member[run]']:not([disabled])"
    end
  end
end
