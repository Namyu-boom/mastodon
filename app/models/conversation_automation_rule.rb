# frozen_string_literal: true

class ConversationAutomationRule < ApplicationRecord
  belongs_to :account

  has_many :choices, -> { order(position: :asc, id: :asc) }, class_name: 'ConversationAutomationChoice', dependent: :destroy, inverse_of: :conversation_automation_rule
  has_many :executions, class_name: 'ConversationAutomationExecution', dependent: :destroy

  accepts_nested_attributes_for :choices, allow_destroy: true

  before_validation :apply_defaults

  validates :name, presence: true, length: { maximum: 100 }
  validates :trigger_keyword, presence: true, length: { maximum: 100 }, format: { without: /[\[\]]/ }
  validates :prompt, presence: true, length: { maximum: 500 }
  validates :default_response_text, length: { maximum: 450 }, allow_blank: true
  validates :default_image_url, length: { maximum: 2_000 }, allow_blank: true
  validate :must_have_response
  validate :default_image_url_must_be_https

  scope :active, -> { where(active: true) }

  private

  def apply_defaults
    self.trigger_keyword = name if trigger_keyword.blank?
    self.prompt = trigger_keyword if prompt.blank?
  end

  def must_have_response
    remaining_choices = choices.reject(&:marked_for_destruction?)
    errors.add(:base, :blank) if remaining_choices.empty? && default_response_text.blank?
    errors.add(:choices, :too_long, count: 10) if remaining_choices.size > 10
  end

  def default_image_url_must_be_https
    return if default_image_url.blank?

    uri = Addressable::URI.parse(default_image_url)
    errors.add(:default_image_url, :invalid) unless uri.scheme == 'https' && uri.host.present?
  rescue Addressable::URI::InvalidURIError
    errors.add(:default_image_url, :invalid)
  end
end
