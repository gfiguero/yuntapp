class RunValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    return if value.blank?

    unless valid_run_format?(value)
      record.errors.add(attribute, :invalid_rut_format)
      return
    end

    unless valid_run_check_digit?(value)
      record.errors.add(attribute, :invalid_rut_check_digit)
    end
  end

  private

  def valid_run_format?(run)
    # Formato esperado: 12345678-K (ya normalizado antes de validar) o 12345678K
    # La normalización previa en el modelo debería dejarlo como 12345678-K
    run.match?(/\A\d{7,8}-[\dkK]\z/i)
  end

  def valid_run_check_digit?(run)
    body, dv = run.split("-")
    return false unless body && dv

    computed_dv = calculate_dv(body)
    computed_dv.to_s.upcase == dv.to_s.upcase
  end

  def calculate_dv(body)
    sum = 0
    multiplier = 2

    body.to_s.reverse.each_char do |char|
      sum += char.to_i * multiplier
      multiplier = (multiplier == 7) ? 2 : multiplier + 1
    end

    remainder = 11 - (sum % 11)
    case remainder
    when 11 then "0"
    when 10 then "K"
    else remainder.to_s
    end
  end
end
