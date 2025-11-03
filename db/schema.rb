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

ActiveRecord::Schema[8.1].define(version: 2025_11_03_175111) do
  create_table "follows", id: false, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "followed_id", null: false
    t.bigint "follower_id", null: false
    t.datetime "updated_at", null: false
    t.index ["followed_id"], name: "index_follows_on_followed_id"
    t.index ["follower_id", "followed_id"], name: "index_follows_on_follower_id_and_followed_id", unique: true
  end

  create_table "posts", force: :cascade do |t|
    t.integer "author_id"
    t.string "content", limit: 200, null: false
    t.datetime "created_at", null: false
    t.integer "parent_id"
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_posts_on_author_id"
    t.index ["created_at"], name: "index_posts_on_created_at"
    t.index ["parent_id"], name: "index_posts_on_parent_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description", limit: 120
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.string "username", limit: 50, null: false
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "follows", "users", column: "followed_id", on_delete: :cascade
  add_foreign_key "follows", "users", column: "follower_id", on_delete: :cascade
  add_foreign_key "posts", "posts", column: "parent_id", on_delete: :nullify
  add_foreign_key "posts", "users", column: "author_id", on_delete: :nullify
end
