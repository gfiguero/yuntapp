require "test_helper"

module Webhooks
  class MercadopagoControllerTest < ActionDispatch::IntegrationTest
    SECRET = "test-webhook-secret".freeze

    setup do
      @original_secret = Rails.application.config.mercadopago[:webhook_secret]
      @original_token = Rails.application.config.mercadopago[:access_token]
      Rails.application.config.mercadopago[:webhook_secret] = SECRET
      Rails.application.config.mercadopago[:access_token] = "TEST-token"

      @certificate = ResidenceCertificate.create!(
        member: members(:selendis_member),
        household_unit: household_units(:selendis_household),
        neighborhood_association: neighborhood_associations(:manios_de_buin),
        purpose: "trámite bancario",
        amount: 1500,
        status: "pending_payment"
      )
    end

    teardown do
      Rails.application.config.mercadopago[:webhook_secret] = @original_secret
      Rails.application.config.mercadopago[:access_token] = @original_token
    end

    def valid_signature_header(data_id:, ts: "1700000000", request_id: "req-1")
      manifest = if request_id.present?
        "id:#{data_id};request-id:#{request_id};ts:#{ts};"
      else
        "id:#{data_id};ts:#{ts};"
      end
      hash = OpenSSL::HMAC.hexdigest("sha256", SECRET, manifest)
      "ts=#{ts},v1=#{hash}"
    end

    def stub_fetch_payment(payment, &block)
      real_service = MercadopagoService.new
      fake = Object.new
      fake.define_singleton_method(:verify_signature) { |**kw| real_service.verify_signature(**kw) }
      fake.define_singleton_method(:fetch_payment) { |_payment_id| payment }
      stub_class_method(MercadopagoService, :new, fake, &block)
    end

    # --- Signature verification (BR-072) ---

    test "returns 401 when signature is missing" do
      post webhooks_mercadopago_url,
        params: {topic: "payment", data: {id: "MP-PAY-123"}}
      assert_response :unauthorized
    end

    test "returns 401 when signature is invalid" do
      post webhooks_mercadopago_url,
        params: {topic: "payment", data: {id: "MP-PAY-123"}},
        headers: {
          "x-signature" => "ts=123,v1=deadbeef",
          "x-request-id" => "req-1"
        }
      assert_response :unauthorized
    end

    test "returns 200 with valid signature but no external_reference (no-op)" do
      sig = valid_signature_header(data_id: "MP-PAY-999")

      stub_fetch_payment({"id" => "MP-PAY-999", "status" => "approved"}) do
        post webhooks_mercadopago_url,
          params: {topic: "payment", data: {id: "MP-PAY-999"}},
          headers: {"x-signature" => sig, "x-request-id" => "req-1"}
      end

      assert_response :ok
      @certificate.reload
      assert_equal "pending_payment", @certificate.status
    end

    # --- Happy path: approved ---

    test "marks certificate as paid when MP returns status approved" do
      sig = valid_signature_header(data_id: "MP-PAY-OK")

      stub_fetch_payment({
        "id" => "MP-PAY-OK",
        "status" => "approved",
        "external_reference" => @certificate.id.to_s
      }) do
        post webhooks_mercadopago_url,
          params: {topic: "payment", data: {id: "MP-PAY-OK"}},
          headers: {"x-signature" => sig, "x-request-id" => "req-1"}
      end

      assert_response :ok
      @certificate.reload
      assert @certificate.paid?
      assert_equal "MP-PAY-OK", @certificate.payment_id
      assert_not_nil @certificate.paid_at
    end

    # --- BR-073: rejected payment does NOT mark as paid ---

    test "does not mark as paid when MP returns status rejected" do
      sig = valid_signature_header(data_id: "MP-PAY-REJ")

      stub_fetch_payment({
        "id" => "MP-PAY-REJ",
        "status" => "rejected",
        "external_reference" => @certificate.id.to_s
      }) do
        post webhooks_mercadopago_url,
          params: {topic: "payment", data: {id: "MP-PAY-REJ"}},
          headers: {"x-signature" => sig, "x-request-id" => "req-1"}
      end

      assert_response :ok
      @certificate.reload
      assert @certificate.pending_payment?
      assert_nil @certificate.payment_id
    end

    test "does not mark as paid when MP returns status pending" do
      sig = valid_signature_header(data_id: "MP-PAY-PEND")

      stub_fetch_payment({
        "id" => "MP-PAY-PEND",
        "status" => "pending",
        "external_reference" => @certificate.id.to_s
      }) do
        post webhooks_mercadopago_url,
          params: {topic: "payment", data: {id: "MP-PAY-PEND"}},
          headers: {"x-signature" => sig, "x-request-id" => "req-1"}
      end

      assert_response :ok
      @certificate.reload
      assert @certificate.pending_payment?
    end

    # --- BR-071: idempotency ---

    test "ignores duplicate webhook for already-processed payment_id (BR-071)" do
      @certificate.update!(status: "paid", payment_id: "MP-PAY-DUP", paid_at: 1.hour.ago)
      original_paid_at = @certificate.paid_at

      sig = valid_signature_header(data_id: "MP-PAY-DUP")

      called = false
      real_service = MercadopagoService.new
      fake = Object.new
      fake.define_singleton_method(:verify_signature) { |**kw| real_service.verify_signature(**kw) }
      fake.define_singleton_method(:fetch_payment) { |_|
        called = true
        {}
      }

      stub_class_method(MercadopagoService, :new, fake) do
        post webhooks_mercadopago_url,
          params: {topic: "payment", data: {id: "MP-PAY-DUP"}},
          headers: {"x-signature" => sig, "x-request-id" => "req-1"}
      end

      assert_response :ok
      assert_not called, "fetch_payment should NOT be called when payment_id already exists"
      @certificate.reload
      assert_equal original_paid_at.to_i, @certificate.paid_at.to_i
    end

    # --- Certificate not found ---

    test "returns 200 (no-op) when external_reference points to nonexistent certificate" do
      sig = valid_signature_header(data_id: "MP-PAY-ORPHAN")

      stub_fetch_payment({
        "id" => "MP-PAY-ORPHAN",
        "status" => "approved",
        "external_reference" => "999999"
      }) do
        post webhooks_mercadopago_url,
          params: {topic: "payment", data: {id: "MP-PAY-ORPHAN"}},
          headers: {"x-signature" => sig, "x-request-id" => "req-1"}
      end

      assert_response :ok
    end

    # --- payment_id extraction ---

    test "extracts payment_id from resource URL format" do
      sig = valid_signature_header(data_id: "MP-PAY-FROM-URL")

      stub_fetch_payment({
        "id" => "MP-PAY-FROM-URL",
        "status" => "approved",
        "external_reference" => @certificate.id.to_s
      }) do
        post webhooks_mercadopago_url,
          params: {topic: "payment", resource: "/v1/payments/MP-PAY-FROM-URL"},
          headers: {"x-signature" => sig, "x-request-id" => "req-1"}
      end

      assert_response :ok
      @certificate.reload
      assert @certificate.paid?
      assert_equal "MP-PAY-FROM-URL", @certificate.payment_id
    end

    # --- MP WebHook v1.0 (type en body, sin topic) ---

    test "handles MP v1.0 format with type in body (no topic param)" do
      sig = valid_signature_header(data_id: "MP-PAY-V1")

      stub_fetch_payment({
        "id" => "MP-PAY-V1",
        "status" => "approved",
        "external_reference" => @certificate.id.to_s
      }) do
        post webhooks_mercadopago_url,
          params: {type: "payment", data: {id: "MP-PAY-V1"}},
          headers: {"x-signature" => sig, "x-request-id" => "req-1"}
      end

      assert_response :ok
      @certificate.reload
      assert @certificate.paid?
      assert_equal "MP-PAY-V1", @certificate.payment_id
    end

    # --- Feed v2.0 payment sin x-request-id ---

    test "handles Feed v2.0 payment notification without x-request-id" do
      sig = valid_signature_header(data_id: "MP-PAY-V2", request_id: nil)

      stub_fetch_payment({
        "id" => "MP-PAY-V2",
        "status" => "approved",
        "external_reference" => @certificate.id.to_s
      }) do
        post webhooks_mercadopago_url,
          params: {topic: "payment", id: "MP-PAY-V2"},
          headers: {"x-signature" => sig}
      end

      assert_response :ok
      @certificate.reload
      assert @certificate.paid?
      assert_equal "MP-PAY-V2", @certificate.payment_id
    end

    # --- Handle v2 prefix in signature ---

    test "accepts signature with v2 prefix" do
      ts = "1700000000"
      data_id = "MP-PAY-V2PREFIX"
      manifest = "id:#{data_id};ts:#{ts};"
      hash = OpenSSL::HMAC.hexdigest("sha256", SECRET, manifest)

      stub_fetch_payment({
        "id" => "MP-PAY-V2PREFIX",
        "status" => "approved",
        "external_reference" => @certificate.id.to_s
      }) do
        post webhooks_mercadopago_url,
          params: {topic: "payment", id: "MP-PAY-V2PREFIX"},
          headers: {"x-signature" => "ts=#{ts},v2=#{hash}"}
      end

      assert_response :ok
      @certificate.reload
      assert @certificate.paid?
      assert_equal "MP-PAY-V2PREFIX", @certificate.payment_id
    end
  end
end
