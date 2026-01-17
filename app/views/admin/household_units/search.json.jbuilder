json.array! @household_units do |household_unit|
  json.value household_unit.id
  json.text household_unit.name
end
