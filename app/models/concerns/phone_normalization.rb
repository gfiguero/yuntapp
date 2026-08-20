module PhoneNormalization
  extend ActiveSupport::Concern

  included do
    before_validation :normalize_phone
  end

  # Normaliza el teléfono al formato +569XXXXXXXX (BR-013).
  #
  # Una entrada que no calza con ninguna forma reconocible se conserva **tal como
  # la escribió el usuario**. Antes se guardaba el resultado de la limpieza, que
  # ante un valor sin dígitos ("no-es-un-telefono") era la cadena vacía: como las
  # validaciones de teléfono corren con `allow_blank`/`if: phone.present?`, no
  # llegaban a ejecutarse y el registro se guardaba sin teléfono, en silencio y
  # con el usuario creyendo que lo había registrado.
  def normalize_phone
    return if phone.blank?

    cleaned = phone.to_s.gsub(/[^0-9+]/, "")
    normalized = case cleaned
    when /\A9\d{8}\z/ then "+56#{cleaned}"       # 987654321
    when /\A569\d{8}\z/ then "+#{cleaned}"       # 56987654321
    when /\A\+569\d{8}\z/ then cleaned           # +56 9 8765 4321
    end

    self.phone = normalized if normalized
  end
end
