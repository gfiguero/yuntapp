require "test_helper"

class MercadopagoServiceTest < ActiveSupport::TestCase
  SECRET = "test-secret-for-webhook-verification".freeze

  setup do
    @service = MercadopagoService.new(access_token: "TEST-token", webhook_secret: SECRET)
  end

  # --- verify_signature ---

  test "returns true for valid signature" do
    ts = "1700000000"
    data_id = "MP-PAY-123"
    request_id = "abc-req-id"
    manifest = "id:#{data_id};request-id:#{request_id};ts:#{ts};"
    valid_hash = OpenSSL::HMAC.hexdigest("sha256", SECRET, manifest)

    assert @service.verify_signature(
      signature_header: "ts=#{ts},v1=#{valid_hash}",
      request_id: request_id,
      data_id: data_id
    )
  end

  test "returns false for tampered hash" do
    ts = "1700000000"
    data_id = "MP-PAY-123"
    request_id = "abc-req-id"

    assert_not @service.verify_signature(
      signature_header: "ts=#{ts},v1=ffffffff",
      request_id: request_id,
      data_id: data_id
    )
  end

  test "returns false when data_id mismatches manifest" do
    ts = "1700000000"
    data_id = "MP-PAY-123"
    request_id = "abc-req-id"
    manifest = "id:#{data_id};request-id:#{request_id};ts:#{ts};"
    valid_hash = OpenSSL::HMAC.hexdigest("sha256", SECRET, manifest)

    assert_not @service.verify_signature(
      signature_header: "ts=#{ts},v1=#{valid_hash}",
      request_id: request_id,
      data_id: "MP-DIFFERENT"
    )
  end

  test "returns false when signature_header is blank" do
    assert_not @service.verify_signature(
      signature_header: "",
      request_id: "req-id",
      data_id: "MP-PAY-123"
    )
  end

  test "returns false when ts is missing" do
    assert_not @service.verify_signature(
      signature_header: "v1=abc123",
      request_id: "req-id",
      data_id: "MP-PAY-123"
    )
  end

  test "returns false when v1 is missing" do
    assert_not @service.verify_signature(
      signature_header: "ts=1700000000",
      request_id: "req-id",
      data_id: "MP-PAY-123"
    )
  end

  test "returns false when webhook_secret is not configured" do
    service = MercadopagoService.new(access_token: "TEST", webhook_secret: nil)
    assert_not service.verify_signature(
      signature_header: "ts=1700000000,v1=abc",
      request_id: "req-id",
      data_id: "MP-PAY-123"
    )
  end

  # --- optional request_id (Feed v2.0) ---

  test "verifies signature without request_id" do
    ts = "1700000000"
    data_id = "MP-PAY-NOREQID"
    manifest = "id:#{data_id};ts:#{ts};"
    valid_hash = OpenSSL::HMAC.hexdigest("sha256", SECRET, manifest)

    assert @service.verify_signature(
      signature_header: "ts=#{ts},v1=#{valid_hash}",
      request_id: nil,
      data_id: data_id
    )
  end

  test "verifies signature without request_id when x-request-id is blank string" do
    ts = "1700000000"
    data_id = "MP-PAY-BLANKREQID"
    manifest = "id:#{data_id};ts:#{ts};"
    valid_hash = OpenSSL::HMAC.hexdigest("sha256", SECRET, manifest)

    assert @service.verify_signature(
      signature_header: "ts=#{ts},v1=#{valid_hash}",
      request_id: "",
      data_id: data_id
    )
  end

  test "rejects tampered signature without request_id" do
    ts = "1700000000"
    data_id = "MP-PAY-NOREQID"

    assert_not @service.verify_signature(
      signature_header: "ts=#{ts},v1=deadbeef",
      request_id: nil,
      data_id: data_id
    )
  end

  # --- v2 prefix ---

  test "verifies signature with v2 prefix" do
    ts = "1700000000"
    data_id = "MP-PAY-V2"
    manifest = "id:#{data_id};ts:#{ts};"
    valid_hash = OpenSSL::HMAC.hexdigest("sha256", SECRET, manifest)

    assert @service.verify_signature(
      signature_header: "ts=#{ts},v2=#{valid_hash}",
      request_id: nil,
      data_id: data_id
    )
  end

  # --- v1 takes precedence over v2 ---

  test "uses v1 over v2 when both are present" do
    ts = "1700000000"
    data_id = "MP-PAY-BOTH"
    manifest = "id:#{data_id};ts:#{ts};"
    correct_hash = OpenSSL::HMAC.hexdigest("sha256", SECRET, manifest)
    wrong_hash = "fff"

    assert @service.verify_signature(
      signature_header: "ts=#{ts},v1=#{correct_hash},v2=#{wrong_hash}",
      request_id: nil,
      data_id: data_id
    )
  end

  # --- ConfigurationError when access_token missing ---
  # MercadopagoService.new hace fallback a Rails.application.config.mercadopago
  # cuando el arg es nil. Para probar el caso "sin credenciales" de forma
  # determinista (independiente de si el entorno tiene credenciales cargadas),
  # forzamos la config en blanco durante el bloque.

  test "create_preference raises ConfigurationError when access_token blank" do
    with_blank_mercadopago_config do
      service = MercadopagoService.new(access_token: nil, webhook_secret: SECRET)
      cert = ResidenceCertificate.new(id: 1, amount: 1500)

      assert_raises(MercadopagoService::ConfigurationError) do
        service.create_preference(cert,
          success_url: "https://x.test/s",
          failure_url: "https://x.test/f",
          pending_url: "https://x.test/p",
          notification_url: "https://x.test/n")
      end
    end
  end

  test "fetch_payment raises ConfigurationError when access_token blank" do
    with_blank_mercadopago_config do
      service = MercadopagoService.new(access_token: nil, webhook_secret: SECRET)
      assert_raises(MercadopagoService::ConfigurationError) do
        service.fetch_payment("MP-XYZ")
      end
    end
  end

  private

  # Fuerza config.mercadopago en blanco durante el bloque y la restaura después,
  # para que el fallback del servicio no tome credenciales reales del entorno.
  def with_blank_mercadopago_config
    original = Rails.application.config.mercadopago
    Rails.application.config.mercadopago = {access_token: nil, webhook_secret: nil}
    yield
  ensure
    Rails.application.config.mercadopago = original
  end
end
