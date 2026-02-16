require "test_helper"

class VerifiedIdentityTest < ActiveSupport::TestCase
  # --- RUN normalization ---

  test "normalizes RUN removing dots, dashes and spaces" do
    persona = verified_identities(:karass_persona)
    persona.update!(run: "22.222.222-2")
    assert_equal "22222222-2", persona.run
  end

  test "normalizes RUN to uppercase and inserts dash" do
    persona = verified_identities(:karass_persona)
    persona.update!(run: "11111112k")
    assert_equal "11111112-K", persona.run
  end

  test "normalizes RUN removing spaces" do
    persona = verified_identities(:karass_persona)
    persona.update!(run: "22 222 222 2")
    assert_equal "22222222-2", persona.run
  end

  test "leaves already normalized RUN unchanged" do
    persona = verified_identities(:karass_persona)
    persona.update!(run: "22222222-2")
    assert_equal "22222222-2", persona.run
  end

  # --- RUN validation ---

  test "rejects RUN with invalid format" do
    persona = verified_identities(:karass_persona)
    persona.run = "123"
    assert_not persona.valid?
    assert persona.errors[:run].any?
  end

  test "rejects RUN with incorrect check digit" do
    persona = verified_identities(:karass_persona)
    persona.run = "11111111-9"
    assert_not persona.valid?
    assert persona.errors[:run].any?
  end

  test "accepts RUN with valid check digit" do
    persona = verified_identities(:karass_persona)
    persona.run = "12121212-9"
    assert persona.valid?
  end

  test "accepts RUN with K check digit" do
    persona = verified_identities(:karass_persona)
    persona.run = "11111112-K"
    assert persona.valid?
  end

  test "validates check digit for 7-digit body" do
    persona = verified_identities(:karass_persona)
    persona.run = "7654321-6"
    assert persona.valid?
  end

  test "rejects 7-digit body with wrong check digit" do
    persona = verified_identities(:karass_persona)
    persona.run = "7654321-0"
    assert_not persona.valid?
    assert persona.errors[:run].any?
  end

  # --- Uniqueness ---

  test "enforces uniqueness of RUN" do
    persona = VerifiedIdentity.new(
      first_name: "Duplicate",
      last_name: "Run",
      run: "11111111-1"
    )
    assert_not persona.valid?
    assert persona.errors[:run].any?
  end

  # --- Presence ---

  test "requires first_name, last_name, and run" do
    persona = VerifiedIdentity.new
    assert_not persona.valid?
    assert persona.errors[:first_name].any?
    assert persona.errors[:last_name].any?
    assert persona.errors[:run].any?
  end

  # --- Verification status ---

  test "verification_status defaults to pending" do
    persona = VerifiedIdentity.new(first_name: "Test", last_name: "User", run: "99999999-9")
    assert_equal "pending", persona.verification_status
  end

  test "verified? returns true when verification_status is verified" do
    persona = verified_identities(:selendis_persona)
    assert persona.verified?
  end

  test "pending_verification? returns true when verification_status is pending" do
    persona = verified_identities(:rohana_persona)
    assert persona.pending_verification?
  end

  test "rejected_verification? returns true when verification_status is rejected" do
    persona = verified_identities(:selendis_persona)
    persona.verification_status = "rejected"
    assert persona.rejected_verification?
  end

  test "rejects invalid verification_status" do
    persona = verified_identities(:selendis_persona)
    persona.verification_status = "invalid"
    assert_not persona.valid?
    assert persona.errors[:verification_status].any?
  end

  # --- Name ---

  test "name returns full name" do
    persona = verified_identities(:selendis_persona)
    assert_equal "Selendis Daelaam", persona.name
  end

  # --- Name normalization ---

  test "normalizes first_name to capitalize each word" do
    persona = verified_identities(:karass_persona)
    persona.update!(first_name: "JUAN CARLOS")
    assert_equal "Juan Carlos", persona.first_name
  end

  test "normalizes last_name to capitalize each word" do
    persona = verified_identities(:karass_persona)
    persona.update!(last_name: "de la FUENTE PÉREZ")
    assert_equal "De La Fuente Pérez", persona.last_name
  end

  test "normalizes all-lowercase names" do
    persona = verified_identities(:karass_persona)
    persona.update!(first_name: "maría", last_name: "gonzález")
    assert_equal "María", persona.first_name
    assert_equal "González", persona.last_name
  end

  test "strips extra whitespace from names" do
    persona = verified_identities(:karass_persona)
    persona.update!(first_name: "  juan   carlos  ", last_name: "  pérez  ")
    assert_equal "Juan Carlos", persona.first_name
    assert_equal "Pérez", persona.last_name
  end

  # --- Scopes ---

  test "verified scope returns only verified personas" do
    verified = VerifiedIdentity.verified
    assert verified.all?(&:verified?)
  end

  test "pending scope returns only pending personas" do
    pending_personas = VerifiedIdentity.pending
    assert pending_personas.all?(&:pending_verification?)
  end
end
