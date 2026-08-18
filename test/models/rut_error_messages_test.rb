require "test_helper"

# `RunValidator` agrega errores con las claves `:invalid_rut_format` e
# `:invalid_rut_check_digit`. Durante mucho tiempo esas traducciones existían solo
# repetidas bajo `models:` para dos modelos, así que cualquier otro modelo que
# usara el validador mostraba "Translation missing: es.…" **en pantalla al
# usuario final** (pasaba en AdministrationRequest y NeighborhoodAssociation).
#
# Ahora viven en el fallback global `es.errors.messages`. Este test existe para
# que agregar el validador a un modelo nuevo no vuelva a filtrar el error crudo.
class RutErrorMessagesTest < ActiveSupport::TestCase
  RUT_ATTRIBUTES = [
    [AdministrationRequest, :organization_rut],
    [AdministrationRequest, :run],
    [IdentityVerificationRequest, :run],
    [VerifiedIdentity, :run],
    [NeighborhoodAssociation, :rut]
  ].freeze

  INVALID_CHECK_DIGIT = "16789234-3" # formato válido, dígito verificador incorrecto
  INVALID_FORMAT = "no-es-un-rut"

  test "todo modelo con RunValidator traduce el error de dígito verificador" do
    assert_all_messages_translated(INVALID_CHECK_DIGIT)
  end

  test "todo modelo con RunValidator traduce el error de formato" do
    assert_all_messages_translated(INVALID_FORMAT)
  end

  private

  def assert_all_messages_translated(value)
    RUT_ATTRIBUTES.each do |klass, attribute|
      record = klass.new(attribute => value)
      record.valid?

      messages = record.errors.full_messages_for(attribute)
      assert_not_empty messages, "#{klass}##{attribute} debería rechazar #{value.inspect}"

      messages.each do |message|
        assert_no_match(/translation missing/i, message,
          "#{klass}##{attribute} muestra el error de i18n sin traducir: #{message}")
      end
    end
  end
end
