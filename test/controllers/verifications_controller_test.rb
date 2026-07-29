require "test_helper"

class VerificationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    Rack::Attack.cache.store.clear
    @member = members(:selendis_member)
    @household_unit = household_units(:selendis_household)
    @association = neighborhood_associations(:manios_de_buin)
  end

  def issued_cert(token: SecureRandom.uuid, code: SecureRandom.alphanumeric(8).upcase, expiration: Date.current + 30.days)
    ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      status: "issued",
      folio: "CR-1-#{rand(1_000_000)}",
      validation_token: token,
      validation_code: code,
      issue_date: Date.current,
      expiration_date: expiration,
      issued_at: Time.current
    )
  end

  # --- No auth required ---

  test "index is accessible without authentication" do
    get verify_url
    assert_response :success
  end

  test "lookup is accessible without authentication" do
    post verify_url, params: {identifier: ""}
    assert_redirected_to verify_url
  end

  # --- Index renders form ---

  test "index renders the verification form" do
    get verify_url
    assert_response :success
    assert_match I18n.t("verifications.index.submit"), @response.body
  end

  # --- Lookup ---

  test "lookup redirects to show with sanitized identifier" do
    post verify_url, params: {identifier: "  ABCD1234  "}
    assert_redirected_to verification_url(identifier: "ABCD1234")
  end

  test "lookup redirects back with alert when identifier is blank" do
    post verify_url, params: {identifier: ""}
    assert_redirected_to verify_url
    assert_equal I18n.t("verifications.flash.missing_identifier"), flash[:alert]
  end

  # --- Show happy path ---

  test "show by validation_token returns 200 with cert data" do
    cert = issued_cert
    get verification_url(identifier: cert.validation_token)
    assert_response :success
    assert_match cert.folio, @response.body
    assert_match cert.member.name, @response.body
    assert_match I18n.t("verifications.show.status.valid_badge"), @response.body
  end

  test "show by validation_code returns 200 with cert data" do
    cert = issued_cert(code: "ABCD1234")
    get verification_url(identifier: "ABCD1234")
    assert_response :success
    assert_match cert.folio, @response.body
  end

  test "show is case-insensitive for validation_code" do
    cert = issued_cert(code: "EFGH5678")
    get verification_url(identifier: "efgh5678")
    assert_response :success
    assert_match cert.folio, @response.body
  end

  # --- Privacy: RUN masked (BR-078) ---

  test "show masks the RUN" do
    cert = issued_cert
    # selendis_persona has run "11111111-1"
    get verification_url(identifier: cert.validation_token)
    assert_response :success
    assert_match "1.XXX.XXX-1", @response.body
    assert_no_match(/11111111-1/, @response.body)
  end

  # --- Expired cert (BR-009, BR-080) ---

  test "show returns 200 with expired badge for past expiration_date" do
    cert = issued_cert(expiration: 1.month.ago)
    get verification_url(identifier: cert.validation_token)
    assert_response :success
    assert_match I18n.t("verifications.show.status.expired_badge"), @response.body
    assert_no_match(/#{I18n.t("verifications.show.status.valid_badge")}/, @response.body)
  end

  # --- Deactivated holder (BR-091) ---

  test "show returns 200 with revoked badge when holder was deactivated" do
    cert = issued_cert
    @member.deactivate!(reason: "ya no reside en el domicilio")

    get verification_url(identifier: cert.validation_token)
    assert_response :success
    assert_match I18n.t("verifications.show.status.revoked_badge"), @response.body
    assert_no_match(/#{I18n.t("verifications.show.status.valid_badge")}/, @response.body)
  end

  test "revoked state takes precedence over expired" do
    cert = issued_cert(expiration: 1.month.ago)
    @member.deactivate!(reason: "fraude detectado")

    get verification_url(identifier: cert.validation_token)
    assert_response :success
    assert_match I18n.t("verifications.show.status.revoked_badge"), @response.body
    assert_no_match(/#{I18n.t("verifications.show.status.expired_badge")}/, @response.body)
  end

  # --- Reverted payment (BR-141) ---

  test "reverted certificate shows as No válido (reverted) with 200 and neutral text" do
    token = SecureRandom.uuid
    cert = ResidenceCertificate.create!(
      member: members(:selendis_member), household_unit: household_units(:selendis_household),
      neighborhood_association: neighborhood_associations(:manios_de_buin), purpose: "t",
      status: "issued", folio: "CR-1-7001", validation_token: token, validation_code: "REVRT123",
      issue_date: Date.current, expiration_date: 30.days.from_now.to_date, issued_at: Time.current,
      payment_status: "charged_back"
    )
    get verification_url(identifier: cert.validation_token)
    assert_response :ok
    # BR-141: usa la key reverted_badge (texto neutro, no expone motivo al verificador)
    assert_match I18n.t("verifications.show.status.reverted_badge"), @response.body
    # No debe aparecer el texto de "socio no activo" (eso es BR-091, no una reversión de pago)
    assert_no_match(/socio activo/, @response.body)
  end

  # --- 404 paths ---

  test "show returns 404 for unknown UUID" do
    get verification_url(identifier: SecureRandom.uuid)
    assert_response :not_found
    assert_match I18n.t("verifications.not_found.title"), @response.body
  end

  test "show returns 404 for unknown 8-char code" do
    get verification_url(identifier: "ZZZZZZZZ")
    assert_response :not_found
  end

  test "show returns 404 for malformed identifier" do
    get verification_url(identifier: "not-a-valid-format")
    assert_response :not_found
  end

  # --- BR-081: non-issued certs are never exposed ---

  test "show returns 404 when cert is in pending_payment status" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "test",
      status: "pending_payment",
      validation_token: SecureRandom.uuid,
      validation_code: "NOEXPOSE"
    )

    get verification_url(identifier: cert.validation_token)
    assert_response :not_found

    get verification_url(identifier: cert.validation_code)
    assert_response :not_found
  end

  test "show returns 404 when cert is in paid status (BR-081)" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "test",
      status: "paid",
      amount: 1500,
      payment_id: "MP-NOTYET",
      paid_at: Time.current,
      validation_token: SecureRandom.uuid,
      validation_code: "PAIDONLY"
    )

    get verification_url(identifier: cert.validation_token)
    assert_response :not_found
  end

  # --- Rate limiting (Rack::Attack) ---

  test "rate limits 11th request from same IP within 1 minute" do
    Rack::Attack.cache.store.clear

    10.times do
      get verify_url
      assert_response :success
    end

    get verify_url
    assert_response :too_many_requests
    assert_match(/segundos/, @response.body)
    assert_not_nil @response.headers["Retry-After"]
  end

  test "rate limit applies to /verify/:identifier too" do
    Rack::Attack.cache.store.clear
    bad_id = "ZZZZZZZZ"

    10.times do
      get verification_url(identifier: bad_id)
      assert_response :not_found
    end

    get verification_url(identifier: bad_id)
    assert_response :too_many_requests
  end

  test "rate limit resets after the window expires" do
    Rack::Attack.cache.store.clear

    10.times { get verify_url }
    get verify_url
    assert_response :too_many_requests

    # Avanzar el tiempo más allá de la ventana de 60s
    travel 61.seconds do
      get verify_url
      assert_response :success
    end
  end
end
