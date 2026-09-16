# frozen_string_literal: true

class AddGroupMetadataToConversations < ActiveRecord::Migration[8.0]
  def change
    add_column :conversations, :title, :string

    create_table :conversation_memberships do |t|
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.integer :role, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :conversation_memberships, [:conversation_id, :account_id], unique: true, name: 'index_conversation_memberships_on_convo_and_account'
    add_index :conversation_memberships, [:conversation_id, :active], name: 'index_conversation_memberships_on_convo_and_active'
    add_index :conversation_memberships, :account_id
  end
end
