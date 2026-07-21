require "test_helper"

class DemoJuntaSeederTest < ActiveSupport::TestCase
  def assoc
    NeighborhoodAssociation.find_by(name: DemoJuntaSeeder::ASSOCIATION_NAME)
  end

  test "builds a complete demo junta with members, pending onboardings and dependents" do
    DemoJuntaSeeder.call

    assert_not_nil assoc
    assert_equal 20, Member.where(neighborhood_association: assoc, status: "approved").count
    assert_equal 8, OnboardingRequest.where(neighborhood_association: assoc, status: "pending").count
    assert_equal 4, IdentityVerificationRequest.where(neighborhood_association: assoc, dependent: true, status: "pending").count
    assert_operator CertificatePricing.where(neighborhood_association: assoc).count, :>=, 1
  end

  test "generates RUNs that pass validation" do
    DemoJuntaSeeder.call

    identities = Member.where(neighborhood_association: assoc).map(&:verified_identity)
    assert identities.any?
    assert(identities.all?(&:valid?), "todos los RUN generados deben ser válidos")
  end

  test "creates a confirmed admin user for login" do
    DemoJuntaSeeder.call

    admin = User.find_by(email: "gfiguero+demo-admin@gmail.com")
    assert admin.admin?
    assert_not_nil admin.confirmed_at, "el admin debe estar confirmado para poder loguear"
    assert_equal assoc, admin.neighborhood_association
  end

  test "pending onboardings have identity and residence requests attached" do
    DemoJuntaSeeder.call

    onboarding = OnboardingRequest.where(neighborhood_association: assoc, status: "pending").first
    assert_equal "pending", onboarding.identity_verification_request.status
    assert onboarding.identity_verification_request.identity_documents.attached?
    assert_equal "pending", onboarding.residence_verification_request.status
  end

  test "is idempotent across runs" do
    DemoJuntaSeeder.call
    DemoJuntaSeeder.call

    assert_equal 1, NeighborhoodAssociation.where(name: DemoJuntaSeeder::ASSOCIATION_NAME).count
    assert_equal 20, Member.where(neighborhood_association: assoc, status: "approved").count
  end

  test "reset! removes all demo data cleanly" do
    DemoJuntaSeeder.call
    DemoJuntaSeeder.reset!

    assert_equal 0, NeighborhoodAssociation.where(name: DemoJuntaSeeder::ASSOCIATION_NAME).count
    assert_equal 0, User.where("email LIKE ?", DemoJuntaSeeder::EMAIL_LIKE).count
  end
end
