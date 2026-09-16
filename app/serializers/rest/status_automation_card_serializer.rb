# frozen_string_literal: true

class REST::StatusAutomationCardSerializer < ActiveModel::Serializer
  attributes :id, :prompt, :selected, :selectable

  has_many :choices, serializer: REST::StatusAutomationChoiceSerializer

  def id
    object.id.to_s
  end

  def selected
    return false if current_user.nil?

    object.executions.exists?(selected_by_account_id: current_user.account_id)
  end

  def selectable
    current_user.present? && object.status.account_id != current_user.account_id
  end

  def choices
    AutomationResponseSelector.visible_choices(object.choices)
  end
end
