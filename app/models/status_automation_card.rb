# frozen_string_literal: true

class StatusAutomationCard < ApplicationRecord
  belongs_to :status
  belongs_to :source_rule, class_name: 'ConversationAutomationRule', optional: true

  has_many :choices, -> { order(position: :asc, id: :asc) }, class_name: 'StatusAutomationChoice', dependent: :destroy, inverse_of: :status_automation_card
  has_many :executions, class_name: 'StatusAutomationExecution', dependent: :destroy

  validates :status_id, uniqueness: true
  validates :prompt, presence: true, length: { maximum: 500 }
end
