json.array! @countries do |country|
  json.value country.id
  json.text country.name
end
