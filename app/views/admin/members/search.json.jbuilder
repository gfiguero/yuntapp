json.array! @members do |member|
  json.value member.id
  json.text member.name
end
