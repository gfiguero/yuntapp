json.array! @regions do |region|
  json.value region.id
  json.text region.name
end
