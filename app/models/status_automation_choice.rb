# frozen_string_literal: true

class StatusAutomationChoice < ApplicationRecord
  belongs_to :status_automation_card, inverse_of: :choices
  has_many :executions, class_name: 'StatusAutomationExecution', dependent: :destroy

  normalizes :label, with: ->(label) { label.squish }

  validates :label, presence: true, length: { maximum: 100 }
  validates :response_text, presence: true, length: { maximum: 450 }
  validates :image_url, length: { maximum: 2_000 }, allow_blank: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :image_url_must_be_https

  private

  def image_url_must_be_https
    return if image_url.blank?

    uri = Addressable::URI.parse(image_url)
    errors.add(:image_url, :invalid) unless uri.scheme == 'https' && uri.host.present?
  rescue Addressable::URI::InvalidURIError
    errors.add(:image_url, :invalid)
  end
end
