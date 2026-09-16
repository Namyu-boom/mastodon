# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AutomationResponseSelector do
  describe '.visible_choices' do
    it 'shows one button for normalized duplicate labels' do
      choices = [
        ConversationAutomationChoice.new(label: ' 배송 조회 ', response_text: 'First'),
        ConversationAutomationChoice.new(label: '배송 조회', response_text: 'Second'),
        ConversationAutomationChoice.new(label: '환불', response_text: 'Third'),
      ]

      expect(described_class.visible_choices(choices).map { |choice| choice.label.squish }).to eq ['배송 조회', '환불']
    end
  end

  describe '.random_variant' do
    it 'returns a stable candidate from the selected label group' do
      selected = ConversationAutomationChoice.new(label: 'Guide', response_text: 'First')
      alternative = ConversationAutomationChoice.new(label: ' guide ', response_text: 'Second')
      unrelated = ConversationAutomationChoice.new(label: 'Report', response_text: 'Third')

      first_result = described_class.random_variant([selected, alternative, unrelated], selected_choice: selected, seed: 'same request')
      second_result = described_class.random_variant([selected, alternative, unrelated], selected_choice: selected, seed: 'same request')

      expect(first_result).to be_in([selected, alternative])
      expect(second_result).to equal(first_result)
    end
  end
end
