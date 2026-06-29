# Preview all emails at http://localhost:3000/rails/mailers/residence_certificate_mailer
class ResidenceCertificateMailerPreview < ActionMailer::Preview
  # Preview this email at http://localhost:3000/rails/mailers/residence_certificate_mailer/issued
  def issued
    ResidenceCertificateMailer.issued
  end
end
