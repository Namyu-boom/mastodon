# frozen_string_literal: true

class CreateStatusAutomationCards < ActiveRecord::Migration[8.0]
  def change
    create_table :status_automation_cards do |t|
      t.references :status, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.references :source_rule, foreign_key: { to_table: :conversation_automation_rules, on_delete: :nullify }
      t.text :prompt, null: false
      t.timestamps
    end

    create_table :status_automation_choices do |t|
      t.references :status_automation_card, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :label, null: false
      t.text :response_text, null: false
      t.string :image_url
      t.integer :position, null: false, default: 0
      t.timestamps
      t.index [:status_automation_card_id, :position], name: 'index_status_automation_choices_on_card_and_position'
    end

    create_table :status_automation_executions do |t|
      t.references :status_automation_card, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :status_automation_choice, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :selected_by_account, null: false, foreign_key: { to_table: :accounts, on_delete: :cascade }, index: false
      t.references :response_status, foreign_key: { to_table: :statuses, on_delete: :nullify }, index: false
      t.timestamps
      t.index [:status_automation_card_id, :selected_by_account_id], unique: true, name: 'index_status_automation_executions_once_per_account'
      t.index :status_automation_choice_id, name: 'index_status_automation_executions_on_choice_id'
      t.index :response_status_id, name: 'index_status_automation_executions_on_response_status_id'
    end
  end
end
