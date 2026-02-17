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

ActiveRecord::Schema[8.1].define(version: 2026_02_17_020706) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "board_members", force: :cascade do |t|
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.date "end_date"
    t.integer "member_id", null: false
    t.integer "neighborhood_association_id", null: false
    t.string "position", null: false
    t.date "start_date"
    t.datetime "updated_at", null: false
    t.index ["member_id"], name: "index_board_members_on_member_id"
    t.index ["neighborhood_association_id"], name: "index_board_members_on_neighborhood_association_id"
  end

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

  create_table "identity_verification_requests", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "first_name"
    t.string "last_name"
    t.integer "onboarding_request_id"
    t.string "phone"
    t.text "rejection_reason"
    t.string "run"
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["onboarding_request_id"], name: "index_identity_verification_requests_on_onboarding_request_id"
    t.index ["user_id"], name: "index_identity_verification_requests_on_user_id"
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
    t.datetime "approved_at"
    t.integer "approved_by_id"
    t.datetime "created_at", null: false
    t.boolean "household_admin", default: false
    t.integer "household_unit_id", null: false
    t.text "rejection_reason"
    t.integer "requested_by_id"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.integer "verified_identity_id", null: false
    t.index ["approved_by_id"], name: "index_members_on_approved_by_id"
    t.index ["household_unit_id"], name: "index_members_on_household_unit_id"
    t.index ["requested_by_id"], name: "index_members_on_requested_by_id"
    t.index ["status"], name: "index_members_on_status"
    t.index ["verified_identity_id"], name: "index_members_on_verified_identity_id"
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

  create_table "onboarding_requests", force: :cascade do |t|
    t.integer "commune_id"
    t.datetime "created_at", null: false
    t.integer "neighborhood_association_id"
    t.integer "region_id"
    t.text "rejection_reason"
    t.string "status", default: "draft", null: false
    t.datetime "terms_accepted_at"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["commune_id"], name: "index_onboarding_requests_on_commune_id"
    t.index ["neighborhood_association_id"], name: "index_onboarding_requests_on_neighborhood_association_id"
    t.index ["region_id"], name: "index_onboarding_requests_on_region_id"
    t.index ["user_id"], name: "index_onboarding_requests_on_user_id"
  end

  create_table "regions", force: :cascade do |t|
    t.integer "country_id", null: false
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["country_id"], name: "index_regions_on_country_id"
  end

  create_table "residence_certificates", force: :cascade do |t|
    t.integer "approved_by_id"
    t.datetime "created_at", null: false
    t.date "expiration_date"
    t.string "folio"
    t.integer "household_unit_id", null: false
    t.date "issue_date"
    t.integer "member_id", null: false
    t.integer "neighborhood_association_id", null: false
    t.text "notes"
    t.text "purpose"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["approved_by_id"], name: "index_residence_certificates_on_approved_by_id"
    t.index ["household_unit_id"], name: "index_residence_certificates_on_household_unit_id"
    t.index ["member_id"], name: "index_residence_certificates_on_member_id"
    t.index ["neighborhood_association_id", "folio"], name: "index_residence_certificates_on_association_and_folio", unique: true
    t.index ["neighborhood_association_id"], name: "index_residence_certificates_on_neighborhood_association_id"
  end

  create_table "residence_verification_requests", force: :cascade do |t|
    t.string "address_line_1"
    t.string "address_line_2"
    t.integer "commune_id", null: false
    t.datetime "created_at", null: false
    t.boolean "manual_address", default: false, null: false
    t.integer "neighborhood_association_id", null: false
    t.integer "neighborhood_delegation_id"
    t.string "number"
    t.integer "onboarding_request_id"
    t.text "rejection_reason"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["commune_id"], name: "index_residence_verification_requests_on_commune_id"
    t.index ["neighborhood_association_id"], name: "idx_on_neighborhood_association_id_8284982259"
    t.index ["neighborhood_delegation_id"], name: "idx_on_neighborhood_delegation_id_53d3fd92d5"
    t.index ["onboarding_request_id"], name: "index_residence_verification_requests_on_onboarding_request_id"
    t.index ["user_id"], name: "index_residence_verification_requests_on_user_id"
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
    t.integer "neighborhood_association_id"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.boolean "superadmin", default: false
    t.datetime "updated_at", null: false
    t.integer "verified_identity_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["neighborhood_association_id"], name: "index_users_on_neighborhood_association_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["verified_identity_id"], name: "index_users_on_verified_identity_id"
  end

  create_table "verified_identities", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "first_name", null: false
    t.string "last_name", null: false
    t.string "phone"
    t.string "run", null: false
    t.datetime "updated_at", null: false
    t.string "verification_status", default: "pending", null: false
    t.index ["run"], name: "index_verified_identities_on_run", unique: true
    t.index ["verification_status"], name: "index_verified_identities_on_verification_status"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "board_members", "members"
  add_foreign_key "board_members", "neighborhood_associations"
  add_foreign_key "communes", "regions"
  add_foreign_key "household_units", "communes"
  add_foreign_key "household_units", "neighborhood_delegations"
  add_foreign_key "identity_verification_requests", "onboarding_requests"
  add_foreign_key "identity_verification_requests", "users"
  add_foreign_key "listings", "categories"
  add_foreign_key "listings", "users"
  add_foreign_key "members", "household_units"
  add_foreign_key "members", "users", column: "approved_by_id"
  add_foreign_key "members", "users", column: "requested_by_id"
  add_foreign_key "members", "verified_identities"
  add_foreign_key "neighborhood_associations", "communes"
  add_foreign_key "neighborhood_delegations", "neighborhood_associations"
  add_foreign_key "onboarding_requests", "communes"
  add_foreign_key "onboarding_requests", "neighborhood_associations"
  add_foreign_key "onboarding_requests", "regions"
  add_foreign_key "onboarding_requests", "users"
  add_foreign_key "regions", "countries"
  add_foreign_key "residence_certificates", "household_units"
  add_foreign_key "residence_certificates", "members"
  add_foreign_key "residence_certificates", "neighborhood_associations"
  add_foreign_key "residence_certificates", "users", column: "approved_by_id"
  add_foreign_key "residence_verification_requests", "communes"
  add_foreign_key "residence_verification_requests", "neighborhood_associations"
  add_foreign_key "residence_verification_requests", "neighborhood_delegations"
  add_foreign_key "residence_verification_requests", "onboarding_requests"
  add_foreign_key "residence_verification_requests", "users"
  add_foreign_key "users", "neighborhood_associations"
  add_foreign_key "users", "verified_identities"
end
