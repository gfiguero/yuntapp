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
    # Se rechaza con 401 solo cuando x-signature está presente pero es inválida.
    # Si no hay firma (Feed v2.0) se procesa igual — la API de MP es la validación real.

    test "returns 200 when signature is not present (Feed v2.0)" do
      stub_fetch_payment({"id" => "MP-PAY-123", "status" => "approved", "external_reference" => nil}) do
        post webhooks_mercadopago_url,
          params: {topic: "payment", id: "MP-PAY-123"}
      end
      assert_response :ok
    end

    test "returns 401 when signature is present but invalid" do
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
        "transaction_amount" => 1500,
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
        "transaction_amount" => 1500,
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
        "transaction_amount" => 1500,
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
        "transaction_amount" => 1500,
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
        "transaction_amount" => 1500,
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
        "transaction_amount" => 1500,
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
        "transaction_amount" => 1500,
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
        "transaction_amount" => 1500,
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

    # --- BR-090: validación de monto ---

    test "rejects payment with amount different from certificate amount (BR-090)" do
      sig = valid_signature_header(data_id: "MP-PAY-BADAMT")

      stub_fetch_payment({
        "id" => "MP-PAY-BADAMT",
        "transaction_amount" => 2000,
        "status" => "approved",
        "external_reference" => @certificate.id.to_s
      }) do
        post webhooks_mercadopago_url,
          params: {topic: "payment", data: {id: "MP-PAY-BADAMT"}},
          headers: {"x-signature" => sig, "x-request-id" => "req-1"}
      end

      assert_response :ok
      @certificate.reload
      assert @certificate.pending_payment?
      assert_nil @certificate.payment_id
    end

    test "rejects payment without transaction_amount (BR-090)" do
      sig = valid_signature_header(data_id: "MP-PAY-NOAMT")

      stub_fetch_payment({
        "id" => "MP-PAY-NOAMT",
        "status" => "approved",
        "external_reference" => @certificate.id.to_s
      }) do
        post webhooks_mercadopago_url,
          params: {topic: "payment", data: {id: "MP-PAY-NOAMT"}},
          headers: {"x-signature" => sig, "x-request-id" => "req-1"}
      end

      assert_response :ok
      @certificate.reload
      assert @certificate.pending_payment?
    end

    test "rejects listing payment with wrong amount (BR-090)" do
      listing = Listing.create!(name: "Webhook listing", user: users(:artanis), amount: 1200)
      sig = valid_signature_header(data_id: "MP-PAY-LSTBADAMT")

      stub_fetch_payment({
        "id" => "MP-PAY-LSTBADAMT",
        "transaction_amount" => 500,
        "status" => "approved",
        "external_reference" => "listing-#{listing.id}"
      }) do
        post webhooks_mercadopago_url,
          params: {topic: "payment", data: {id: "MP-PAY-LSTBADAMT"}},
          headers: {"x-signature" => sig, "x-request-id" => "req-1"}
      end

      assert_response :ok
      listing.reload
      assert listing.pending_payment?
      assert_nil listing.payment_id
    end

    # --- Publicaciones del marketplace (BR-083/BR-087) ---
    # external_reference "listing-<id>" enruta el pago a Listing.

    test "publishes listing when MP returns approved for listing reference" do
      listing = Listing.create!(name: "Webhook listing", user: users(:artanis), amount: 1200)
      sig = valid_signature_header(data_id: "MP-PAY-LST")

      stub_fetch_payment({
        "id" => "MP-PAY-LST",
        "transaction_amount" => 1200,
        "status" => "approved",
        "external_reference" => "listing-#{listing.id}"
      }) do
        post webhooks_mercadopago_url,
          params: {topic: "payment", data: {id: "MP-PAY-LST"}},
          headers: {"x-signature" => sig, "x-request-id" => "req-1"}
      end

      assert_response :ok
      listing.reload
      assert listing.published?
      assert_equal "MP-PAY-LST", listing.payment_id
      assert_equal Date.current + 30.days, listing.published_until
    end

    test "does not publish listing when MP returns rejected" do
      listing = Listing.create!(name: "Webhook listing", user: users(:artanis), amount: 1200)
      sig = valid_signature_header(data_id: "MP-PAY-LSTREJ")

      stub_fetch_payment({
        "id" => "MP-PAY-LSTREJ",
        "transaction_amount" => 1200,
        "status" => "rejected",
        "external_reference" => "listing-#{listing.id}"
      }) do
        post webhooks_mercadopago_url,
          params: {topic: "payment", data: {id: "MP-PAY-LSTREJ"}},
          headers: {"x-signature" => sig, "x-request-id" => "req-1"}
      end

      assert_response :ok
      listing.reload
      assert listing.pending_payment?
      assert_nil listing.payment_id
    end

    test "listing payment_id already processed is idempotent (BR-087)" do
      listing = Listing.create!(name: "Webhook listing", user: users(:artanis), amount: 1200)
      listing.mark_as_paid!(payment_id: "MP-PAY-DUP")
      original_until = listing.published_until
      sig = valid_signature_header(data_id: "MP-PAY-DUP")

      # fetch_payment no debería llamarse; si se llama y retorna approved,
      # mark_as_paid! con el mismo payment_id sigue siendo no-op.
      stub_fetch_payment({
        "id" => "MP-PAY-DUP",
        "status" => "approved",
        "external_reference" => "listing-#{listing.id}"
      }) do
        post webhooks_mercadopago_url,
          params: {topic: "payment", data: {id: "MP-PAY-DUP"}},
          headers: {"x-signature" => sig, "x-request-id" => "req-1"}
      end

      assert_response :ok
      assert_equal original_until, listing.reload.published_until
    end

    # --- Suscripciones (BR-088/BR-089) ---

    def stub_subscription_service(preapproval: nil, authorized_payment: nil, &block)
      fake = Object.new
      fake.define_singleton_method(:fetch_preapproval) { |_id| preapproval }
      fake.define_singleton_method(:fetch_authorized_payment) { |_id| authorized_payment }
      stub_class_method(MercadopagoService, :new, fake, &block)
    end

    test "subscription_preapproval syncs subscription status (BR-088)" do
      listing = Listing.create!(name: "Sub listing", user: users(:artanis), amount: 1200)

      stub_subscription_service(preapproval: {
        "id" => "PRE-1",
        "status" => "authorized",
        "external_reference" => "listing-#{listing.id}"
      }) do
        post webhooks_mercadopago_url,
          params: {type: "subscription_preapproval", data: {id: "PRE-1"}}
      end

      assert_response :ok
      listing.reload
      assert_equal "PRE-1", listing.preapproval_id
      assert listing.subscription_active?
    end

    test "subscription_preapproval syncs cancellation from MP" do
      listing = Listing.create!(name: "Sub listing", user: users(:artanis),
        amount: 1200, preapproval_id: "PRE-2", subscription_status: "authorized")

      stub_subscription_service(preapproval: {
        "id" => "PRE-2",
        "status" => "cancelled",
        "external_reference" => "listing-#{listing.id}"
      }) do
        post webhooks_mercadopago_url,
          params: {type: "subscription_preapproval", data: {id: "PRE-2"}}
      end

      assert_response :ok
      assert_equal "cancelled", listing.reload.subscription_status
    end

    test "subscription_authorized_payment approved renews the listing (BR-089)" do
      listing = Listing.create!(name: "Sub listing", user: users(:artanis),
        amount: 1200, preapproval_id: "PRE-3", subscription_status: "authorized")
      listing.mark_as_paid!(payment_id: "MP-FIRST")
      current_until = listing.published_until

      stub_subscription_service(authorized_payment: {
        "id" => "AUTHPAY-1",
        "preapproval_id" => "PRE-3",
        "payment" => {"id" => "MP-RECUR-1", "status" => "approved"}
      }) do
        post webhooks_mercadopago_url,
          params: {type: "subscription_authorized_payment", data: {id: "AUTHPAY-1"}}
      end

      assert_response :ok
      listing.reload
      assert_equal current_until + 30.days, listing.published_until
      assert_equal "MP-RECUR-1", listing.payment_id
    end

    test "subscription_authorized_payment rejected does not renew" do
      listing = Listing.create!(name: "Sub listing", user: users(:artanis),
        amount: 1200, preapproval_id: "PRE-4", subscription_status: "authorized")

      stub_subscription_service(authorized_payment: {
        "id" => "AUTHPAY-2",
        "preapproval_id" => "PRE-4",
        "payment" => {"id" => "MP-RECUR-2", "status" => "rejected"}
      }) do
        post webhooks_mercadopago_url,
          params: {type: "subscription_authorized_payment", data: {id: "AUTHPAY-2"}}
      end

      assert_response :ok
      listing.reload
      assert listing.pending_payment?
      assert_nil listing.payment_id
    end
  end
end
