json.extract! residence_certificate, :id, :folio, :status, :member_id, :household_unit_id, :purpose, :notes, :issue_date, :expiration_date, :created_at, :updated_at
json.url admin_residence_certificate_url(residence_certificate, format: :json)
