# frozen_string_literal: true

class CreateConversationAutomation < ActiveRecord::Migration[8.0]
  def change
    create_table :conversation_automation_rules do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.text :prompt, null: false
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    create_table :conversation_automation_choices do |t|
      t.references :conversation_automation_rule, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :label, null: false
      t.text :response_text, null: false
      t.string :image_url
      t.integer :position, null: false, default: 0
      t.timestamps
      t.index [:conversation_automation_rule_id, :position], name: 'index_conversation_automation_choices_on_rule_and_position'
    end

    create_table :conversation_automation_executions do |t|
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :conversation_automation_rule, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :conversation_automation_choice, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :selected_by_account, null: false, foreign_key: { to_table: :accounts, on_delete: :cascade }, index: false
      t.references :response_status, foreign_key: { to_table: :statuses, on_delete: :nullify }, index: false
      t.timestamps
      t.index [:conversation_id, :conversation_automation_rule_id, :selected_by_account_id], unique: true, name: 'index_conversation_automation_executions_once_per_rule'
      t.index :conversation_automation_choice_id, name: 'index_conversation_automation_executions_on_choice_id'
      t.index :response_status_id, name: 'index_conversation_automation_executions_on_response_status_id'
    end
  end
end
