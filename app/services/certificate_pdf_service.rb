require "prawn"
require "rqrcode"
require "stringio"

# Genera el PDF del certificado de residencia con Prawn y lo adjunta al
# certificado vía Active Storage. Incluye QR code, código alfanumérico y URL
# de verificación pública (BR-074/BR-075).
#
# Diseño: documento institucional A4 con marco doble, encabezado de la junta
# emisora, titular destacado al centro, caja de detalles y panel de
# verificación con QR. Solo usa fuentes nativas de Prawn (Helvetica).
class CertificatePdfService
  NAVY = "1F3A5F"
  GOLD = "B8933A"
  TEXT = "1F2937"
  GRAY = "6B7280"
  LIGHT = "F4F5F7"

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
    pdf = Prawn::Document.new(page_size: "A4", margin: 60)
    draw_frame(pdf)
    draw_header(pdf)
    draw_body(pdf)
    draw_validation_block(pdf)
    draw_footer(pdf)
    pdf.render
  end

  private

  # Marco doble alrededor de la página: línea gruesa exterior + fina interior.
  def draw_frame(pdf)
    pdf.canvas do
      pdf.stroke_color NAVY
      pdf.line_width 1.6
      pdf.stroke_rectangle [26, pdf.bounds.top - 26], pdf.bounds.width - 52, pdf.bounds.height - 52
      pdf.line_width 0.6
      pdf.stroke_rectangle [32, pdf.bounds.top - 32], pdf.bounds.width - 64, pdf.bounds.height - 64
    end
    pdf.stroke_color "000000"
    pdf.line_width 1
    pdf.move_cursor_to pdf.bounds.top
  end

  def draw_header(pdf)
    pdf.font_size(9) { pdf.text "JUNTA DE VECINOS", align: :center, color: GRAY, character_spacing: 2 }
    pdf.move_down 4
    pdf.font_size(17) { pdf.text association_name, style: :bold, align: :center, color: NAVY }
    if commune_name.present?
      pdf.move_down 2
      pdf.font_size(9) { pdf.text "Comuna de #{commune_name}", align: :center, color: GRAY }
    end

    pdf.move_down 14
    center = pdf.bounds.width / 2
    pdf.stroke_color GOLD
    pdf.line_width 1.4
    pdf.stroke_horizontal_line center - 70, center + 70, at: pdf.cursor
    pdf.stroke_color "000000"
    pdf.line_width 1

    pdf.move_down 20
    pdf.font_size(21) { pdf.text "CERTIFICADO DE RESIDENCIA", style: :bold, align: :center, color: NAVY, character_spacing: 1.2 }
    pdf.move_down 6
    pdf.font_size(10) { pdf.text "Folio Nº #{@certificate.folio}", align: :center, color: GRAY }
    pdf.move_down 26
  end

  def draw_body(pdf)
    pdf.font_size(11) do
      pdf.text "La #{association_name} certifica que, conforme a la verificación de identidad y domicilio realizada por su directiva:",
        align: :center, color: TEXT
    end

    pdf.move_down 18
    pdf.font_size(19) { pdf.text member_full_name, style: :bold, align: :center, color: NAVY }
    pdf.move_down 2
    pdf.font_size(11) { pdf.text "RUN #{member_run}", align: :center, color: GRAY }

    pdf.move_down 16
    pdf.font_size(11) { pdf.text "mantiene su domicilio registrado en", align: :center, color: TEXT }
    pdf.move_down 4
    pdf.font_size(13) { pdf.text full_address_line, style: :bold, align: :center, color: TEXT }

    pdf.move_down 24
    draw_details_box(pdf)
    pdf.move_down 24
  end

  # Caja gris con tres columnas: propósito, emisión y vencimiento.
  def draw_details_box(pdf)
    height = 56
    y = pdf.cursor
    pdf.fill_color LIGHT
    pdf.fill_rounded_rectangle [0, y], pdf.bounds.width, height, 6
    pdf.fill_color "000000"

    columns = [
      ["PROPÓSITO", @certificate.purpose.to_s],
      ["FECHA DE EMISIÓN", I18n.l(@certificate.issue_date)],
      ["FECHA DE VENCIMIENTO", I18n.l(@certificate.expiration_date)]
    ]
    col_width = pdf.bounds.width / 3.0

    columns.each_with_index do |(label, value), i|
      x = i * col_width + 14
      pdf.fill_color GRAY
      pdf.text_box label, at: [x, y - 12], width: col_width - 28, size: 7.5, character_spacing: 1
      pdf.fill_color TEXT
      pdf.text_box value, at: [x, y - 26], width: col_width - 28, height: height - 34,
        size: 10.5, style: :bold, overflow: :shrink_to_fit
    end

    pdf.fill_color "000000"
    pdf.move_cursor_to y - height
  end

  # Panel de verificación: instrucciones y código a la izquierda, QR a la derecha.
  def draw_validation_block(pdf)
    height = 132
    pad = 16
    y = pdf.cursor

    pdf.fill_color LIGHT
    pdf.fill_rounded_rectangle [0, y], pdf.bounds.width, height, 6

    qr_size = 96
    white_pad = 8
    qr_box_size = qr_size + white_pad * 2
    qr_box_x = pdf.bounds.width - qr_box_size - pad
    qr_box_y = y - (height - qr_box_size) / 2
    pdf.fill_color "FFFFFF"
    pdf.fill_rounded_rectangle [qr_box_x, qr_box_y], qr_box_size, qr_box_size, 4
    pdf.image qr_io, at: [qr_box_x + white_pad, qr_box_y - white_pad], fit: [qr_size, qr_size]

    text_width = qr_box_x - pad * 2
    pdf.fill_color NAVY
    pdf.text_box "VERIFICACIÓN DE AUTENTICIDAD", at: [pad, y - pad], width: text_width,
      size: 8.5, style: :bold, character_spacing: 1.2
    pdf.fill_color TEXT
    pdf.text_box "Escanea el código QR o ingresa el siguiente código de verificación:",
      at: [pad, y - pad - 16], width: text_width, size: 9.5
    pdf.fill_color NAVY
    pdf.text_box @certificate.validation_code.to_s, at: [pad, y - pad - 44], width: text_width,
      size: 22, style: :bold, character_spacing: 3
    pdf.fill_color GRAY
    pdf.text_box verification_url, at: [pad, y - pad - 76], width: text_width, height: 22,
      size: 8, style: :italic, overflow: :shrink_to_fit

    pdf.fill_color "000000"
    pdf.move_cursor_to y - height
  end

  # Pie fijo al borde inferior del área útil de la página.
  def draw_footer(pdf)
    pdf.bounding_box([0, pdf.bounds.bottom + 58], width: pdf.bounds.width, height: 58) do
      pdf.stroke_color "D1D5DB"
      pdf.line_width 0.5
      pdf.stroke_horizontal_rule
      pdf.stroke_color "000000"
      pdf.line_width 1
      pdf.move_down 8
      pdf.font_size(8) do
        pdf.text "Este certificado es válido por 30 días desde la fecha de emisión. " \
                 "Su autenticidad puede verificarse en cualquier momento ingresando el código " \
                 "o escaneando el QR en la URL indicada.", align: :justify, color: GRAY
      end
      pdf.move_down 6
      pdf.font_size(8) do
        pdf.text "Documento emitido electrónicamente a través de Yuntapp — yuntapp.cl",
          align: :center, color: GRAY
      end
    end
    pdf.fill_color "000000"
  end

  def association_name
    @certificate.neighborhood_association.name.to_s
  end

  def commune_name
    @certificate.household_unit.commune&.name.to_s
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

  def full_address_line
    commune_name.present? ? "#{address_line}, #{commune_name}" : address_line
  end

  def verification_url
    # El host lo resuelve config/initializers/verification_url.rb (#102), fuente
    # única para PDF, mailers y QR — no duplicar el fallback aquí.
    base = Rails.application.config.x.verification_base_url
    "#{base.chomp("/")}/verify/#{@certificate.validation_token}"
  end

  def qr_io
    qr = RQRCode::QRCode.new(verification_url, size: 6, level: :m)
    png = qr.as_png(size: 240, border_modules: 2)
    StringIO.new(png.to_datastream.to_blob)
  end
end
