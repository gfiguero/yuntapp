json.array! @listings do |listing|
  json.value listing.id
  json.text listing.name
end
