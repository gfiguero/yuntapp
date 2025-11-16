json.extract! listing, :id, :name, :description, :price, :active, :user_id, :created_at, :updated_at
json.url listing_url(listing, format: :json)
