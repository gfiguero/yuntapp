require "test_helper"

module Panel
  class ResidenceCertificatesControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @household_admin = users(:selendis)
      @non_admin = users(:karass)
      @member = members(:selendis_member)
      @residency = residencies(:selendis_residency)
      @association = neighborhood_associations(:manios_de_buin)
      @pricing = certificate_pricings(:manios_current_pricing)
    end

    # --- Authorization ---

    test "non household_admin is redirected" do
      sign_in @non_admin
      get panel_residence_certificates_url
      assert_redirected_to panel_root_url
    end

    test "unauthenticated is redirected" do
      get panel_residence_certificates_url
      assert_redirected_to new_user_session_url
    end

    test "household_admin can view index" do
      sign_in @household_admin
      get panel_residence_certificates_url
      assert_response :success
    end

    test "household_admin can view new with current pricing" do
      sign_in @household_admin
      get new_panel_residence_certificate_url
      assert_response :success
    end

    # --- Create ---

    test "create captures snapshot of current price as amount" do
      sign_in @household_admin

      assert_difference -> { ResidenceCertificate.count }, 1 do
        post panel_residence_certificates_url, params: {
          residence_certificate: {
            member_id: @residency.id,
            purpose: "trámite bancario"
          }
        }
      end

      cert = ResidenceCertificate.order(:created_at).last
      assert_equal @pricing.price, cert.amount
      assert_equal @pricing.price * 0.10, cert.platform_fee
      assert cert.pending_payment?
      assert_nil cert.payment_id
    end

    test "create snapshots the price at request time, even if price later changes" do
      sign_in @household_admin
      original_price = @pricing.price

      post panel_residence_certificates_url, params: {
        residence_certificate: {member_id: @residency.id, purpose: "test"}
      }
      cert = ResidenceCertificate.order(:created_at).last
      assert_equal original_price, cert.amount

      CertificatePricing.create!(
        neighborhood_association: @association,
        price: 5000,
        effective_from: Time.current,
        created_by: @household_admin
      )

      cert.reload
      assert_equal original_price, cert.amount, "amount snapshot must be immutable to pricing changes"
    end

    test "create fails when no current pricing defined" do
      sign_in @household_admin
      @pricing.destroy

      assert_no_difference -> { ResidenceCertificate.count } do
        post panel_residence_certificates_url, params: {
          residence_certificate: {member_id: @residency.id, purpose: "test"}
        }
      end

      assert_response :unprocessable_content
    end

    test "create ignores params attempts to set amount/payment_id/status" do
      sign_in @household_admin

      post panel_residence_certificates_url, params: {
        residence_certificate: {
          member_id: @residency.id,
          purpose: "test",
          amount: 99999,
          payment_id: "FAKE",
          status: "issued",
          platform_fee: 0
        }
      }

      cert = ResidenceCertificate.order(:created_at).last
      assert_equal @pricing.price, cert.amount
      assert_nil cert.payment_id
      assert cert.pending_payment?
    end

    # --- show with issued certificate ---

    test "show on issued cert displays download link and validation_code" do
      sign_in @household_admin

      cert = ResidenceCertificate.create!(
        member: @member,
        household_unit: household_units(:selendis_household),
        neighborhood_association: @association,
        purpose: "trámite bancario",
        status: "issued",
        folio: "CR-1-99",
        validation_token: "uuid-show-test",
        validation_code: "SHOWCODE",
        issue_date: Date.current,
        expiration_date: Date.current + 6.months,
        issued_at: Time.current
      )
      cert.pdf_document.attach(
        io: StringIO.new("%PDF-1.4 fake content"),
        filename: "test.pdf",
        content_type: "application/pdf"
      )

      get panel_residence_certificate_url(cert)
      assert_response :success
      assert_match I18n.t("panel.residence_certificates.show.download_pdf"), @response.body
      assert_match "SHOWCODE", @response.body
    end

    test "show on paid cert (awaiting issuance) shows processing message" do
      sign_in @household_admin

      cert = ResidenceCertificate.create!(
        member: @member,
        household_unit: household_units(:selendis_household),
        neighborhood_association: @association,
        purpose: "test",
        status: "paid",
        amount: 1500,
        payment_id: "MP-SHOW-PAID",
        paid_at: Time.current
      )

      get panel_residence_certificate_url(cert)
      assert_response :success
      assert_match I18n.t("panel.residence_certificates.show.processing"), @response.body
    end
  end
end
