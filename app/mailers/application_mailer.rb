class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_DEFAULT_FROM", "no-reply@yuntapp.cl")
  layout "mailer"
end
