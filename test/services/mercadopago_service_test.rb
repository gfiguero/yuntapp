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
          pending_url: "https://x.test/p")
      end
    end
  end

  # --- Payload enrichment: create_preference (#126, #128, #129, #130, #132, #133) ---

  test "create_preference payload includes statement_descriptor, expires, installments, category_id, description, payer and idempotency key" do
    cert = ResidenceCertificate.new(id: 42, amount: 1500, purpose: "trámite bancario")

    captured = {}
    fake_pref = build_fake_preference_resource(captured)
    fake_sdk = build_fake_sdk(preference: fake_pref)

    @service.instance_variable_set(:@sdk, fake_sdk)
    @service.create_preference(
      cert,
      payer: {email: "pagador@x.cl"},
      success_url: "https://x.test/s",
      failure_url: "https://x.test/f",
      pending_url: "https://x.test/p"
    )

    payload = captured[:payload]
    assert_equal "YUNTAPP", payload[:statement_descriptor]
    assert payload[:expires]
    assert payload[:expiration_date_to].present?
    assert_equal 1, payload[:payment_methods][:installments]
    assert_equal({email: "pagador@x.cl"}, payload[:payer])
    assert_equal "services", payload[:items][0][:category_id]
    assert_equal "trámite bancario", payload[:items][0][:description]
    assert_equal "pref-cert-42", captured[:opts].custom_headers["x-idempotency-key"]
  end

  test "create_preference omits payer key when payer is nil" do
    cert = ResidenceCertificate.new(id: 7, amount: 1500, purpose: "otro")

    captured = {}
    fake_pref = build_fake_preference_resource(captured)
    fake_sdk = build_fake_sdk(preference: fake_pref)

    @service.instance_variable_set(:@sdk, fake_sdk)
    @service.create_preference(
      cert,
      success_url: "https://x.test/s",
      failure_url: "https://x.test/f",
      pending_url: "https://x.test/p"
    )

    assert_not captured[:payload].key?(:payer)
  end

  # --- Payload enrichment: create_listing_preference (#126, #128, #129, #130, #132, #133) ---

  test "create_listing_preference payload includes statement_descriptor, category_id, description, installments, payer and idempotency key" do
    listing = build_fake_listing(id: 99, name: "Mesa de jardín", amount: 2000)

    captured = {}
    fake_pref = build_fake_preference_resource(captured)
    fake_sdk = build_fake_sdk(preference: fake_pref)

    @service.instance_variable_set(:@sdk, fake_sdk)
    @service.create_listing_preference(
      listing,
      payer: {email: "comprador@x.cl"},
      success_url: "https://x.test/s",
      failure_url: "https://x.test/f",
      pending_url: "https://x.test/p"
    )

    payload = captured[:payload]
    assert_equal "YUNTAPP", payload[:statement_descriptor]
    assert payload[:expires]
    assert payload[:expiration_date_to].present?
    assert_equal 1, payload[:payment_methods][:installments]
    assert_equal({email: "comprador@x.cl"}, payload[:payer])
    assert_equal "services", payload[:items][0][:category_id]
    assert_equal "Mesa de jardín", payload[:items][0][:description]
    assert_equal "pref-listing-99", captured[:opts].custom_headers["x-idempotency-key"]
  end

  # --- Idempotency key: create_listing_subscription (#126) ---

  test "create_listing_subscription passes stable idempotency key" do
    listing = build_fake_listing(id: 55, name: "Aviso mensual", amount: 1200)

    captured = {}
    fake_preapproval = build_fake_preapproval_resource(captured)
    fake_sdk = build_fake_sdk(preapproval: fake_preapproval)

    @service.instance_variable_set(:@sdk, fake_sdk)
    @service.create_listing_subscription(listing, payer_email: "x@x.cl", back_url: "https://x.test/back")

    assert_equal "preapproval-listing-55", captured[:opts].custom_headers["x-idempotency-key"]
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

  # Fake SDK resource que captura payload y request_options para preferences.
  def build_fake_preference_resource(captured)
    fake = Object.new
    fake.define_singleton_method(:create) do |payload, request_options:|
      captured[:payload] = payload
      captured[:opts] = request_options
      {response: {"init_point" => "https://mp.test/checkout/fake"}}
    end
    fake
  end

  # Fake SDK resource que captura payload y request_options para preapprovals.
  def build_fake_preapproval_resource(captured)
    fake = Object.new
    fake.define_singleton_method(:create) do |payload, request_options:|
      captured[:payload] = payload
      captured[:opts] = request_options
      {response: {"id" => "PREAPPROVAL-FAKE", "init_point" => "https://mp.test/sub/fake"}}
    end
    fake
  end

  # Fake SDK que expone preference y/o preapproval.
  def build_fake_sdk(preference: nil, preapproval: nil)
    fake = Object.new
    fake.define_singleton_method(:preference) { preference } if preference
    fake.define_singleton_method(:preapproval) { preapproval } if preapproval
    fake
  end

  # Stub ligero de Listing con los campos mínimos para el service.
  def build_fake_listing(id:, name:, amount:)
    listing = Object.new
    listing.define_singleton_method(:id) { id }
    listing.define_singleton_method(:name) { name }
    listing.define_singleton_method(:amount) { amount }
    listing
  end
end
