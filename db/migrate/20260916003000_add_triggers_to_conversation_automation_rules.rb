# frozen_string_literal: true

class AddTriggersToConversationAutomationRules < ActiveRecord::Migration[8.0]
  def up
    add_column :conversation_automation_rules, :trigger_keyword, :string
    add_column :conversation_automation_rules, :match_in_text, :boolean, null: false, default: false
    add_column :conversation_automation_rules, :default_response_text, :text
    add_column :conversation_automation_rules, :default_image_url, :string

    execute <<~SQL.squish
      UPDATE conversation_automation_rules
      SET trigger_keyword = name
      WHERE trigger_keyword IS NULL
    SQL

    change_column_null :conversation_automation_rules, :trigger_keyword, false
    change_column_null :conversation_automation_executions, :conversation_automation_choice_id, true
  end

  def down
    execute 'DELETE FROM conversation_automation_executions WHERE conversation_automation_choice_id IS NULL'
    change_column_null :conversation_automation_executions, :conversation_automation_choice_id, false
    remove_columns :conversation_automation_rules, :trigger_keyword, :match_in_text, :default_response_text, :default_image_url
  end
end
