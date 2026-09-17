class CreateAccounts < ActiveRecord::Migration[8.1]
  def change
    create_table :roles do |t|
      t.string  :name, null: false
      t.string  :description
      t.integer :rank, null: false, default: 0
      t.timestamps
    end
    add_index :roles, :name, unique: true

    create_table :permissions do |t|
      t.string :key, null: false
      t.string :label, null: false
      t.timestamps
    end
    add_index :permissions, :key, unique: true

    create_table :role_permissions do |t|
      t.references :role, null: false, foreign_key: true
      t.references :permission, null: false, foreign_key: true
    end
    add_index :role_permissions, [ :role_id, :permission_id ], unique: true

    create_table :users do |t|
      t.string  :username, null: false
      t.string  :display_name, null: false
      t.string  :email, null: false
      t.string  :password_hash, null: false
      t.text    :bio, null: false, default: ""
      t.string  :location, null: false, default: ""
      t.string  :website, null: false, default: ""
      t.string  :avatar_path
      t.string  :banner_path
      t.references :role, null: false, foreign_key: true
      t.boolean :is_suspended, null: false, default: false
      t.boolean :is_verified, null: false, default: false
      t.boolean :is_banned, null: false, default: false
      t.text    :ban_reason, null: false, default: ""
      t.boolean :ban_permanent, null: false, default: false
      t.datetime :ban_expires_at
      t.integer :bonus_followers, null: false, default: 0
      t.datetime :last_login_at
      t.timestamps
    end
    # Usernames and emails are unique regardless of case, matching the
    # behaviour of the original client.
    execute "CREATE UNIQUE INDEX index_users_on_username ON users (username COLLATE NOCASE)"
    execute "CREATE UNIQUE INDEX index_users_on_email ON users (email COLLATE NOCASE)"

    create_table :sessions do |t|
      t.string   :token, null: false
      t.references :user, null: false, foreign_key: true
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :sessions, :token, unique: true

    create_table :site_settings do |t|
      t.string :key, null: false
      t.text   :value, null: false, default: ""
      t.timestamps
    end
    add_index :site_settings, :key, unique: true

    create_table :audit_logs do |t|
      t.references :actor, foreign_key: { to_table: :users }
      t.string :action, null: false
      t.string :target, null: false, default: ""
      t.text   :detail, null: false, default: ""
      t.timestamps
    end
  end
end