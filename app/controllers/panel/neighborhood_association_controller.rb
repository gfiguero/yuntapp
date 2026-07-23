module Panel
  class NeighborhoodAssociationController < ApplicationController
    layout "panel"
    before_action :authenticate_user!

    # Información general de la junta a la que pertenece el socio.
    # Solo lectura y siempre acotada a la junta del member activo del
    # usuario (BR-007: nunca datos de otras juntas).
    def show
      @association = current_user.member&.neighborhood_association

      if @association.nil?
        redirect_to panel_root_path, alert: I18n.t("panel.neighborhood_association.flash.not_member")
        return
      end

      @board_members = @association.board_members.active
        .includes(member: :verified_identity)
        .sort_by { |bm| BoardMember::POSITIONS.index(bm.position) || BoardMember::POSITIONS.size }
      @delegations = @association.neighborhood_delegations.order(:name)
      @approved_members_count = @association.members.approved.count
      @current_price = @association.current_certificate_price
    end
  end
end
