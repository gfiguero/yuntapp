require "test_helper"

class AdministrationApprovalServiceTest < ActiveSupport::TestCase
  setup do
    @staff = users(:artanis) # superadmin
  end

  def upload
    Rack::Test::UploadedFile.new(Rails.root.join("test/fixtures/files/id_placeholder.png"), "image/png")
  end

  test "aprobar junta existente crea identidad, member, boardmember y marca admin" do
    req = AdministrationRequest.create!(
      user: users(:urunis),
      neighborhood_association: neighborhood_associations(:manios_de_buin),
      organization_rut: neighborhood_associations(:manios_de_buin).rut,
      position: "presidente",
      first_name: "Ana", last_name: "Soto", run: "15111222-6", phone: "+56911112222",
      status: "pending", directiva_validity_document: upload
    )

    assert_difference -> { Member.count } => 1, -> { BoardMember.count } => 1, -> { VerifiedIdentity.count } => 1 do
      AdministrationApprovalService.approve!(req, approved_by: @staff)
    end

    req.reload
    assert req.approved?
    assert_equal @staff, req.reviewed_by
    user = users(:urunis).reload
    assert user.admin?
    assert_equal neighborhood_associations(:manios_de_buin), user.neighborhood_association
    member = user.verified_identity.members.approved.find_by(neighborhood_association: neighborhood_associations(:manios_de_buin))
    assert member
    assert_equal "presidente", member.board_members.first.position
  end

  test "aprobar junta nueva la crea con el rut declarado" do
    req = AdministrationRequest.create!(
      user: users(:urunis),
      proposed_association_name: "Junta Nueva Los Robles",
      commune: communes(:commune_0_0_0),
      organization_rut: "86429665-3",
      position: "secretario",
      first_name: "Luis", last_name: "Vera", run: "14222333-3", phone: "+56911113333",
      status: "pending", directiva_validity_document: upload
    )

    assert_difference -> { NeighborhoodAssociation.count } => 1 do
      AdministrationApprovalService.approve!(req, approved_by: @staff)
    end

    junta = NeighborhoodAssociation.find_by(name: "Junta Nueva Los Robles")
    assert_equal "86429665-3", junta.rut
    assert_equal junta, users(:urunis).reload.neighborhood_association
  end

  test "aprobar desactiva la membresia previa en OTRA junta (BR-137)" do
    identidad = verified_identities(:selendis_persona)
    otra = neighborhood_associations(:association_0)
    prev = Member.create!(verified_identity: identidad, neighborhood_association: otra, status: "approved")
    req = AdministrationRequest.create!(
      user: users(:selendis),
      neighborhood_association: neighborhood_associations(:manios_de_buin),
      organization_rut: neighborhood_associations(:manios_de_buin).rut,
      position: "tesorero",
      first_name: identidad.first_name, last_name: identidad.last_name,
      run: identidad.run, phone: "+56911114444",
      status: "pending", directiva_validity_document: upload
    )

    AdministrationApprovalService.approve!(req, approved_by: @staff)

    assert_equal "inactive", prev.reload.status
  end

  # BR-054: una junta disuelta tiene todos sus socios en inactive. Aprobar hacia
  # ella dejaba a un admin operando una junta que el staff ya disolvió, con un
  # Member(approved) y un BoardMember(active) que contradicen la disolución.
  test "no aprueba hacia una junta disuelta (BR-054)" do
    junta = neighborhood_associations(:manios_de_buin)
    req = AdministrationRequest.create!(
      user: users(:urunis),
      neighborhood_association: junta,
      organization_rut: junta.rut,
      position: "secretario",
      first_name: "Ana", last_name: "Soto", run: "15111222-6", phone: "+56911112222",
      status: "pending", directiva_validity_document: upload
    )
    junta.update_column(:active, false)

    assert_no_difference -> { Member.count } do
      assert_no_difference -> { BoardMember.count } do
        assert_raises(AdministrationApprovalService::InactiveAssociationError) do
          AdministrationApprovalService.approve!(req, approved_by: @staff)
        end
      end
    end

    assert req.reload.pending?, "la solicitud sigue pendiente"
    assert_not users(:urunis).reload.admin?
  end
end
