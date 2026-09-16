# frozen_string_literal: true

class StatusAutomationExecution < ApplicationRecord
  belongs_to :status_automation_card
  belongs_to :status_automation_choice
  belongs_to :selected_by_account, class_name: 'Account'
  belongs_to :response_status, class_name: 'Status', optional: true

  validates :selected_by_account_id, uniqueness: { scope: :status_automation_card_id }
  validate :choice_belongs_to_card

  private

  def choice_belongs_to_card
    return if status_automation_choice.nil? || status_automation_choice.status_automation_card_id == status_automation_card_id

    errors.add(:status_automation_choice, :invalid)
  end
end
