module Admin
  class DependentReviewsController < Admin::ApplicationController
    before_action :set_dependent_request, only: [ :show, :approve, :reject ]
    before_action :ensure_pending!, only: [ :approve, :reject ]

    # GET /admin/dependent_reviews
    def index
      @dependent_requests = current_neighborhood_association
        .identity_verification_requests
        .dependent_requests
        .where.not(status: "draft")
        .order(created_at: :desc)
    end

    # GET /admin/dependent_reviews/:id
    def show
    end

    # PATCH /admin/dependent_reviews/:id/approve
    def approve
      ActiveRecord::Base.transaction do
        @dependent_request.update!(status: "approved")

        verified_identity = VerifiedIdentity.find_or_initialize_by(run: @dependent_request.run)
        verified_identity.assign_attributes(
          first_name: @dependent_request.first_name,
          last_name: @dependent_request.last_name,
          phone: @dependent_request.phone,
          identity_verification_request: @dependent_request
        )
        verified_identity.save!

        if @dependent_request.identity_documents.attached? && !verified_identity.identity_document.attached?
          verified_identity.identity_document.attach(@dependent_request.identity_documents.first.blob)
        end

        family_group = @dependent_request.family_group
        household_unit = family_group.household_unit
        verified_residence = household_unit.verified_residence

        Residency.create!(
          verified_identity: verified_identity,
          verified_residence: verified_residence,
          household_unit: household_unit,
          family_group: family_group,
          household_admin: false,
          status: "approved"
        )

        Member.create!(
          verified_identity: verified_identity,
          neighborhood_association: @dependent_request.neighborhood_association,
          status: "approved",
          dependent: true,
          requested_by: current_user,
          approved_by: current_user,
          approved_at: Time.current
        )
      end

      redirect_to admin_dependent_reviews_path,
        notice: I18n.t("admin.dependent_reviews.flash.approved")
    end

    # PATCH /admin/dependent_reviews/:id/reject
    def reject
      @dependent_request.update!(
        status: "rejected",
        rejection_reason: params[:rejection_reason]
      )

      redirect_to admin_dependent_reviews_path,
        notice: I18n.t("admin.dependent_reviews.flash.rejected")
    end

    private

    def set_dependent_request
      @dependent_request = current_neighborhood_association
        .identity_verification_requests
        .dependent_requests
        .where.not(status: "draft")
        .find(params[:id])
    end

    def ensure_pending!
      unless @dependent_request.pending?
        redirect_to admin_dependent_reviews_path,
          alert: I18n.t("admin.dependent_reviews.flash.not_pending")
      end
    end
  end
end
