# frozen_string_literal: true

class ConversationAutomationExecution < ApplicationRecord
  belongs_to :conversation
  belongs_to :conversation_automation_rule
  belongs_to :conversation_automation_choice, optional: true
  belongs_to :selected_by_account, class_name: 'Account'
  belongs_to :response_status, class_name: 'Status', optional: true

  validates :selected_by_account_id, uniqueness: { scope: [:conversation_id, :conversation_automation_rule_id] }
  validate :choice_belongs_to_rule

  private

  def choice_belongs_to_rule
    return if conversation_automation_choice.nil? || conversation_automation_choice.conversation_automation_rule_id == conversation_automation_rule_id

    errors.add(:conversation_automation_choice, :invalid)
  end
end
