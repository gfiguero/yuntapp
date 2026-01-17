json.array! @neighborhood_delegations do |neighborhood_delegation|
  json.value neighborhood_delegation.id
  json.text neighborhood_delegation.name
end
