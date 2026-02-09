json.array! @neighborhood_associations do |neighborhood_association|
  json.value neighborhood_association.id
  json.text neighborhood_association.name
end
