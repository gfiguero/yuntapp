# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_01_16_033526) do
  create_table "categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "communes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.integer "region_id", null: false
    t.datetime "updated_at", null: false
    t.index ["region_id"], name: "index_communes_on_region_id"
  end

  create_table "countries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "iso_code"
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "household_units", force: :cascade do |t|
    t.string "address_line_1"
    t.string "address_line_2"
    t.string "city"
    t.integer "commune_id"
    t.string "country"
    t.datetime "created_at", null: false
    t.integer "neighborhood_delegation_id", null: false
    t.string "number"
    t.string "postal_code"
    t.string "region"
    t.datetime "updated_at", null: false
    t.index ["commune_id"], name: "index_household_units_on_commune_id"
    t.index ["neighborhood_delegation_id"], name: "index_household_units_on_neighborhood_delegation_id"
  end

  create_table "listings", force: :cascade do |t|
    t.boolean "active"
    t.integer "category_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name"
    t.decimal "price"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["category_id"], name: "index_listings_on_category_id"
    t.index ["user_id"], name: "index_listings_on_user_id"
  end

  create_table "members", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "first_name"
    t.integer "household_unit_id", null: false
    t.string "last_name"
    t.string "phone"
    t.string "run"
    t.datetime "updated_at", null: false
    t.index ["household_unit_id"], name: "index_members_on_household_unit_id"
  end

  create_table "neighborhood_associations", force: :cascade do |t|
    t.integer "commune_id"
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["commune_id"], name: "index_neighborhood_associations_on_commune_id"
  end

  create_table "neighborhood_delegations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.integer "neighborhood_association_id", null: false
    t.datetime "updated_at", null: false
    t.index ["neighborhood_association_id"], name: "index_neighborhood_delegations_on_neighborhood_association_id"
  end

  create_table "regions", force: :cascade do |t|
    t.integer "country_id", null: false
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["country_id"], name: "index_regions_on_country_id"
  end

  create_table "tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin"
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "first_name"
    t.string "last_name"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "communes", "regions"
  add_foreign_key "household_units", "communes"
  add_foreign_key "household_units", "neighborhood_delegations"
  add_foreign_key "listings", "categories"
  add_foreign_key "listings", "users"
  add_foreign_key "members", "household_units"
  add_foreign_key "neighborhood_associations", "communes"
  add_foreign_key "neighborhood_delegations", "neighborhood_associations"
  add_foreign_key "regions", "countries"
end
