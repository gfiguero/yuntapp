module Panel
  class OnboardingController < ApplicationController
    layout "panel"
    before_action :authenticate_user!
    before_action :redirect_if_onboarded!
    before_action :ensure_step1!, only: [:step2, :update_step2, :step3, :update_step3, :step4, :submit]
    before_action :ensure_step2!, only: [:step3, :update_step3, :step4, :submit]
    before_action :ensure_step3!, only: [:step4, :submit]

    def step1
      @cascading_data = build_cascading_data
    end

    def update_step1
      association = NeighborhoodAssociation.find(params[:neighborhood_association_id])
      session[:onboarding] = { "neighborhood_association_id" => association.id }
      redirect_to panel_onboarding_step2_path
    end

    def step2
      @neighborhood_association = NeighborhoodAssociation.find(session.dig(:onboarding, "neighborhood_association_id"))
      @delegations = @neighborhood_association.neighborhood_delegations.order(:name)
      @household_unit = HouseholdUnit.new
    end

    def update_step2
      @neighborhood_association = NeighborhoodAssociation.find(session.dig(:onboarding, "neighborhood_association_id"))
      @delegations = @neighborhood_association.neighborhood_delegations.order(:name)
      @household_unit = HouseholdUnit.new(household_unit_params)

      if @household_unit.save
        session[:onboarding]["household_unit_id"] = @household_unit.id
        redirect_to panel_onboarding_step3_path
      else
        render :step2, status: :unprocessable_content
      end
    end

    def step3
      if current_user.persona&.verified?
        redirect_to panel_onboarding_step4_path
        return
      end

      @persona = current_user.persona || Persona.new
    end

    def update_step3
      if current_user.persona&.verified?
        redirect_to panel_onboarding_step4_path
        return
      end

      run = normalize_run(params[:persona][:run])
      @persona = Persona.find_by(run: run)

      if @persona.present? && @persona.user.present? && @persona.user != current_user
        redirect_to panel_onboarding_step3_path, alert: I18n.t("persona.message.run_already_claimed")
        return
      end

      @persona ||= Persona.new

      @persona.assign_attributes(verification_params)
      @persona.verification_status = "pending"

      if @persona.save
        @persona.identity_document.attach(params[:persona][:identity_document]) if params[:persona][:identity_document].present?
        current_user.update!(persona: @persona)
        redirect_to panel_onboarding_step4_path
      else
        render :step3, status: :unprocessable_content
      end
    end

    def step4
      @neighborhood_association = NeighborhoodAssociation.find(session.dig(:onboarding, "neighborhood_association_id"))
      @household_unit = HouseholdUnit.find(session.dig(:onboarding, "household_unit_id"))
      @persona = current_user.persona
    end

    def submit
      household_unit = HouseholdUnit.find(session.dig(:onboarding, "household_unit_id"))

      @member = Member.new
      @member.persona = current_user.persona
      @member.household_unit = household_unit
      @member.requested_by = current_user
      @member.status = "pending"

      if @member.save
        session.delete(:onboarding)
        redirect_to panel_root_path, notice: I18n.t("onboarding.message.completed")
      else
        redirect_to panel_onboarding_step4_path, alert: "Error al enviar la solicitud."
      end
    end

    private

    def redirect_if_onboarded!
      redirect_to panel_root_path if current_user.member.present?
    end

    def ensure_step1!
      redirect_to panel_onboarding_step1_path unless session.dig(:onboarding, "neighborhood_association_id").present?
    end

    def ensure_step2!
      redirect_to panel_onboarding_step2_path unless session.dig(:onboarding, "household_unit_id").present?
    end

    def ensure_step3!
      redirect_to panel_onboarding_step3_path unless current_user.persona.present?
    end

    def normalize_run(value)
      cleaned = value.to_s.gsub(/[.\-\s]/, "").upcase
      if cleaned.match?(/\A\d{7,8}[0-9K]\z/)
        "#{cleaned[0..-2]}-#{cleaned[-1]}"
      else
        cleaned
      end
    end

    def verification_params
      params.require(:persona).permit(:first_name, :last_name, :run, :phone)
    end

    def household_unit_params
      params.require(:household_unit).permit(:number, :address_line_1, :address_line_2, :city, :region, :country, :postal_code, :neighborhood_delegation_id, :commune_id)
    end

    def build_cascading_data
      associations_by_commune = NeighborhoodAssociation.where.not(commune_id: nil).order(:name).group_by(&:commune_id)
      commune_ids = associations_by_commune.keys
      communes = Commune.where(id: commune_ids).order(:name).includes(:region)

      communes.group_by { |c| c.region }.map do |region, region_communes|
        {
          id: region.id,
          name: region.name,
          communes: region_communes.sort_by(&:name).map do |commune|
            {
              id: commune.id,
              name: commune.name,
              associations: (associations_by_commune[commune.id] || []).map do |assoc|
                { id: assoc.id, name: assoc.name }
              end
            }
          end
        }
      end.sort_by { |r| r[:name] }
    end
  end
end
