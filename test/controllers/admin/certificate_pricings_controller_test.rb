require "test_helper"

module Admin
  class CertificatePricingsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @admin = users(:selendis)
      @non_admin = users(:karass)
      @association = neighborhood_associations(:manios_de_buin)
      @other_association = neighborhood_associations(:association_1)
      @pricing = certificate_pricings(:manios_current_pricing)
    end

    # --- Authorization ---

    test "non-admin is redirected" do
      sign_in @non_admin
      get admin_certificate_pricings_url
      assert_redirected_to root_url
    end

    test "unauthenticated is redirected" do
      get admin_certificate_pricings_url
      assert_redirected_to new_user_session_url
    end

    test "admin can view index" do
      sign_in @admin
      get admin_certificate_pricings_url
      assert_response :success
    end

    test "admin can view new form" do
      sign_in @admin
      get new_admin_certificate_pricing_url
      assert_response :success
    end

    # --- Index multi-tenant ---

    test "admin sees only pricings of own neighborhood_association" do
      sign_in @admin
      CertificatePricing.create!(
        neighborhood_association: @other_association,
        price: 99999,
        effective_from: Time.current,
        created_by: @admin
      )

      get admin_certificate_pricings_url
      assert_response :success
      assert_match ActiveSupport::NumberHelper.number_to_delimited(@pricing.price), @response.body
      assert_no_match(/99,999/, @response.body)
    end

    # --- Create ---

    test "admin can create a pricing for own association" do
      sign_in @admin

      assert_difference -> { CertificatePricing.count }, 1 do
        post admin_certificate_pricings_url, params: {
          certificate_pricing: {price: 2500}
        }
      end

      new_pricing = CertificatePricing.order(:created_at).last
      assert_equal 2500, new_pricing.price
      assert_equal @association, new_pricing.neighborhood_association
      assert_equal @admin, new_pricing.created_by
      assert_nil new_pricing.effective_to

      @pricing.reload
      assert_not_nil @pricing.effective_to, "previous pricing should be closed (BR-070)"

      assert_redirected_to admin_certificate_pricings_url
    end

    test "create rejects price below BR-005 minimum" do
      sign_in @admin

      assert_no_difference -> { CertificatePricing.count } do
        post admin_certificate_pricings_url, params: {
          certificate_pricing: {price: 999}
        }
      end

      assert_response :unprocessable_content
    end

    test "create ignores params attempts to set neighborhood_association_id" do
      sign_in @admin

      post admin_certificate_pricings_url, params: {
        certificate_pricing: {
          price: 2500,
          neighborhood_association_id: @other_association.id,
          created_by_id: users(:karass).id,
          effective_to: 1.day.ago
        }
      }

      new_pricing = CertificatePricing.order(:created_at).last
      assert_equal @association, new_pricing.neighborhood_association
      assert_equal @admin, new_pricing.created_by
      assert_nil new_pricing.effective_to
    end
  end
end
