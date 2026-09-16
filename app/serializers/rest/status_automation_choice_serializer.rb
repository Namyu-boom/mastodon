# frozen_string_literal: true

class REST::StatusAutomationChoiceSerializer < ActiveModel::Serializer
  attributes :id, :label, :position, :image_url

  def id
    object.id.to_s
  end

  def label
    object.label.squish
  end
end
