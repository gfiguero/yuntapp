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

  # --- ConfigurationError when access_token missing ---

  test "create_preference raises ConfigurationError when access_token blank" do
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

  test "fetch_payment raises ConfigurationError when access_token blank" do
    service = MercadopagoService.new(access_token: nil, webhook_secret: SECRET)
    assert_raises(MercadopagoService::ConfigurationError) do
      service.fetch_payment("MP-XYZ")
    end
  end
end
