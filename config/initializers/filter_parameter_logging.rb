# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn, :cvv, :cvc
]

# Datos personales de los vecinos. Sin esto quedaban en texto plano en los logs
# de producción cada vez que alguien enviaba el formulario de onboarding: el RUN
# —que en Chile es dato sensible bajo la ley 19.628—, el nombre, el teléfono y el
# domicilio exacto. La lista de arriba es el default de Rails, que filtra
# `:certificate` pero no `:run`. Detectado en la auditoría del 2026-08-21.
#
# `filter_parameters` hace match parcial, así que `:run` cubre también `run_field`
# y similares, y `:name` cubre `first_name`/`last_name`.
Rails.application.config.filter_parameters += [
  :run, :name, :phone, :street_name, :address_detail, :number, :rut
]
