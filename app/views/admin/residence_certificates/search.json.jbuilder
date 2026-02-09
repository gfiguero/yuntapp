json.array! @residence_certificates do |residence_certificate|
  json.value residence_certificate.id
  json.text residence_certificate.folio || "Certificado ##{residence_certificate.id}"
end
