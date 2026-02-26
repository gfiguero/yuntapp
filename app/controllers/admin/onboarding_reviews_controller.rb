module Admin
  class OnboardingReviewsController < Admin::ApplicationController
    before_action :set_onboarding_request
    before_action :ensure_pending!

    def step1
      @identity_request = @onboarding_request.identity_verification_request
    end

    def step2
      @residence_request = @onboarding_request.residence_verification_request
    end

    def step3
      @identity_request = @onboarding_request.identity_verification_request
      @residence_request = @onboarding_request.residence_verification_request

      # Look up pre-existing verified identity by RUN for transition preview.
      # Since steps 1-2 don't write data, a match here means the identity existed
      # before this onboarding process.
      @existing_identity = VerifiedIdentity
        .includes(residencies: {household_unit: {neighborhood_delegation: :neighborhood_association}})
        .find_by(run: @identity_request.run)

      # Find existing household units with matching delegation + number (same association)
      address_matches = if @residence_request.neighborhood_delegation_id.present?
        current_neighborhood_association.household_units
          .where(
            neighborhood_delegation_id: @residence_request.neighborhood_delegation_id,
            number: @residence_request.number
          )
      else
        HouseholdUnit.none
      end

      # Find household units where the verified identity already has residencies (any association)
      identity_hu_ids = @existing_identity&.residencies&.pluck(:household_unit_id) || []

      @matching_household_units = HouseholdUnit
        .where(id: address_matches.select(:id))
        .or(HouseholdUnit.where(id: identity_hu_ids))
        .includes(:neighborhood_delegation, :approved_residencies, neighborhood_delegation: :neighborhood_association)
        .distinct
    end

    def approve_step3
      ActiveRecord::Base.transaction do
        identity_req = @onboarding_request.identity_verification_request
        residence_req = @onboarding_request.residence_verification_request
        user = @onboarding_request.user

        # 1. Approve identity request and create/update VerifiedIdentity
        identity_req.update!(status: "approved")

        verified_identity = VerifiedIdentity.find_or_initialize_by(run: identity_req.run)
        verified_identity.assign_attributes(
          first_name: identity_req.first_name,
          last_name: identity_req.last_name,
          phone: identity_req.phone,
          email: user.email,
          identity_verification_request: identity_req
        )
        verified_identity.save!

        # Copy first identity document if not already present
        if identity_req.identity_documents.attached? && !verified_identity.identity_document.attached?
          verified_identity.identity_document.attach(identity_req.identity_documents.first.blob)
        end

        # Link user to verified identity
        user.update!(verified_identity: verified_identity)

        # 2. Approve residence request and create VerifiedResidence
        residence_req.update!(status: "approved")

        verified_residence = VerifiedResidence.create!(
          neighborhood_association: @onboarding_request.neighborhood_association,
          neighborhood_delegation_id: residence_req.neighborhood_delegation_id,
          commune: residence_req.commune,
          number: residence_req.number,
          street_name: residence_req.street_name,
          address_detail: residence_req.address_detail,
          manual_address: residence_req.manual_address || false,
          residence_verification_request: residence_req
        )

        # Copy residence documents
        if residence_req.residence_documents.attached?
          residence_req.residence_documents.each do |doc|
            verified_residence.residence_documents.attach(doc.blob)
          end
        end

        # 3. Link user to neighborhood association
        user.update!(neighborhood_association: @onboarding_request.neighborhood_association)

        # 4. Resolve neighborhood delegation
        delegation = if residence_req.neighborhood_delegation_id.present?
          residence_req.neighborhood_delegation
        else
          @onboarding_request.neighborhood_association.neighborhood_delegations
            .find_or_create_by!(name: residence_req.street_name)
        end

        # 5. Relink existing or create new HouseholdUnit
        household_unit = if params[:household_unit_id].present? && params[:household_unit_id] != "new"
          existing = current_neighborhood_association.household_units.find(params[:household_unit_id])
          existing.update!(verified_residence: verified_residence)
          existing
        else
          HouseholdUnit.create!(
            neighborhood_delegation: delegation,
            commune: residence_req.commune,
            number: residence_req.number,
            street_name: residence_req.street_name,
            address_detail: residence_req.address_detail,
            verified_residence: verified_residence
          )
        end

        # 6. Create Residency
        Residency.create!(
          verified_identity: verified_identity,
          verified_residence: verified_residence,
          household_unit: household_unit,
          household_admin: true,
          status: "approved"
        )

        # 7. Create Member (association membership)
        Member.create!(
          verified_identity: verified_identity,
          neighborhood_association: @onboarding_request.neighborhood_association,
          status: "approved",
          requested_by: user,
          approved_by: current_user,
          approved_at: Time.current
        )

        # 8. Approve the onboarding request
        @onboarding_request.update!(status: "approved")
      end

      redirect_to admin_onboarding_request_path(@onboarding_request),
        notice: I18n.t("admin.onboarding_reviews.flash.approved")
    end

    def reject
      ActiveRecord::Base.transaction do
        @onboarding_request.update!(status: "rejected", rejection_reason: params[:rejection_reason])
        @onboarding_request.identity_verification_request&.update!(status: "rejected")
        @onboarding_request.residence_verification_request&.update!(status: "rejected")
      end

      redirect_to admin_onboarding_request_path(@onboarding_request),
        notice: I18n.t("admin.onboarding_reviews.flash.rejected")
    end

    private

    def set_onboarding_request
      @onboarding_request = current_neighborhood_association
        .onboarding_requests
        .where.not(status: "draft")
        .find(params[:id])
    end

    def ensure_pending!
      unless @onboarding_request.pending?
        redirect_to admin_onboarding_request_path(@onboarding_request),
          alert: I18n.t("admin.onboarding_reviews.flash.not_pending")
      end
    end
  end
end
