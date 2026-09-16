# frozen_string_literal: true

class ConversationAutomationChoice < ApplicationRecord
  belongs_to :conversation_automation_rule, inverse_of: :choices

  has_many :executions, class_name: 'ConversationAutomationExecution', dependent: :destroy

  normalizes :label, with: ->(label) { label.squish }

  validates :label, presence: true, length: { maximum: 100 }
  validates :response_text, presence: true, length: { maximum: 450 }
  validates :image_url, length: { maximum: 2_000 }, allow_blank: true
  validate :image_url_must_be_https
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  private

  def image_url_must_be_https
    return if image_url.blank?

    uri = Addressable::URI.parse(image_url)
    errors.add(:image_url, :invalid) unless uri.scheme == 'https' && uri.host.present?
  rescue Addressable::URI::InvalidURIError
    errors.add(:image_url, :invalid)
  end
end
