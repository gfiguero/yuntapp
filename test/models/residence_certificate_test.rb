require "test_helper"

class ResidenceCertificateTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def setup
    @member = members(:selendis_member)
    @household_unit = household_units(:selendis_household)
    @association = neighborhood_associations(:manios_de_buin)
  end

  test "valid statuses are pending_payment, paid, issued" do
    %w[pending_payment paid issued].each do |status|
      cert = ResidenceCertificate.new(
        member: @member,
        household_unit: @household_unit,
        neighborhood_association: @association,
        purpose: "trámite bancario",
        status: status
      )
      assert cert.valid?, "#{status} debería ser válido pero falló: #{cert.errors.full_messages}"
    end
  end

  test "approved and rejected are not valid statuses" do
    %w[approved rejected pending].each do |status|
      cert = ResidenceCertificate.new(
        member: @member,
        household_unit: @household_unit,
        neighborhood_association: @association,
        purpose: "trámite bancario",
        status: status
      )
      assert_not cert.valid?, "#{status} no debería ser un estado válido"
    end
  end

  test "pending_payment? returns true when status is pending_payment" do
    cert = ResidenceCertificate.new(status: "pending_payment")
    assert cert.pending_payment?
    assert_not cert.paid?
    assert_not cert.issued?
  end

  test "paid? returns true when status is paid" do
    cert = ResidenceCertificate.new(status: "paid")
    assert cert.paid?
    assert_not cert.pending_payment?
    assert_not cert.issued?
  end

  test "issued? returns true when status is issued" do
    cert = ResidenceCertificate.new(status: "issued")
    assert cert.issued?
    assert_not cert.pending_payment?
    assert_not cert.paid?
  end

  test "new certificate defaults to pending_payment status" do
    cert = ResidenceCertificate.new(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario"
    )
    assert_equal "pending_payment", cert.status
  end

  test "issue! genera el folio con el formato CR-anio-junta-correlativo (BR-006)" do
    cert = ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit,
      neighborhood_association: @association, purpose: "trámite bancario", status: "paid"
    )
    cert.issue!

    assert_match(/\ACR-\d{4}-\d+-\d{5}\z/, cert.folio)
    assert_equal Date.current.year, cert.folio_year
    assert_equal format("CR-%04d-%04d-%05d", cert.folio_year, @association.id, cert.folio_sequence), cert.folio
  end

  test "el correlativo del folio es por junta y por anio" do
    first = ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit,
      neighborhood_association: @association, purpose: "uno", status: "paid"
    ).tap(&:issue!)

    second = ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit,
      neighborhood_association: @association, purpose: "dos", status: "paid"
    ).tap(&:issue!)

    assert_equal first.folio_sequence + 1, second.folio_sequence
    assert_equal first.folio_year, second.folio_year
  end

  test "el correlativo reinicia al cambiar de anio" do
    cert = ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit,
      neighborhood_association: @association, purpose: "del futuro", status: "paid"
    )
    # Un año sin certificados previos arranca en 1, sin importar el correlativo
    # que lleve el año en curso.
    cert.issue!(issue_date: Date.new(Date.current.year + 1, 1, 5))

    assert_equal 1, cert.folio_sequence
    assert_equal Date.current.year + 1, cert.folio_year
    assert_equal format("CR-%04d-%04d-00001", Date.current.year + 1, @association.id), cert.folio
  end

  test "una junta con folios del formato viejo continua el correlativo, sin reescribirlos" do
    viejo = ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit,
      neighborhood_association: @association, purpose: "formato viejo", status: "issued",
      folio: "CR-#{@association.id}-14", folio_year: Date.current.year, folio_sequence: 14,
      issue_date: Date.current, expiration_date: 30.days.from_now.to_date
    )

    nuevo = ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit,
      neighborhood_association: @association, purpose: "formato nuevo", status: "paid"
    )
    nuevo.issue!

    assert_equal 15, nuevo.folio_sequence, "el correlativo debe continuar desde el folio viejo"
    assert_equal format("CR-%04d-%04d-00015", Date.current.year, @association.id), nuevo.folio
    assert_equal "CR-#{@association.id}-14", viejo.reload.folio, "BR-008: el folio viejo no se reescribe"
  end

  test "filter_by_folio encuentra ambos formatos" do
    ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit,
      neighborhood_association: @association, purpose: "viejo", status: "issued",
      folio: "CR-#{@association.id}-14", folio_year: Date.current.year, folio_sequence: 14,
      issue_date: Date.current, expiration_date: 30.days.from_now.to_date
    )
    ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit,
      neighborhood_association: @association, purpose: "nuevo", status: "issued",
      folio: format("CR-%04d-%04d-00015", Date.current.year, @association.id),
      folio_year: Date.current.year, folio_sequence: 15,
      issue_date: Date.current, expiration_date: 30.days.from_now.to_date
    )

    assert_equal 1, ResidenceCertificate.filter_by_folio("14").count
    assert_equal 1, ResidenceCertificate.filter_by_folio("15").count
  end

  test "issue! recovers from a folio collision by retrying with the next number (#98)" do
    # Simula una emisión concurrente: otro certificado de la misma junta toma
    # el folio que este iba a usar, justo entre el cálculo y el save.
    taken = ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit,
      neighborhood_association: @association, purpose: "tomado", status: "issued",
      folio: "CR-#{Date.current.year}-#{format("%04d", @association.id)}-00001",
      folio_year: Date.current.year, folio_sequence: 1,
      issue_date: Date.current, expiration_date: 30.days.from_now.to_date
    )

    cert = ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit,
      neighborhood_association: @association, purpose: "nuevo", status: "paid"
    )

    # El primer cálculo devuelve el folio ya tomado (como si otro proceso lo
    # hubiera computado a la vez); el retry debe recalcular al siguiente libre
    # en vez de atascarse. Mismo patrón que el test de agotamiento de reintentos.
    taken_sequence = taken.folio_sequence
    calls = 0
    cert.define_singleton_method(:next_folio_sequence) do |year|
      calls += 1
      (calls == 1) ? taken_sequence : super(year)
    end

    assert_nothing_raised { cert.issue! }
    assert cert.issued?
    assert_not_equal taken.folio, cert.folio
    assert_match(/\ACR-\d{4}-\d+-\d{5}\z/, cert.folio)
  end

  test "issue! preserves a preexisting folio when only its folio_sequence collides (#98)" do
    # Este escenario no es alcanzable desde la aplicación (ningún flujo
    # persiste un folio en un certificado sin emitir); se construye a mano,
    # igual que los demás tests de colisión de este archivo.
    taken = ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit,
      neighborhood_association: @association, purpose: "tomado", status: "issued",
      folio: "CR-#{Date.current.year}-#{format("%04d", @association.id)}-00001",
      folio_year: Date.current.year, folio_sequence: 1,
      issue_date: Date.current, expiration_date: 30.days.from_now.to_date
    )

    cert = ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit,
      neighborhood_association: @association, purpose: "nuevo", status: "paid",
      folio: "CR-MANUAL-PREEXISTING"
    )

    # El folio_sequence calculado en el primer intento choca con el de
    # `taken` (índice association+folio_year+folio_sequence), aunque el
    # string del folio preexistente es único. El retry debe recalcular el
    # correlativo sin descartar el folio preexistente.
    taken_sequence = taken.folio_sequence
    calls = 0
    cert.define_singleton_method(:next_folio_sequence) do |year|
      calls += 1
      (calls == 1) ? taken_sequence : super(year)
    end

    assert_nothing_raised { cert.issue! }
    assert cert.issued?
    assert_equal "CR-MANUAL-PREEXISTING", cert.folio, "el folio preexistente debe sobrevivir al retry"
    assert_not_equal taken.folio_sequence, cert.folio_sequence
  end

  test "issue! gives up after max attempts and leaves cert in paid for the job to retry (#98)" do
    ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit,
      neighborhood_association: @association, purpose: "tomado", status: "issued",
      folio: "CR-#{Date.current.year}-#{format("%04d", @association.id)}-00001",
      folio_year: Date.current.year, folio_sequence: 1,
      issue_date: Date.current, expiration_date: 30.days.from_now.to_date
    )

    cert = ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit,
      neighborhood_association: @association, purpose: "nuevo", status: "paid"
    )

    # next_folio_sequence siempre devuelve el mismo correlativo tomado → la
    # colisión nunca se resuelve. Tras FOLIO_MAX_ATTEMPTS, issue! propaga el
    # error y el certificado queda en paid (BR-076: IssueCertificateJob
    # reintentará / revisión manual).
    cert.define_singleton_method(:next_folio_sequence) { |_year| 1 }

    assert_raises(ActiveRecord::RecordInvalid) { cert.issue! }
    assert cert.reload.paid?, "el certificado debe quedar en paid, no atascado a medias"
  end

  # BR-062/BR-064/BR-077: la emisión es automática; no existe aprobación de
  # admin. `approved_by_id` era un residuo del flujo anterior que nunca se
  # asignaba y que la vista admin mostraba siempre como "—".
  test "el certificado no tiene aprobador: la emisión es automática (BR-077)" do
    assert_not ResidenceCertificate.column_names.include?("approved_by_id")
    assert_not ResidenceCertificate.new.respond_to?(:approved_by)
  end

  # BR-141: las transiciones de estado deciden sobre el estado vigente en BD, no
  # sobre la lectura que el proceso tenía en memoria. Antes, un job que había
  # cargado el certificado como `paid` seguía emitiéndolo aunque un webhook de
  # contracargo ya lo hubiera devuelto a `pending_payment`.
  test "issue! aborta si el pago fue revertido concurrentemente (BR-141)" do
    cert = ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit,
      neighborhood_association: @association, purpose: "trámite", status: "paid",
      payment_id: "MP-RACE", paid_at: Time.current
    )

    # Otro proceso (webhook de refund) revierte el certificado en la BD mientras
    # este todavía lo tiene cargado como `paid`.
    ResidenceCertificate.where(id: cert.id)
      .update_all(status: "pending_payment", payment_status: "refunded")
    assert cert.paid?, "en memoria sigue viéndose como paid"

    assert_raises(RuntimeError) { cert.issue! }
    assert_not cert.reload.issued?, "no debe emitirse un certificado revertido"
  end

  # BR-004: a diferencia de `Listing` (cuyo `amount` se re-captura con el precio
  # vigente), el monto del certificado se fija al crearlo y ninguna ruta lo
  # reescribe. Por eso la comisión sigue siendo el 10% exacto tras un ciclo
  # reversión → re-pago, sin necesidad de recalcularla.
  test "la comisión sigue alineada con el monto tras revertir el pago (BR-004/BR-141)" do
    cert = ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit,
      neighborhood_association: @association, purpose: "trámite",
      amount: 2000, status: "paid", payment_id: "MP-REV", paid_at: Time.current
    )
    assert_equal 200, cert.platform_fee

    cert.apply_mp_payment_status!("refunded")
    cert.reload
    assert cert.pending_payment?

    cert.mark_as_paid!(payment_id: "MP-REV-2")

    cert.reload
    assert_equal 2000, cert.amount
    assert_equal 200, cert.platform_fee, "el 10% exacto del monto realmente cobrado"
  end

  # BR-008: issued certificates are immutable
  test "issued certificate cannot be modified" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      status: "issued"
    )
    assert_not cert.update(purpose: "otro propósito")
    assert cert.errors[:base].any?
    cert.reload
    assert_equal "trámite bancario", cert.purpose
  end

  test "issued certificate raises on update!" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      status: "issued"
    )
    assert_raises(ActiveRecord::RecordInvalid) do
      cert.update!(purpose: "otro propósito")
    end
  end

  test "paid certificate can be transitioned to issued" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      status: "paid"
    )
    assert cert.update(status: "issued", issue_date: Date.current, expiration_date: 30.days.from_now.to_date)
  end

  test "pending_payment certificate can be modified" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      status: "pending_payment"
    )
    assert cert.update(purpose: "arriendo")
  end

  # --- BR-005 minimum amount + BR-004 platform fee ---

  test "rejects amount below 1000 (BR-005)" do
    cert = ResidenceCertificate.new(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      amount: 999
    )
    assert_not cert.valid?
    assert cert.errors[:amount].any?
  end

  test "accepts amount at 1000" do
    cert = ResidenceCertificate.new(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      amount: 1000
    )
    assert cert.valid?
  end

  test "amount is optional (legacy records may not have it)" do
    cert = ResidenceCertificate.new(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario"
    )
    assert cert.valid?
  end

  test "platform_fee is computed as 10 percent of amount (BR-004)" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      amount: 1500
    )
    assert_equal 150, cert.platform_fee
  end

  test "platform_fee not overwritten if already set" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      amount: 1500,
      platform_fee: 500
    )
    assert_equal 500, cert.platform_fee
  end

  test "platform_fee rounds to the nearest peso, not truncating (BR-004, #99)" do
    # 1099 * 10% = 109.9 → 110 (antes truncaba a 109, sub-cobrando)
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      amount: 1099
    )
    assert_equal 110, cert.platform_fee
  end

  test "platform_fee rounds down when the fraction is below half (#99)" do
    # 1234 * 10% = 123.4 → 123
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      amount: 1234
    )
    assert_equal 123, cert.platform_fee
  end

  # --- payment_id uniqueness (BR-071) ---

  test "payment_id must be unique" do
    ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      amount: 1500,
      payment_id: "MP-12345"
    )

    duplicate = ResidenceCertificate.new(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "otro",
      amount: 1500,
      payment_id: "MP-12345"
    )
    assert_not duplicate.valid?
    assert duplicate.errors[:payment_id].any?
  end

  test "payment_id allows nil for multiple certificates" do
    ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      amount: 1500
    )

    another = ResidenceCertificate.new(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "arriendo",
      amount: 1500
    )
    assert another.valid?
  end

  # --- mark_as_paid! ---

  test "mark_as_paid! transitions pending_payment to paid" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      amount: 1500
    )

    cert.mark_as_paid!(payment_id: "MP-XYZ")

    assert cert.paid?
    assert_equal "MP-XYZ", cert.payment_id
    assert_not_nil cert.paid_at
  end

  test "mark_as_paid! is idempotent on already-paid certificate with same payment_id (BR-071)" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      amount: 1500,
      status: "paid",
      payment_id: "MP-XYZ",
      paid_at: 1.hour.ago
    )
    original_paid_at = cert.paid_at

    cert.mark_as_paid!(payment_id: "MP-XYZ")

    assert cert.paid?
    assert_equal "MP-XYZ", cert.payment_id
    assert_equal original_paid_at.to_i, cert.paid_at.to_i
  end

  test "mark_as_paid! raises when already paid with different payment_id" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      amount: 1500,
      status: "paid",
      payment_id: "MP-XYZ",
      paid_at: 1.hour.ago
    )

    assert_raises(ResidenceCertificate::AlreadyPaidError) do
      cert.mark_as_paid!(payment_id: "MP-DIFFERENT")
    end
  end

  test "mark_as_paid! refuses to downgrade from issued with a different payment_id (BR-008)" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      status: "issued",
      payment_id: "MP-ORIG"
    )

    assert_raises(ResidenceCertificate::AlreadyPaidError) do
      cert.mark_as_paid!(payment_id: "MP-OTHER")
    end
    assert cert.reload.issued?, "no debe degradarse de issued"
  end

  test "mark_as_paid! is a clean no-op on an issued cert with the same payment_id (merchant_order closed)" do
    # MP reenvía el pago (merchant_order opened→closed) tras la emisión; debe ser
    # un no-op limpio, sin RecordInvalid por inmutabilidad ni tocar la BD.
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      status: "issued",
      payment_id: "MP-SAME",
      folio: "CR-#{@association.id}-8200",
      issue_date: Date.current, expiration_date: 30.days.from_now.to_date, issued_at: Time.current
    )

    assert_nothing_raised do
      assert_no_changes -> { cert.reload.updated_at } do
        cert.mark_as_paid!(payment_id: "MP-SAME")
      end
    end
    assert cert.reload.issued?
  end

  # --- After-commit job enqueue (BR-076) ---

  test "mark_as_paid! enqueues IssueCertificateJob after commit" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      amount: 1500
    )

    assert_enqueued_with(job: IssueCertificateJob, args: [cert.id]) do
      cert.mark_as_paid!(payment_id: "MP-NEW")
    end
  end

  test "does not enqueue job on subsequent saves once already paid" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      amount: 1500,
      status: "paid",
      payment_id: "MP-PRE",
      paid_at: 1.hour.ago
    )

    assert_no_enqueued_jobs only: IssueCertificateJob do
      cert.mark_as_paid!(payment_id: "MP-PRE") # idempotent — no status change
    end
  end

  # --- issue! transition (BR-062, BR-074) ---

  test "issue! transitions paid to issued with folio, tokens and dates" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      amount: 1500,
      status: "paid",
      payment_id: "MP-PAY",
      paid_at: Time.current
    )

    cert.issue!

    assert cert.issued?
    assert_match(/\ACR-\d{4}-\d+-\d{5}\z/, cert.folio)
    assert cert.validation_token.present?
    assert_match(/\A[\h-]+\z/, cert.validation_token) # uuid-ish
    assert cert.validation_code.present?
    assert_equal ResidenceCertificate::VALIDATION_CODE_LENGTH, cert.validation_code.length
    assert_no_match(/[OI01]/, cert.validation_code, "el código no debe contener 0/O/1/I (BR-074)")
    assert_not_nil cert.issued_at
    assert_equal Date.current, cert.issue_date
    assert_equal Date.current + 30.days, cert.expiration_date
  end

  test "issue! is idempotent when already issued (BR-076)" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      status: "issued",
      validation_token: "uuid-preset",
      validation_code: "PRESET12"
    )

    cert.issue!
    assert cert.issued?
    assert_equal "uuid-preset", cert.validation_token
    assert_equal "PRESET12", cert.validation_code
  end

  test "issue! raises when status is not paid" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      status: "pending_payment"
    )

    assert_raises(RuntimeError) do
      cert.issue!
    end
  end

  test "issue! falla si la junta no tiene rut (BR-120)" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      amount: 1500,
      status: "paid",
      payment_id: "MP-NO-RUT",
      paid_at: Time.current
    )
    assert cert.paid?
    assert_not cert.issued?

    # rut is NOT NULL at the DB level (Task 1); use blank string to simulate a junta
    # sin RUT, bypassing model validation but respecting the DB constraint.
    cert.neighborhood_association.update_column(:rut, "") # bypass validation on purpose
    assert_raises(RuntimeError) { cert.issue! }
    assert_not cert.reload.issued?
  end

  test "issue! preserves existing folio/tokens if already set (defense against double issuance)" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      status: "paid",
      payment_id: "MP-FOO",
      paid_at: Time.current,
      folio: "CR-MANUAL-999",
      validation_token: "abc-existing",
      validation_code: "EXIST123"
    )

    cert.issue!

    assert cert.issued?
    assert_equal "CR-MANUAL-999", cert.folio
    assert_equal "abc-existing", cert.validation_token
    assert_equal "EXIST123", cert.validation_code
  end

  # --- Uniqueness validations (BR-074) ---

  test "validation_token must be unique" do
    ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      validation_token: "uuid-shared-token"
    )

    duplicate = ResidenceCertificate.new(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "otro",
      validation_token: "uuid-shared-token"
    )
    assert_not duplicate.valid?
    assert duplicate.errors[:validation_token].any?
  end

  test "validation_code must be unique" do
    ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      validation_code: "ABCD1234"
    )

    duplicate = ResidenceCertificate.new(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "otro",
      validation_code: "ABCD1234"
    )
    assert_not duplicate.valid?
    assert duplicate.errors[:validation_code].any?
  end

  # --- Public verification (BR-009, BR-078, BR-079, BR-080, BR-081) ---

  def issued_certificate(token: SecureRandom.uuid, code: SecureRandom.alphanumeric(8).upcase, expiration: Date.current + 30.days)
    ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "trámite bancario",
      status: "issued",
      folio: "CR-1-#{rand(1_000_000)}",
      validation_token: token,
      validation_code: code,
      issue_date: Date.current,
      expiration_date: expiration,
      issued_at: Time.current
    )
  end

  test "expired? is false for cert with future expiration" do
    cert = issued_certificate(expiration: Date.current + 1.day)
    assert_not cert.expired?
  end

  test "expired? is true for cert with past expiration" do
    cert = issued_certificate(expiration: Date.current - 1.day)
    assert cert.expired?
  end

  test "expired? is false when expiration_date is nil" do
    cert = issued_certificate
    cert.update_columns(expiration_date: nil)
    assert_not cert.expired?
  end

  test "masked_run hides middle digits keeping format" do
    cert = issued_certificate
    cert.member.verified_identity.update_columns(run: "12345678-K")
    assert_equal "1.XXX.XXX-K", cert.member.reload.run && cert.masked_run
  end

  test "masked_run preserves dv for known RUN format" do
    cert = issued_certificate
    cert.member.verified_identity.update_columns(run: "9876543-2")
    assert_equal "9.XXX.XXX-2", cert.masked_run
  end

  # BR-078: ante un RUN que no se puede separar en cuerpo y dígito verificador,
  # masked_run falla CERRADO. Antes hacía `return raw`, devolviendo el RUN
  # completo sin enmascarar a la página pública de verificación.
  test "masked_run does not leak a RUN without a dash" do
    cert = issued_certificate
    cert.member.verified_identity.update_columns(run: "12345678K")
    masked = cert.masked_run
    assert_not_includes masked.to_s, "12345678"
    assert_equal "X.XXX.XXX-X", masked
  end

  test "masked_run does not leak a malformed RUN" do
    cert = issued_certificate
    cert.member.verified_identity.update_columns(run: "malformed-no-dash-pattern")
    masked = cert.masked_run
    assert_not_includes masked.to_s, "malformed"
    assert_equal "X.XXX.XXX-X", masked
  end

  test "masked_run returns nil when run is blank" do
    cert = issued_certificate
    cert.member.verified_identity.update_columns(run: "")
    assert_nil cert.masked_run
  end

  test "findable_publicly scope returns only issued certs" do
    issued = issued_certificate
    ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "test",
      status: "pending_payment",
      validation_token: "uuid-pending",
      validation_code: "PENDING1"
    )

    results = ResidenceCertificate.findable_publicly
    assert_includes results, issued
    assert results.all?(&:issued?)
  end

  test "find_for_public_verification finds by validation_token" do
    cert = issued_certificate(token: SecureRandom.uuid)
    found = ResidenceCertificate.find_for_public_verification(cert.validation_token)
    assert_equal cert, found
  end

  test "find_for_public_verification finds by validation_code" do
    cert = issued_certificate(code: "LOOKUP12")
    found = ResidenceCertificate.find_for_public_verification("LOOKUP12")
    assert_equal cert, found
  end

  test "find_for_public_verification is case-insensitive for validation_code" do
    cert = issued_certificate(code: "LOOKUP34")
    found = ResidenceCertificate.find_for_public_verification("lookup34")
    assert_equal cert, found
  end

  test "find_for_public_verification returns nil for non-issued cert (BR-081)" do
    pending = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "test",
      status: "pending_payment",
      validation_token: "uuid-only-pending",
      validation_code: "PEND1234"
    )

    assert_nil ResidenceCertificate.find_for_public_verification(pending.validation_token)
    assert_nil ResidenceCertificate.find_for_public_verification(pending.validation_code)
  end

  test "find_for_public_verification returns nil for unknown identifier" do
    assert_nil ResidenceCertificate.find_for_public_verification("not-a-real-uuid")
    assert_nil ResidenceCertificate.find_for_public_verification("ABCD5678")
  end

  test "find_for_public_verification returns nil for blank identifier" do
    assert_nil ResidenceCertificate.find_for_public_verification(nil)
    assert_nil ResidenceCertificate.find_for_public_verification("")
    assert_nil ResidenceCertificate.find_for_public_verification("   ")
  end

  test "find_for_public_verification works for expired certs (BR-009, BR-080)" do
    cert = issued_certificate(expiration: 1.month.ago)
    found = ResidenceCertificate.find_for_public_verification(cert.validation_token)
    assert_equal cert, found
    assert found.expired?
  end

  # --- BR-091/BR-092: holder_deactivated? y downloadable? ---

  test "holder_deactivated? reflects the member status" do
    cert = issued_certificate
    assert_not cert.holder_deactivated?

    @member.deactivate!(reason: "ya no reside en el domicilio")
    assert cert.reload.holder_deactivated?
  end

  test "downloadable? is true only for vigente cert with active holder" do
    cert = issued_certificate
    assert cert.downloadable?
  end

  test "downloadable? is false for expired cert (BR-092)" do
    cert = issued_certificate(expiration: 1.month.ago)
    assert_not cert.downloadable?
  end

  test "downloadable? is false when holder was deactivated (BR-091)" do
    cert = issued_certificate
    @member.deactivate!(reason: "fraude detectado")
    assert_not cert.reload.downloadable?
  end

  test "downloadable? is false for non-issued certificates" do
    cert = ResidenceCertificate.create!(
      member: @member,
      household_unit: @household_unit,
      neighborhood_association: @association,
      purpose: "test",
      status: "pending_payment"
    )
    assert_not cert.downloadable?
  end

  # --- Task 1: payment_status + payment_reverted? + inmutabilidad ---

  test "payment_reverted? is true only for refunded and charged_back" do
    cert = ResidenceCertificate.new
    %w[refunded charged_back].each do |s|
      cert.payment_status = s
      assert cert.payment_reverted?, "#{s} debería contar como revertido"
    end
    %w[approved in_process pending rejected cancelled].each do |s|
      cert.payment_status = s
      assert_not cert.payment_reverted?, "#{s} no debería contar como revertido"
    end
    cert.payment_status = nil
    assert_not cert.payment_reverted?
  end

  test "downloadable? is false when payment was reverted" do
    cert = ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit, neighborhood_association: @association,
      purpose: "trámite", status: "issued", folio: "CR-#{@association.id}-9001",
      issue_date: Date.current, expiration_date: 30.days.from_now.to_date, issued_at: Time.current,
      payment_status: "charged_back"
    )
    assert_not cert.downloadable?, "un cert con pago revertido no debe poder descargarse"
  end

  test "payment_status can be updated on an issued certificate (not blocked by immutability)" do
    cert = ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit, neighborhood_association: @association,
      purpose: "trámite", status: "issued", folio: "CR-#{@association.id}-9002",
      issue_date: Date.current, expiration_date: 30.days.from_now.to_date, issued_at: Time.current
    )
    assert cert.update(payment_status: "charged_back"), cert.errors.full_messages.to_sentence
    assert_equal "charged_back", cert.reload.payment_status
  end

  test "other fields remain immutable on an issued certificate" do
    cert = ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit, neighborhood_association: @association,
      purpose: "trámite", status: "issued", folio: "CR-#{@association.id}-9003",
      issue_date: Date.current, expiration_date: 30.days.from_now.to_date, issued_at: Time.current
    )
    assert_not cert.update(purpose: "otro")
    assert cert.errors[:base].any?
  end

  # --- Task 2: apply_mp_payment_status! ---

  test "apply_mp_payment_status! registers non-approved status without changing business status" do
    cert = ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit, neighborhood_association: @association,
      purpose: "trámite", status: "pending_payment", amount: 1500
    )
    cert.apply_mp_payment_status!("in_process")
    assert_equal "in_process", cert.payment_status
    assert cert.pending_payment?
  end

  test "apply_mp_payment_status! reverts a paid (not issued) certificate to pending_payment" do
    cert = ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit, neighborhood_association: @association,
      purpose: "trámite", status: "paid", amount: 1500, payment_id: "MP-REV-1", paid_at: Time.current
    )
    cert.apply_mp_payment_status!("refunded")
    assert_equal "refunded", cert.payment_status
    assert cert.pending_payment?
    assert_equal "MP-REV-1", cert.payment_id, "el payment_id se conserva como dato de auditoría"
  end

  test "apply_mp_payment_status! keeps an issued certificate issued but marks it reverted" do
    cert = ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit, neighborhood_association: @association,
      purpose: "trámite", status: "issued", folio: "CR-#{@association.id}-9101",
      issue_date: Date.current, expiration_date: 30.days.from_now.to_date, issued_at: Time.current
    )
    cert.apply_mp_payment_status!("charged_back")
    assert cert.issued?
    assert cert.payment_reverted?
    assert_not cert.downloadable?, "un cert emitido con pago revertido no debe poder descargarse"
  end

  test "apply_mp_payment_status! is idempotent for the same status" do
    cert = ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit, neighborhood_association: @association,
      purpose: "trámite", status: "pending_payment", amount: 1500, payment_status: "in_process"
    )
    assert_no_changes -> { cert.reload.updated_at } do
      cert.apply_mp_payment_status!("in_process")
    end
  end

  # --- #107: holder_deactivated? cubre todo estado no-aprobado del Member ---

  test "holder_deactivated? is true for any non-approved member state (#107)" do
    cert = ResidenceCertificate.create!(
      member: @member, household_unit: @household_unit, neighborhood_association: @association,
      purpose: "trámite", status: "issued", folio: "CR-#{@association.id}-8107",
      issue_date: Date.current, expiration_date: 30.days.from_now.to_date, issued_at: Time.current
    )

    @member.update_column(:status, "approved")
    assert_not cert.holder_deactivated?
    assert cert.downloadable?

    %w[inactive rejected pending].each do |state|
      @member.update_column(:status, state)
      assert cert.holder_deactivated?, "member #{state} debe invalidar el certificado"
      assert_not cert.downloadable?, "member #{state} no debe permitir descarga"
    end
  end
end
