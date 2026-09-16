# frozen_string_literal: true

class REST::ConversationAutomationRuleManagementSerializer < REST::ConversationAutomationRuleSerializer
  attributes :default_response_text, :default_image_url

  has_many :choices, serializer: REST::ConversationAutomationChoiceManagementSerializer

  def choices
    object.choices
  end
end
