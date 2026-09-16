# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Conversation Automation Rules' do
  include_context 'with API authentication', oauth_scopes: 'read:statuses write:conversations'

  let!(:user) { Fabricate(:user) }

  describe 'rule management' do
    it 'creates and returns a choice-based rule to its owner' do
      post '/api/v1/conversation_automation_rules', params: {
        name: 'Support menu',
        prompt: 'What do you need?',
        active: true,
        choices_attributes: [
          { label: 'Account help', response_text: 'Here is the account guide.', position: 0 },
          { label: 'Report', response_text: 'Here is the report form.', position: 1 },
        ],
      }, headers: headers

      expect(response).to have_http_status(201)
      expect(response.parsed_body).to include(name: 'Support menu', prompt: 'What do you need?', active: true)
      expect(response.parsed_body[:choices].pluck(:label)).to eq ['Account help', 'Report']
      expect(response.parsed_body[:choices].first[:response_text]).to eq('Here is the account guide.')
    end

    it 'does not expose another account\'s rule' do
      other_rule = Fabricate(:user).account.conversation_automation_rules.create!(
        name: 'Private rule',
        prompt: 'Choose',
        choices_attributes: [{ label: 'One', response_text: 'Secret response' }]
      )

      get "/api/v1/conversation_automation_rules/#{other_rule.id}", headers: headers

      expect(response).to have_http_status(404)
    end
  end
end
