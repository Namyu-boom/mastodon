# frozen_string_literal: true

class REST::ConversationAutomationRuleSerializer < ActiveModel::Serializer
  attributes :id, :name, :prompt, :active, :account_id, :trigger_keyword, :match_in_text

  has_many :choices, serializer: REST::ConversationAutomationChoiceSerializer

  def id
    object.id.to_s
  end

  def account_id
    object.account_id.to_s
  end

  def choices
    AutomationResponseSelector.visible_choices(object.choices)
  end
end
