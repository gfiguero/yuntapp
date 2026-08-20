require "test_helper"

# BR-048/BR-049: duplicar una solicitud resuelta para corregir solo lo necesario.
class OnboardingRequestDuplicateTest < ActiveSupport::TestCase
  setup do
    @request = onboarding_requests(:karass_pending)
    @request.update!(status: "rejected", rejection_reason: "Documento ilegible")
  end

  test "duplicable? solo para rechazadas y canceladas" do
    assert @request.duplicable?

    @request.update!(status: "cancelled", rejection_reason: nil)
    assert @request.duplicable?

    @request.update_columns(status: "pending")
    assert_not @request.reload.duplicable?

    @request.update_columns(status: "draft")
    assert_not @request.reload.duplicable?

    @request.update_columns(status: "approved")
    assert_not @request.reload.duplicable?
  end

  test "duplicate! crea una nueva solicitud en draft" do
    copy = @request.duplicate!

    assert_equal "draft", copy.status
    assert_not_equal @request.id, copy.id
    assert_equal @request.user, copy.user
    assert_equal @request.neighborhood_association, copy.neighborhood_association
    assert_equal @request.region, copy.region
    assert_equal @request.commune, copy.commune
  end

  test "duplicate! deja intacta la solicitud original" do
    @request.duplicate!
    @request.reload

    assert_equal "rejected", @request.status
    assert_equal "Documento ilegible", @request.rejection_reason
    assert_not_nil @request.identity_verification_request
    assert_not_nil @request.residence_verification_request
  end

  test "duplicate! copia los datos de identidad sin el estado ni el rechazo" do
    original = @request.identity_verification_request
    original.update!(rejection_reason: "Foto borrosa", status: "rejected")

    copy = @request.duplicate!.identity_verification_request

    assert_equal original.first_name, copy.first_name
    assert_equal original.last_name, copy.last_name
    assert_equal original.run, copy.run
    assert_equal original.phone, copy.phone
    assert_equal "draft", copy.status
    assert_nil copy.rejection_reason
  end

  test "duplicate! copia los datos de domicilio" do
    fields = %w[
      commune_id neighborhood_association_id neighborhood_delegation_id
      street_name number address_detail manual_address
    ]
    original = @request.residence_verification_request
    copy = @request.duplicate!.residence_verification_request

    assert_equal original.attributes.slice(*fields), copy.attributes.slice(*fields)
    assert_equal "draft", copy.status
  end

  # Decision de producto: los documentos NO se copian. El rechazo suele deberse a
  # un documento ilegible o incorrecto, y recopiarlo invita a reenviar el mismo
  # problema.
  test "duplicate! no copia los documentos adjuntos" do
    original = @request.identity_verification_request
    original.identity_documents.attach(
      io: StringIO.new("documento"), filename: "ci.png", content_type: "image/png"
    )
    assert original.reload.identity_documents.attached?

    copy = @request.duplicate!.identity_verification_request
    assert_not copy.identity_documents.attached?
  end

  # BR-015: los terminos se aceptan al enviar, no se heredan de la solicitud vieja.
  test "duplicate! no arrastra la aceptacion de terminos" do
    @request.update_columns(terms_accepted_at: Time.current)
    assert_nil @request.duplicate!.terms_accepted_at
  end

  # Si la copia del domicilio falla, la OnboardingRequest y la identidad ya
  # creadas deben revertirse: nada de solicitudes a medias en el historial.
  test "duplicate! es atomico: no deja una solicitud a medias si algo falla" do
    @request.define_singleton_method(:duplicate_residence_request_into) do |_copy|
      raise ActiveRecord::RecordInvalid, ResidenceVerificationRequest.new
    end

    assert_no_difference ["OnboardingRequest.count", "IdentityVerificationRequest.count"] do
      assert_raises(ActiveRecord::RecordInvalid) { @request.duplicate! }
    end
  end

  test "duplicate! rechaza una solicitud que no es duplicable" do
    @request.update_columns(status: "approved")

    assert_raises(OnboardingRequest::NotDuplicableError) { @request.reload.duplicate! }
  end
end
