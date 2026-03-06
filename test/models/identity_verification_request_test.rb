require "test_helper"

class IdentityVerificationRequestTest < ActiveSupport::TestCase
  # --- Associations ---

  test "belongs to user" do
    identity = identity_verification_requests(:karass_identity)
    assert_equal users(:karass), identity.user
  end

  test "belongs to onboarding_request" do
    identity = identity_verification_requests(:karass_identity)
    assert_equal onboarding_requests(:karass_pending), identity.onboarding_request
  end

  test "onboarding_request is optional" do
    identity = identity_verification_requests(:one)
    assert_nil identity.onboarding_request
    assert identity.valid?
  end

  test "has identity_documents attached" do
    identity = identity_verification_requests(:karass_identity)
    assert identity.identity_documents.attached?
    assert_equal 2, identity.identity_documents.count
  end

  # --- Status validation ---

  test "valid with each allowed status" do
    identity = identity_verification_requests(:karass_identity)
    %w[draft pending approved rejected].each do |s|
      identity.status = s
      assert identity.valid?, "expected status '#{s}' to be valid"
    end
  end

  test "invalid with unknown status" do
    identity = identity_verification_requests(:karass_identity)
    identity.status = "cancelled"
    assert_not identity.valid?
    assert identity.errors[:status].any?
  end

  # --- Presence validations (conditional on draft) ---

  test "draft does not require first_name, last_name, run, phone" do
    identity = identity_verification_requests(:one)
    identity.first_name = nil
    identity.last_name = nil
    identity.run = nil
    identity.phone = nil
    identity.status = "draft"
    assert identity.valid?
  end

  test "pending requires first_name" do
    identity = identity_verification_requests(:karass_identity)
    identity.first_name = nil
    assert_not identity.valid?
    assert identity.errors[:first_name].any?
  end

  test "pending requires last_name" do
    identity = identity_verification_requests(:karass_identity)
    identity.last_name = nil
    assert_not identity.valid?
    assert identity.errors[:last_name].any?
  end

  test "pending requires run" do
    identity = identity_verification_requests(:karass_identity)
    identity.run = nil
    assert_not identity.valid?
    assert identity.errors[:run].any?
  end

  test "pending requires phone" do
    identity = identity_verification_requests(:karass_identity)
    identity.phone = nil
    assert_not identity.valid?
    assert identity.errors[:phone].any?
  end

  # --- RUN validation ---

  test "rejects invalid run format" do
    identity = identity_verification_requests(:karass_identity)
    identity.run = "123"
    assert_not identity.valid?
    assert identity.errors[:run].any?
  end

  test "rejects run with wrong check digit" do
    identity = identity_verification_requests(:karass_identity)
    identity.run = "11111111-9"
    assert_not identity.valid?
    assert identity.errors[:run].any?
  end

  test "accepts valid run" do
    identity = identity_verification_requests(:karass_identity)
    identity.run = "22222222-2"
    assert identity.valid?
  end

  test "allows blank run in draft" do
    identity = identity_verification_requests(:one)
    identity.status = "draft"
    identity.run = ""
    assert identity.valid?
  end

  # --- RUN normalization ---

  test "normalizes run removing dots, dashes and spaces" do
    identity = identity_verification_requests(:karass_identity)
    identity.run = "22.222.222-2"
    identity.valid?
    assert_equal "22222222-2", identity.run
  end

  test "normalizes run uppercase and inserts dash" do
    identity = identity_verification_requests(:karass_identity)
    identity.run = "11111112k"
    identity.valid?
    assert_equal "11111112-K", identity.run
  end

  test "normalizes run removing spaces" do
    identity = identity_verification_requests(:karass_identity)
    identity.run = "22 222 222 2"
    identity.valid?
    assert_equal "22222222-2", identity.run
  end

  # --- Phone validation ---

  test "rejects invalid phone format" do
    identity = identity_verification_requests(:karass_identity)
    identity.phone = "12345"
    assert_not identity.valid?
    assert identity.errors[:phone].any?
  end

  test "accepts valid phone" do
    identity = identity_verification_requests(:karass_identity)
    identity.phone = "+56987654321"
    assert identity.valid?
  end

  test "allows blank phone in draft" do
    identity = identity_verification_requests(:one)
    identity.status = "draft"
    identity.phone = ""
    assert identity.valid?
  end

  # --- Phone normalization ---

  test "normalizes phone starting with 9 to +56 prefix" do
    identity = identity_verification_requests(:karass_identity)
    identity.phone = "987654321"
    identity.valid?
    assert_equal "+56987654321", identity.phone
  end

  test "normalizes phone starting with 569 adding plus" do
    identity = identity_verification_requests(:karass_identity)
    identity.phone = "56987654321"
    identity.valid?
    assert_equal "+56987654321", identity.phone
  end

  test "normalizes phone stripping non-numeric characters" do
    identity = identity_verification_requests(:karass_identity)
    identity.phone = "+56 9 8765 4321"
    identity.valid?
    assert_equal "+56987654321", identity.phone
  end

  test "leaves already normalized phone unchanged" do
    identity = identity_verification_requests(:karass_identity)
    identity.phone = "+56987654321"
    identity.valid?
    assert_equal "+56987654321", identity.phone
  end

  # --- Name normalization ---

  test "normalizes first_name capitalizing each word" do
    identity = identity_verification_requests(:karass_identity)
    identity.first_name = "JUAN CARLOS"
    identity.valid?
    assert_equal "Juan Carlos", identity.first_name
  end

  test "normalizes last_name capitalizing each word" do
    identity = identity_verification_requests(:karass_identity)
    identity.last_name = "de la FUENTE"
    identity.valid?
    assert_equal "De La Fuente", identity.last_name
  end

  test "strips extra whitespace from names" do
    identity = identity_verification_requests(:karass_identity)
    identity.first_name = "  juan   carlos  "
    identity.last_name = "  pérez  "
    identity.valid?
    assert_equal "Juan Carlos", identity.first_name
    assert_equal "Pérez", identity.last_name
  end

  # --- full_name ---

  test "full_name returns first and last name" do
    identity = identity_verification_requests(:karass_identity)
    assert_equal "Karass Templar", identity.full_name
  end

  # --- Status predicates ---

  test "draft? returns true for draft" do
    identity = identity_verification_requests(:one)
    assert identity.draft?
    assert_not identity.pending?
  end

  test "pending? returns true for pending" do
    identity = identity_verification_requests(:karass_identity)
    assert identity.pending?
    assert_not identity.draft?
  end

  test "approved? returns true for approved" do
    identity = identity_verification_requests(:karass_identity)
    identity.status = "approved"
    assert identity.approved?
  end

  test "rejected? returns true for rejected" do
    identity = identity_verification_requests(:karass_identity)
    identity.status = "rejected"
    assert identity.rejected?
  end

  # --- Scopes ---

  test "draft scope returns only draft records" do
    results = IdentityVerificationRequest.draft
    results.each { |r| assert_equal "draft", r.status }
    assert_includes results, identity_verification_requests(:one)
  end

  test "pending scope returns only pending records" do
    results = IdentityVerificationRequest.pending
    results.each { |r| assert_equal "pending", r.status }
    assert_includes results, identity_verification_requests(:karass_identity)
  end

  test "approved scope filters correctly" do
    identity = identity_verification_requests(:karass_identity)
    identity.update!(status: "approved")
    assert_includes IdentityVerificationRequest.approved, identity
  end

  test "rejected scope filters correctly" do
    identity = identity_verification_requests(:karass_identity)
    identity.update!(status: "rejected")
    assert_includes IdentityVerificationRequest.rejected, identity
  end
end
