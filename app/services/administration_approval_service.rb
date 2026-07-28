# Aprobación de una solicitud de administración de junta (BR-128/BR-129/BR-137).
#
# Solo la ejecuta el staff (superadmin). A diferencia del onboarding de residente
# (Admin::OnboardingReviewsController#approve_step3) aquí NO se crea
# VerifiedResidence/HouseholdUnit/Residency: el administrador es socio de directiva
# sin domicilio, por lo que su Member no tiene Residency.
#
# La desactivación de membresías previas es SELECTIVA (BR-137): solo desactiva las
# membresías aprobadas en OTRAS juntas, reutilizando la de la misma junta si existe.
# Se hace ANTES de crear/reactivar el Member de la junta destino, replicando el orden
# de IdentityTransferService (la cascada de deactivate! resuelve al household_admin
# anterior por su residencia aprobada más reciente).
class AdministrationApprovalService
  def self.approve!(administration_request, approved_by:)
    new(administration_request, approved_by).approve!
  end

  def initialize(administration_request, approved_by)
    @req = administration_request
    @approved_by = approved_by
  end

  def approve!
    raise "AdministrationRequest ##{@req.id} no está pending (#{@req.status})" unless @req.pending?

    ActiveRecord::Base.transaction do
      junta = resolve_association!
      identity = resolve_identity!
      deactivate_prior_memberships!(identity, junta)
      member = ensure_member!(identity, junta)
      ensure_board_member!(member)
      @req.user.update!(admin: true, neighborhood_association: junta, verified_identity: identity)
      @req.update!(status: "approved", reviewed_by: @approved_by, reviewed_at: Time.current)
    end
    @req
  end

  private

  def resolve_association!
    return @req.neighborhood_association if @req.neighborhood_association_id.present?

    NeighborhoodAssociation.create!(
      name: @req.proposed_association_name,
      commune: @req.commune,
      rut: @req.organization_rut
    )
  end

  def resolve_identity!
    identity = VerifiedIdentity.find_or_initialize_by(run: @req.run)
    identity.assign_attributes(
      first_name: @req.first_name,
      last_name: @req.last_name,
      phone: @req.phone,
      email: @req.user.email
    )
    identity.save!

    if @req.identity_documents.attached? && !identity.identity_document.attached?
      identity.identity_document.attach(@req.identity_documents.first.blob)
    end
    @req.user.update!(verified_identity: identity)
    identity
  end

  # BR-137: desactivación selectiva. Solo las membresías aprobadas en OTRAS juntas
  # pasan a inactive; la de la misma junta se reutiliza en ensure_member!.
  def deactivate_prior_memberships!(identity, junta)
    identity.members.approved.where.not(neighborhood_association_id: junta.id).find_each do |member|
      member.deactivate!(reason: I18n.t("members.deactivation.administration_onboarding"))
    end
  end

  def ensure_member!(identity, junta)
    member = identity.members.find_or_initialize_by(neighborhood_association: junta)
    member.assign_attributes(
      status: "approved",
      requested_by: @req.user,
      approved_by: @approved_by,
      approved_at: Time.current
    )
    member.save!
    member
  end

  def ensure_board_member!(member)
    BoardMember.find_or_create_by!(
      neighborhood_association: member.neighborhood_association,
      member: member,
      position: @req.position,
      active: true
    ) { |bm| bm.start_date = Date.current }
  end
end
