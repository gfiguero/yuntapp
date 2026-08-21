# Límites de los documentos que sube el usuario (cédula, comprobante de
# domicilio, certificado de vigencia de la directiva).
#
# Hasta la auditoría del 2026-08-21 no existía ninguna validación: ni de tipo ni
# de tamaño. Active Storage escribe en el mismo disco que la base SQLite, así que
# una subida suficientemente grande llenaba el disco y dejaba a la aplicación sin
# poder escribir. Tampoco había nada que impidiera adjuntar un ejecutable.
#
# No aplica al PDF del certificado: ese lo genera la plataforma, no el usuario.
module AttachmentLimits
  extend ActiveSupport::Concern

  # 10 MB cubre de sobra una foto de cédula: un iPhone reciente produce entre 3 y
  # 8 MB en HEIC, y bastante menos en JPEG.
  MAX_DOCUMENT_SIZE = 10.megabytes

  # HEIC/HEIF es lo que sube un iPhone por defecto, así que rechazarlo sería
  # rechazar a buena parte de los vecinos. PDF es habitual en comprobantes de
  # domicilio y certificados de vigencia.
  ALLOWED_DOCUMENT_TYPES = %w[
    image/jpeg image/png image/webp image/heic image/heif application/pdf
  ].freeze

  class_methods do
    # Declara las validaciones de tipo y tamaño sobre uno o más adjuntos.
    def validates_document_attachments(*names)
      validate do
        names.each do |name|
          Array(public_send(name)).each do |attachment|
            next unless attachment.respond_to?(:blob) && attachment.blob.present?

            unless ALLOWED_DOCUMENT_TYPES.include?(attachment.blob.content_type)
              errors.add(name, :invalid_document_type,
                message: I18n.t("errors.messages.invalid_document_type"))
            end

            if attachment.blob.byte_size > MAX_DOCUMENT_SIZE
              errors.add(name, :document_too_large,
                message: I18n.t("errors.messages.document_too_large",
                  max: MAX_DOCUMENT_SIZE / 1.megabyte))
            end
          end
        end
      end
    end
  end
end
