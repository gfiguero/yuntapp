class PhoneValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return if value.blank?

    # Normalizar para validación (eliminar espacios, guiones, paréntesis)
    normalized_phone = value.to_s.gsub(/[\s\-()]/, "")

    # Validar formato: debe empezar con +569 seguido de 8 dígitos
    # Opcionalmente aceptamos 569... o 9... y asumimos que se normalizará después
    # Pero la validación estricta pide +569XXXXXXXX

    unless normalized_phone.match?(/\A\+569\d{8}\z/)
      record.errors.add(attribute, :invalid_phone_format)
    end
  end
end
