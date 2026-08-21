require "test_helper"

# Los documentos que sube el vecino (cédula, comprobante de domicilio) no tenían
# ninguna validación de tipo ni de tamaño. Active Storage escribe en el mismo
# disco que la base SQLite, así que una subida grande podía llenar el disco y
# dejar la aplicación sin poder escribir. Detectado en la auditoría del
# 2026-08-21.
class AttachmentLimitsTest < ActiveSupport::TestCase
  setup do
    @identity_request = identity_verification_requests(:karass_identity)
  end

  def attach(record, name, filename:, content_type:, size: 1.kilobyte)
    record.public_send(name).attach(
      io: StringIO.new("x" * size),
      filename: filename,
      content_type: content_type
    )
    record
  end

  # --- Tipo ---

  test "acepta una foto de cédula en JPEG" do
    attach(@identity_request, :identity_documents, filename: "cedula.jpg", content_type: "image/jpeg")
    assert @identity_request.valid?, @identity_request.errors.full_messages.to_sentence
  end

  test "acepta un PDF" do
    attach(@identity_request, :identity_documents, filename: "cedula.pdf", content_type: "application/pdf")
    assert @identity_request.valid?, @identity_request.errors.full_messages.to_sentence
  end

  test "acepta HEIC, que es lo que sube un iPhone por defecto" do
    attach(@identity_request, :identity_documents, filename: "IMG_0001.heic", content_type: "image/heic")
    assert @identity_request.valid?, @identity_request.errors.full_messages.to_sentence
  end

  test "rechaza un ejecutable" do
    attach(@identity_request, :identity_documents, filename: "virus.exe", content_type: "application/x-msdownload")
    assert_not @identity_request.valid?
    assert @identity_request.errors[:identity_documents].any?
  end

  test "rechaza un video" do
    attach(@identity_request, :identity_documents, filename: "clip.mp4", content_type: "video/mp4")
    assert_not @identity_request.valid?
    assert @identity_request.errors[:identity_documents].any?
  end

  # --- Tamaño ---

  test "acepta una foto de celular de tamaño realista" do
    attach(@identity_request, :identity_documents, filename: "foto.jpg", content_type: "image/jpeg", size: 6.megabytes)
    assert @identity_request.valid?, @identity_request.errors.full_messages.to_sentence
  end

  test "rechaza un archivo que excede el límite" do
    attach(@identity_request, :identity_documents, filename: "enorme.jpg", content_type: "image/jpeg", size: 11.megabytes)
    assert_not @identity_request.valid?
    assert @identity_request.errors[:identity_documents].any?
  end

  # --- Cobertura de todos los adjuntos que sube el usuario ---

  test "el comprobante de domicilio también valida tipo" do
    rvr = residence_verification_requests(:karass_residence)
    attach(rvr, :residence_documents, filename: "boleta.exe", content_type: "application/x-msdownload")
    assert_not rvr.valid?
    assert rvr.errors[:residence_documents].any?
  end

  test "el certificado de vigencia de la directiva también valida tamaño" do
    r = AdministrationRequest.new(
      user: users(:rohana), status: "draft",
      neighborhood_association: neighborhood_associations(:manios_de_buin)
    )
    attach(r, :directiva_validity_document, filename: "vigencia.pdf", content_type: "application/pdf", size: 11.megabytes)
    assert_not r.valid?
    assert r.errors[:directiva_validity_document].any?
  end

  # El PDF del certificado lo genera el sistema, no el usuario: no debe quedar
  # sujeto a los límites de subida.
  test "el PDF generado del certificado no valida tipo de subida" do
    assert_not ResidenceCertificate.validators_on(:pdf_document).any?,
      "el PDF emitido por la plataforma no pasa por los límites de subida del usuario"
  end
end
