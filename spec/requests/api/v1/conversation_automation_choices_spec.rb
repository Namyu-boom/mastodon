# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Conversation Automation Choices' do
  include_context 'with API authentication', oauth_scopes: 'read:statuses write:conversations'

  let!(:user) { Fabricate(:user, account_attributes: { username: 'alice' }) }
  let(:owner) { Fabricate(:user, account_attributes: { username: 'support' }) }
  let!(:first_status) { PostStatusService.new.call(owner.account, text: 'Welcome @alice', visibility: 'direct') }
  let(:conversation) { user.account.conversations.find_by!(conversation_id: first_status.conversation_id) }
  let!(:rule) do
    owner.account.conversation_automation_rules.create!(
      name: 'Support menu',
      prompt: 'Choose a topic',
      choices_attributes: [
        { label: 'Account', response_text: 'Account instructions', position: 0 },
        { label: 'Report', response_text: 'Report instructions', position: 1 },
      ]
    )
  end

  describe 'GET /api/v1/conversations/:id/automation_choices', :inline_jobs do
    it 'returns rules owned by another active participant' do
      post "/api/v1/conversations/#{conversation.id}/messages", params: { status: '[Support menu]' }, headers: headers
      get "/api/v1/conversations/#{conversation.id}/automation_choices", headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body.first).to include(id: rule.id.to_s, prompt: 'Choose a topic')
      expect(response.parsed_body.first[:choices].first).not_to have_key(:response_text)
    end

    it 'detects a bracketed keyword inside a longer message only when enabled' do
      rule.update!(trigger_keyword: '배송조회', match_in_text: true)

      post "/api/v1/conversations/#{conversation.id}/messages", params: { status: '안녕하세요 [배송조회] 부탁해요' }, headers: headers
      get "/api/v1/conversations/#{conversation.id}/automation_choices", headers: headers

      expect(response.parsed_body.pluck(:id)).to contain_exactly(rule.id.to_s)

      rule.update!(match_in_text: false)
      get "/api/v1/conversations/#{conversation.id}/automation_choices", headers: headers

      expect(response.parsed_body).to be_empty
    end

    it 'immediately replies when a matching rule has no choices' do
      immediate_rule = owner.account.conversation_automation_rules.create!(
        name: 'Hours',
        trigger_keyword: '운영시간',
        match_in_text: true,
        prompt: 'Operating hours',
        default_response_text: '평일 오전 9시부터 오후 6시까지 운영합니다.'
      )

      post "/api/v1/conversations/#{conversation.id}/messages", params: { status: '안녕하세요 [운영시간] 알려주세요' }, headers: headers

      expect(response).to have_http_status(200)
      execution = ConversationAutomationExecution.find_by!(conversation: first_status.conversation, conversation_automation_rule: immediate_rule, selected_by_account: user.account)
      expect(execution.conversation_automation_choice).to be_nil
      expect(execution.response_status).to have_attributes(account_id: owner.account.id, text: '평일 오전 9시부터 오후 6시까지 운영합니다.', visibility: 'direct')
    end

    it 'chooses only one rule when the same account has duplicate trigger keywords' do
      first_rule = owner.account.conversation_automation_rules.create!(name: 'First hours', trigger_keyword: '시간', default_response_text: 'First response')
      second_rule = owner.account.conversation_automation_rules.create!(name: 'Second hours', trigger_keyword: ' 시간 ', default_response_text: 'Second response')

      post "/api/v1/conversations/#{conversation.id}/messages", params: { status: '[시간]' }, headers: headers

      executions = ConversationAutomationExecution.where(conversation: first_status.conversation, selected_by_account: user.account, conversation_automation_rule: [first_rule, second_rule])
      expect(executions.one?).to be true
      expect(executions.first.response_status.text).to be_in(['First response', 'Second response'])
    end
  end

  describe 'POST /api/v1/conversations/:id/automation_choices/:choice_id', :inline_jobs do
    it 'sends the configured response from the rule owner exactly once' do
      choice = rule.choices.first
      post "/api/v1/conversations/#{conversation.id}/messages", params: { status: '[Support menu]' }, headers: headers

      post "/api/v1/conversations/#{conversation.id}/automation_choices/#{choice.id}", headers: headers

      expect(response).to have_http_status(200)
      response_status = Status.find(response.parsed_body[:id])
      expect(response_status).to have_attributes(account_id: owner.account.id, text: 'Account instructions', visibility: 'direct')
      expect(response_status.active_mentions.pluck(:account_id)).to contain_exactly(user.account.id)
      expect(ConversationAutomationExecution.where(conversation: first_status.conversation, selected_by_account: user.account).count).to eq(1)

      post "/api/v1/conversations/#{conversation.id}/automation_choices/#{choice.id}", headers: headers

      expect(response).to have_http_status(422)
      expect(ConversationAutomationExecution.where(conversation: first_status.conversation, selected_by_account: user.account).count).to eq(1)
    end

    it 'rejects a choice owned by an account outside the conversation' do
      stranger = Fabricate(:user)
      stranger_rule = stranger.account.conversation_automation_rules.create!(
        name: 'Injected',
        prompt: 'Choose',
        choices_attributes: [{ label: 'Run', response_text: 'Injected response' }]
      )
      post "/api/v1/conversations/#{conversation.id}/messages", params: { status: '[Injected]' }, headers: headers

      post "/api/v1/conversations/#{conversation.id}/automation_choices/#{stranger_rule.choices.first.id}", headers: headers

      expect(response).to have_http_status(404)
    end

    it 'shows one button for duplicate labels and selects a response variant on the server' do
      alternative = rule.choices.create!(label: 'Account', response_text: 'Alternative account instructions', position: 2)
      post "/api/v1/conversations/#{conversation.id}/messages", params: { status: '[Support menu]' }, headers: headers
      get "/api/v1/conversations/#{conversation.id}/automation_choices", headers: headers

      expect(response.parsed_body.first[:choices].pluck(:label)).to eq ['Account', 'Report']

      allow(AutomationResponseSelector).to receive(:random_variant).and_return(alternative)
      post "/api/v1/conversations/#{conversation.id}/automation_choices/#{rule.choices.first.id}", headers: headers

      expect(Status.find(response.parsed_body[:id]).text).to eq('Alternative account instructions')
      expect(ConversationAutomationExecution.last.conversation_automation_choice).to eq(alternative)
    end
  end
end
