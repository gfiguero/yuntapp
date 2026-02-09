json.array! @board_members do |board_member|
  json.value board_member.id
  json.text board_member.member.name
end
