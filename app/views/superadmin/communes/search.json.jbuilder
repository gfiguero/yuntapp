json.array! @communes do |commune|
  json.value commune.id
  json.text commune.name
end
