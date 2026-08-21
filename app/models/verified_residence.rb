class VerifiedResidence < ApplicationRecord
  include AttachmentLimits

  validates_document_attachments :residence_documents

  belongs_to :residence_verification_request, optional: true
  belongs_to :neighborhood_delegation, optional: true
  belongs_to :commune, optional: true
  belongs_to :neighborhood_association

  has_many :household_units
  has_many_attached :residence_documents

  def address
    [street_name, number, address_detail].compact_blank.join(", ")
  end
end
