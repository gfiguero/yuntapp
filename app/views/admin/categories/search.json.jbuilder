json.array! @categories do |category|
  json.value category.id
  json.text category.name
end
