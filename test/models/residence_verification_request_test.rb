require "test_helper"

class ResidenceVerificationRequestTest < ActiveSupport::TestCase
  # --- Associations ---

  test "belongs to user" do
    residence = residence_verification_requests(:karass_residence)
    assert_equal users(:karass), residence.user
  end

  test "belongs to neighborhood_association" do
    residence = residence_verification_requests(:karass_residence)
    assert_equal neighborhood_associations(:manios_de_buin), residence.neighborhood_association
  end

  test "belongs to commune" do
    residence = residence_verification_requests(:karass_residence)
    assert_equal communes(:commune_0_0_39), residence.commune
  end

  test "belongs to neighborhood_delegation" do
    residence = residence_verification_requests(:karass_residence)
    assert_equal neighborhood_delegations(:manios_delegation_1), residence.neighborhood_delegation
  end

  test "neighborhood_delegation is optional" do
    residence = residence_verification_requests(:one)
    residence.neighborhood_delegation = nil
    residence.street_name = "Calle Falsa 123"
    assert residence.valid?
  end

  test "belongs to onboarding_request" do
    residence = residence_verification_requests(:karass_residence)
    assert_equal onboarding_requests(:karass_pending), residence.onboarding_request
  end

  test "onboarding_request is optional" do
    residence = residence_verification_requests(:one)
    assert_nil residence.onboarding_request
    assert residence.valid?
  end

  test "has residence_documents attached" do
    residence = residence_verification_requests(:karass_residence)
    assert residence.residence_documents.attached?
    assert_equal 1, residence.residence_documents.count
  end

  # --- Status validation ---

  test "valid with each allowed status" do
    residence = residence_verification_requests(:karass_residence)
    %w[draft pending approved rejected].each do |s|
      residence.status = s
      assert residence.valid?, "expected status '#{s}' to be valid"
    end
  end

  test "invalid with unknown status" do
    residence = residence_verification_requests(:karass_residence)
    residence.status = "cancelled"
    assert_not residence.valid?
    assert residence.errors[:status].any?
  end

  # --- Conditional address validation ---

  test "valid with delegation and no street_name" do
    residence = residence_verification_requests(:karass_residence)
    residence.street_name = nil
    assert residence.valid?
  end

  test "valid with street_name and no delegation" do
    residence = residence_verification_requests(:one)
    residence.neighborhood_delegation = nil
    residence.street_name = "Calle Falsa 123"
    assert residence.valid?
  end

  test "valid with both delegation and street_name" do
    residence = residence_verification_requests(:karass_residence)
    residence.street_name = "Calle Extra"
    assert residence.valid?
  end

  test "valid with neither delegation nor street_name due to allow_blank" do
    residence = residence_verification_requests(:karass_residence)
    residence.neighborhood_delegation = nil
    residence.street_name = nil
    # allow_blank: true means blank values pass, even when presence is triggered
    assert residence.valid?
  end

  # --- Status predicates ---

  test "draft? returns true for draft" do
    residence = residence_verification_requests(:karass_residence)
    residence.status = "draft"
    assert residence.draft?
    assert_not residence.pending?
    assert_not residence.approved?
    assert_not residence.rejected?
  end

  test "pending? returns true for pending" do
    residence = residence_verification_requests(:karass_residence)
    assert residence.pending?
    assert_not residence.draft?
  end

  test "approved? returns true for approved" do
    residence = residence_verification_requests(:karass_residence)
    residence.status = "approved"
    assert residence.approved?
  end

  test "rejected? returns true for rejected" do
    residence = residence_verification_requests(:karass_residence)
    residence.status = "rejected"
    assert residence.rejected?
  end

  # --- Scopes ---

  test "draft scope returns only draft records" do
    residence = residence_verification_requests(:karass_residence)
    residence.update_column(:status, "draft")
    results = ResidenceVerificationRequest.draft
    assert_includes results, residence
    results.each { |r| assert_equal "draft", r.status }
  end

  test "pending scope returns only pending records" do
    results = ResidenceVerificationRequest.pending
    results.each { |r| assert_equal "pending", r.status }
    assert_includes results, residence_verification_requests(:karass_residence)
  end

  test "approved scope filters correctly" do
    residence = residence_verification_requests(:karass_residence)
    residence.update!(status: "approved")
    assert_includes ResidenceVerificationRequest.approved, residence
  end

  test "rejected scope filters correctly" do
    residence = residence_verification_requests(:karass_residence)
    residence.update!(status: "rejected")
    assert_includes ResidenceVerificationRequest.rejected, residence
  end
end
