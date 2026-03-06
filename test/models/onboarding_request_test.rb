require "test_helper"

class OnboardingRequestTest < ActiveSupport::TestCase
  # --- Associations ---

  test "belongs to user" do
    onboarding = onboarding_requests(:karass_pending)
    assert_equal users(:karass), onboarding.user
  end

  test "belongs to neighborhood_association" do
    onboarding = onboarding_requests(:karass_pending)
    assert_equal neighborhood_associations(:manios_de_buin), onboarding.neighborhood_association
  end

  test "belongs to region" do
    onboarding = onboarding_requests(:karass_pending)
    assert_equal regions(:region_0_0), onboarding.region
  end

  test "belongs to commune" do
    onboarding = onboarding_requests(:karass_pending)
    assert_equal communes(:commune_0_0_39), onboarding.commune
  end

  test "neighborhood_association is optional" do
    onboarding = onboarding_requests(:one)
    onboarding.neighborhood_association = nil
    onboarding.status = "draft"
    assert onboarding.valid?
  end

  test "region is optional" do
    onboarding = onboarding_requests(:one)
    assert_nil onboarding.region
    assert onboarding.valid?
  end

  test "commune is optional" do
    onboarding = onboarding_requests(:one)
    assert_nil onboarding.commune
    assert onboarding.valid?
  end

  test "has one identity_verification_request" do
    onboarding = onboarding_requests(:karass_pending)
    assert_equal identity_verification_requests(:karass_identity), onboarding.identity_verification_request
  end

  test "has one residence_verification_request" do
    onboarding = onboarding_requests(:karass_pending)
    assert_equal residence_verification_requests(:karass_residence), onboarding.residence_verification_request
  end

  test "destroys identity_verification_request on destroy" do
    onboarding = onboarding_requests(:karass_pending)
    identity_id = onboarding.identity_verification_request.id
    onboarding.destroy
    assert_nil IdentityVerificationRequest.find_by(id: identity_id)
  end

  test "destroys residence_verification_request on destroy" do
    onboarding = onboarding_requests(:karass_pending)
    residence_id = onboarding.residence_verification_request.id
    onboarding.destroy
    assert_nil ResidenceVerificationRequest.find_by(id: residence_id)
  end

  # --- Status validation ---

  test "valid with draft status" do
    onboarding = onboarding_requests(:one)
    assert_equal "draft", onboarding.status
    assert onboarding.valid?
  end

  test "valid with pending status" do
    onboarding = onboarding_requests(:karass_pending)
    assert_equal "pending", onboarding.status
    assert onboarding.valid?
  end

  test "valid with approved status" do
    onboarding = onboarding_requests(:karass_pending)
    onboarding.status = "approved"
    assert onboarding.valid?
  end

  test "valid with rejected status" do
    onboarding = onboarding_requests(:karass_pending)
    onboarding.status = "rejected"
    assert onboarding.valid?
  end

  test "invalid with unknown status" do
    onboarding = onboarding_requests(:karass_pending)
    onboarding.status = "unknown"
    assert_not onboarding.valid?
    assert onboarding.errors[:status].any?
  end

  # --- terms_accepted_at validation ---

  test "draft does not require terms_accepted_at" do
    onboarding = onboarding_requests(:one)
    onboarding.terms_accepted_at = nil
    assert onboarding.valid?
  end

  test "pending requires terms_accepted_at" do
    onboarding = onboarding_requests(:karass_pending)
    onboarding.terms_accepted_at = nil
    assert_not onboarding.valid?
    assert onboarding.errors[:terms_accepted_at].any?
  end

  test "approved requires terms_accepted_at" do
    onboarding = onboarding_requests(:karass_pending)
    onboarding.status = "approved"
    onboarding.terms_accepted_at = nil
    assert_not onboarding.valid?
    assert onboarding.errors[:terms_accepted_at].any?
  end

  test "rejected requires terms_accepted_at" do
    onboarding = onboarding_requests(:karass_pending)
    onboarding.status = "rejected"
    onboarding.terms_accepted_at = nil
    assert_not onboarding.valid?
    assert onboarding.errors[:terms_accepted_at].any?
  end

  # --- Status predicates ---

  test "draft? returns true for draft status" do
    onboarding = onboarding_requests(:one)
    assert onboarding.draft?
    assert_not onboarding.pending?
    assert_not onboarding.approved?
    assert_not onboarding.rejected?
  end

  test "pending? returns true for pending status" do
    onboarding = onboarding_requests(:karass_pending)
    assert onboarding.pending?
    assert_not onboarding.draft?
    assert_not onboarding.approved?
    assert_not onboarding.rejected?
  end

  test "approved? returns true for approved status" do
    onboarding = onboarding_requests(:karass_pending)
    onboarding.status = "approved"
    assert onboarding.approved?
    assert_not onboarding.draft?
  end

  test "rejected? returns true for rejected status" do
    onboarding = onboarding_requests(:karass_pending)
    onboarding.status = "rejected"
    assert onboarding.rejected?
    assert_not onboarding.draft?
  end

  # --- Scopes ---

  test "draft scope returns only draft records" do
    results = OnboardingRequest.draft
    results.each { |r| assert_equal "draft", r.status }
    assert_includes results, onboarding_requests(:one)
  end

  test "pending scope returns only pending records" do
    results = OnboardingRequest.pending
    results.each { |r| assert_equal "pending", r.status }
    assert_includes results, onboarding_requests(:karass_pending)
  end

  test "approved scope filters correctly" do
    onboarding = onboarding_requests(:karass_pending)
    onboarding.update!(status: "approved")
    results = OnboardingRequest.approved
    assert_includes results, onboarding
  end

  test "rejected scope filters correctly" do
    onboarding = onboarding_requests(:karass_pending)
    onboarding.update!(status: "rejected")
    results = OnboardingRequest.rejected
    assert_includes results, onboarding
  end
end
