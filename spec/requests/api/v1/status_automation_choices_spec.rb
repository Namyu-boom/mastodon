# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Status Automation Choices' do
  include_context 'with API authentication', oauth_scopes: 'read:statuses write:statuses'

  let!(:user) { Fabricate(:user, account_attributes: { username: 'customer' }) }
  let(:owner) { Fabricate(:user, account_attributes: { username: 'support' }) }
  let(:rule) do
    owner.account.conversation_automation_rules.create!(
      name: 'Support menu',
      prompt: 'Choose a topic',
      choices_attributes: [
        { label: 'Account', response_text: 'Account instructions', image_url: 'https://example.com/account.png', position: 0 },
        { label: 'Report', response_text: 'Report instructions', position: 1 },
      ]
    )
  end
  let(:status) { PostStatusService.new.call(owner.account, text: 'How can we help?', visibility: 'public', automation_rule: rule) }

  describe 'POST /api/v1/statuses/:status_id/automation_choices/:choice_id' do
    it 'sends the snapshotted response as a one-to-one DM exactly once' do
      choice = status.status_automation_card.choices.first

      post "/api/v1/statuses/#{status.id}/automation_choices/#{choice.id}", headers: headers

      expect(response).to have_http_status(200)
      response_status = Status.find(response.parsed_body[:id])
      expect(response_status).to have_attributes(account_id: owner.account.id, text: "Account instructions\n\nhttps://example.com/account.png", visibility: 'direct')
      expect(response_status.active_mentions.pluck(:account_id)).to contain_exactly(user.account.id)
      expect(response_status.conversation.conversation_memberships.pluck(:account_id)).to contain_exactly(owner.account.id, user.account.id)

      post "/api/v1/statuses/#{status.id}/automation_choices/#{choice.id}", headers: headers

      expect(response).to have_http_status(422)
      expect(status.status_automation_card.executions.where(selected_by_account: user.account).count).to eq(1)
    end

    it 'rejects a choice from a different card' do
      other_status = PostStatusService.new.call(owner.account, text: 'Another menu', visibility: 'public', automation_rule: rule)

      post "/api/v1/statuses/#{status.id}/automation_choices/#{other_status.status_automation_card.choices.first.id}", headers: headers

      expect(response).to have_http_status(404)
      expect(StatusAutomationExecution.count).to eq(0)
    end

    it 'does not allow the post author to trigger their own automatic response' do
      owner_token = Fabricate(:accessible_access_token, resource_owner_id: owner.id, scopes: 'write:statuses')

      post "/api/v1/statuses/#{status.id}/automation_choices/#{status.status_automation_card.choices.first.id}", headers: { 'Authorization' => "Bearer #{owner_token.token}" }

      expect(response).to have_http_status(403)
      expect(StatusAutomationExecution.count).to eq(0)
    end

    it 'does not allow an account that cannot view the source status' do
      private_status = PostStatusService.new.call(owner.account, text: 'Followers only', visibility: 'private', automation_rule: rule)

      post "/api/v1/statuses/#{private_status.id}/automation_choices/#{private_status.status_automation_card.choices.first.id}", headers: headers

      expect(response).to have_http_status(404)
      expect(StatusAutomationExecution.count).to eq(0)
    end
  end
end
