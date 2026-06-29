require "prawn"
require "rqrcode"
require "stringio"

# Genera el PDF del certificado de residencia con Prawn y lo adjunta al
# certificado vía Active Storage. Incluye QR code, código alfanumérico y URL
# de verificación pública (cubierta por PR-C).
class CertificatePdfService
  def initialize(certificate)
    @certificate = certificate
  end

  def generate_and_attach!
    pdf_bytes = render
    @certificate.pdf_document.attach(
      io: StringIO.new(pdf_bytes),
      filename: "certificado-#{@certificate.folio}.pdf",
      content_type: "application/pdf"
    )
  end

  def render
    pdf = Prawn::Document.new(page_size: "A4", margin: 48)
    draw_header(pdf)
    draw_body(pdf)
    draw_validation_block(pdf)
    draw_footer(pdf)
    pdf.render
  end

  private

  def draw_header(pdf)
    pdf.font_size(22) { pdf.text "Yuntapp", style: :bold, align: :center }
    pdf.move_down 4
    pdf.font_size(14) { pdf.text association_name, align: :center }
    pdf.move_down 12
    pdf.stroke_horizontal_rule
    pdf.move_down 16
    pdf.font_size(18) { pdf.text "Certificado de Residencia", style: :bold, align: :center }
    pdf.move_down 6
    pdf.font_size(10) { pdf.text "Folio: #{@certificate.folio}", align: :center }
    pdf.move_down 24
  end

  def draw_body(pdf)
    pdf.font_size(11)
    pdf.text "Por el presente, la #{association_name} certifica que:"
    pdf.move_down 12
    pdf.font_size(13) do
      pdf.text member_full_name, style: :bold
      pdf.text "RUN: #{member_run}"
    end
    pdf.move_down 12
    pdf.font_size(11) do
      pdf.text "Tiene su domicilio registrado en:"
      pdf.text address_line, style: :bold
    end
    pdf.move_down 12
    pdf.font_size(11) do
      pdf.text "Propósito declarado: #{@certificate.purpose}"
    end
    pdf.move_down 24
    pdf.font_size(10) do
      pdf.text "Fecha de emisión: #{I18n.l(@certificate.issue_date)}"
      pdf.text "Fecha de vencimiento: #{I18n.l(@certificate.expiration_date)}"
    end
    pdf.move_down 24
  end

  def draw_validation_block(pdf)
    pdf.stroke_horizontal_rule
    pdf.move_down 16
    pdf.font_size(11) { pdf.text "Verificación de autenticidad", style: :bold }
    pdf.move_down 8

    qr_x = pdf.bounds.right - 110
    qr_y = pdf.cursor

    pdf.bounding_box([0, qr_y], width: qr_x - 16, height: 110) do
      pdf.font_size(10) do
        pdf.text "Escanea el QR o ingresa el código en:"
        pdf.move_down 4
        pdf.text verification_url, style: :italic
        pdf.move_down 8
        pdf.text "Código de verificación:"
        pdf.font_size(14) { pdf.text @certificate.validation_code, style: :bold }
      end
    end

    pdf.bounding_box([qr_x, qr_y], width: 110, height: 110) do
      pdf.image qr_io, fit: [100, 100]
    end

    pdf.move_down 24
  end

  def draw_footer(pdf)
    pdf.font_size(8) do
      pdf.text "Este certificado es válido por 6 meses desde la fecha de emisión. " \
               "Su autenticidad puede verificarse en cualquier momento ingresando el código " \
               "o escaneando el QR en la URL indicada.", align: :justify, color: "666666"
    end
  end

  def association_name
    @certificate.neighborhood_association.name.to_s
  end

  def member_full_name
    @certificate.member.name.to_s
  end

  def member_run
    @certificate.member.run.to_s
  end

  def address_line
    hu = @certificate.household_unit
    parts = [hu.street_name, hu.number, hu.address_detail].compact_blank
    parts.join(" ")
  end

  def verification_url
    base = Rails.application.config.x.verification_base_url.presence || default_base_url
    "#{base.chomp("/")}/verify/#{@certificate.validation_token}"
  end

  def default_base_url
    host = ENV["YUNTAPP_HOST"] || "yuntapp.cl"
    "https://#{host}"
  end

  def qr_io
    qr = RQRCode::QRCode.new(verification_url, size: 6, level: :m)
    png = qr.as_png(size: 240, border_modules: 2)
    StringIO.new(png.to_datastream.to_blob)
  end
end
