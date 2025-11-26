json.array! @tags do |tag|
  json.value tag.id
  json.text tag.name
end
