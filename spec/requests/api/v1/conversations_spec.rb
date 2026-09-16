# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Conversations' do
  include_context 'with API authentication', oauth_scopes: 'read:statuses'

  let!(:user) { Fabricate(:user, account_attributes: { username: 'alice' }) }

  let(:other) { Fabricate(:user) }

  describe 'GET /api/v1/conversations', :inline_jobs do
    before do
      user.account.follow!(other.account)
      PostStatusService.new.call(other.account, text: 'Hey @alice', visibility: 'direct')
      PostStatusService.new.call(user.account, text: 'Hey, nobody here', visibility: 'direct')
    end

    it 'returns pagination headers', :aggregate_failures do
      get '/api/v1/conversations', params: { limit: 1 }, headers: headers

      expect(response)
        .to have_http_status(200)
        .and include_pagination_headers(
          prev: api_v1_conversations_url(limit: 1, min_id: Status.first.id),
          next: api_v1_conversations_url(limit: 1, max_id: Status.first.id)
        )
      expect(response.content_type)
        .to start_with('application/json')
    end

    it 'returns conversations', :aggregate_failures do
      get '/api/v1/conversations', headers: headers

      expect(response.parsed_body.size).to eq 2
      expect(response.parsed_body.first[:accounts].size).to eq 1
    end

    context 'with since_id' do
      context 'when requesting old posts' do
        it 'returns conversations' do
          get '/api/v1/conversations', params: { since_id: Mastodon::Snowflake.id_at(1.hour.ago, with_random: false) }, headers: headers

          expect(response.parsed_body.size).to eq 2
        end
      end

      context 'when requesting posts in the future' do
        it 'returns no conversation' do
          get '/api/v1/conversations', params: { since_id: Mastodon::Snowflake.id_at(1.hour.from_now, with_random: false) }, headers: headers

          expect(response.parsed_body.size).to eq 0
        end
      end
    end
  end

  describe 'GET /api/v1/conversations/:id', :inline_jobs do
    let!(:first_status) { PostStatusService.new.call(other.account, text: 'Hey @alice', visibility: 'direct') }
    let!(:second_status) { PostStatusService.new.call(user.account, text: 'Hello back', visibility: 'direct', thread: first_status) }
    let(:conversation) { user.account.conversations.find_by!(conversation_id: first_status.conversation_id) }

    it 'returns the messages in the conversation newest first' do
      get "/api/v1/conversations/#{conversation.id}", headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to eq [second_status.id.to_s, first_status.id.to_s]
    end

    it 'supports pagination' do
      get "/api/v1/conversations/#{conversation.id}", params: { limit: 1 }, headers: headers

      expect(response)
        .to have_http_status(200)
        .and include_pagination_headers(
          prev: api_v1_conversation_url(conversation, limit: 1, min_id: second_status.id),
          next: api_v1_conversation_url(conversation, limit: 1, max_id: second_status.id)
        )
      expect(response.parsed_body.pluck(:id)).to eq [second_status.id.to_s]
    end

    it 'does not expose another account\'s conversation' do
      other_conversation = other.account.conversations.find_by!(conversation_id: first_status.conversation_id)

      get "/api/v1/conversations/#{other_conversation.id}", headers: headers

      expect(response).to have_http_status(404)
    end

    it 'does not expose a conversation when the requester is not a participant' do
      carol = Fabricate(:user, account_attributes: { username: 'carol' })
      dave = Fabricate(:user, account_attributes: { username: 'dave' })
      unrelated_status = PostStatusService.new.call(dave.account, text: 'Private for @carol', visibility: 'direct')
      unrelated_conversation = carol.account.conversations.find_by!(conversation_id: unrelated_status.conversation_id)

      get "/api/v1/conversations/#{unrelated_conversation.id}", headers: headers

      expect(response).to have_http_status(404)
    end
  end

  describe 'POST /api/v1/conversations/:id/messages', :inline_jobs do
    let(:scopes) { 'read:statuses write:conversations' }
    let!(:first_status) { PostStatusService.new.call(other.account, text: 'Hey @alice', visibility: 'direct') }
    let(:conversation) { user.account.conversations.find_by!(conversation_id: first_status.conversation_id) }

    it 'sends a direct reply to every participant without handles in the stored text' do
      post "/api/v1/conversations/#{conversation.id}/messages", params: { status: 'Hello everyone' }, headers: headers

      expect(response).to have_http_status(200)

      status = Status.find(response.parsed_body[:id])
      expect(status).to have_attributes(text: 'Hello everyone', visibility: 'direct', conversation_id: first_status.conversation_id)
      expect(status.active_mentions.pluck(:account_id)).to contain_exactly(other.account.id)
    end

    it 'does not allow sending to another account\'s conversation' do
      other_conversation = other.account.conversations.find_by!(conversation_id: first_status.conversation_id)

      post "/api/v1/conversations/#{other_conversation.id}/messages", params: { status: 'Not allowed' }, headers: headers

      expect(response).to have_http_status(404)
    end
  end

  describe 'POST /api/v1/conversations', :inline_jobs do
    let(:scopes) { 'read:statuses write:conversations' }
    let(:third) { Fabricate(:user) }

    it 'creates a group conversation and sends the first message without visible handles' do
      post '/api/v1/conversations', params: { account_ids: [other.account.id, third.account.id], status: 'Hello group' }, headers: headers

      expect(response).to have_http_status(201)
      expect(response.parsed_body[:accounts].pluck(:id)).to contain_exactly(other.account.id.to_s, third.account.id.to_s)

      status = Status.find(response.parsed_body.dig(:last_status, :id))
      expect(status.text).to eq('Hello group')
      expect(status.active_mentions.pluck(:account_id)).to contain_exactly(other.account.id, third.account.id)
    end

    it 'rejects an empty participant list' do
      post '/api/v1/conversations', params: { account_ids: [], status: 'Hello?' }, headers: headers

      expect(response).to have_http_status(422)
    end

    it 'rejects the current account as a participant' do
      post '/api/v1/conversations', params: { account_ids: [user.account.id], status: 'Hello me' }, headers: headers

      expect(response).to have_http_status(422)
    end
  end

  describe 'conversation membership management', :inline_jobs do
    let(:scopes) { 'read:statuses write:conversations' }
    let(:third) { Fabricate(:user) }

    def create_group
      post '/api/v1/conversations', params: { account_ids: [other.account.id], status: 'Hello group' }, headers: headers
      response.parsed_body[:id]
    end

    it 'allows the owner to name the group and add a participant' do
      conversation_id = create_group

      put "/api/v1/conversations/#{conversation_id}", params: { title: 'Project team' }, headers: headers
      expect(response).to have_http_status(200)
      expect(response.parsed_body[:title]).to eq('Project team')

      post "/api/v1/conversations/#{conversation_id}/participants", params: { account_ids: [third.account.id] }, headers: headers
      expect(response).to have_http_status(200)
      expect(response.parsed_body[:accounts].pluck(:id)).to contain_exactly(other.account.id.to_s, third.account.id.to_s)
    end

    it 'allows a member to leave but prevents the owner from leaving' do
      conversation_id = create_group

      delete "/api/v1/conversations/#{conversation_id}/leave", headers: headers
      expect(response).to have_http_status(403)

      owner_conversation = user.account.conversations.find(conversation_id)
      member_conversation = other.account.conversations.find_by!(conversation: owner_conversation.conversation)
      member_token = Fabricate(:accessible_access_token, resource_owner_id: other.id, scopes: scopes)

      delete "/api/v1/conversations/#{member_conversation.id}/leave", headers: { 'Authorization' => "Bearer #{member_token.token}" }
      expect(response).to have_http_status(200)
      expect(member_conversation.conversation.conversation_memberships.find_by(account: other.account)).not_to be_active
    end
  end

  describe 'non-participant access control', :inline_jobs do
    let(:scopes) { 'read:statuses write:conversations' }
    let(:carol) { Fabricate(:user, account_attributes: { username: 'carol' }) }
    let(:dave) { Fabricate(:user, account_attributes: { username: 'dave' }) }
    let!(:unrelated_status) { PostStatusService.new.call(dave.account, text: 'Private for @carol', visibility: 'direct') }
    let(:unrelated_conversation) { carol.account.conversations.find_by!(conversation_id: unrelated_status.conversation_id) }

    it 'rejects every participant-only conversation operation', :aggregate_failures do
      get "/api/v1/conversations/#{unrelated_conversation.id}", headers: headers
      expect(response).to have_http_status(404)

      get "/api/v1/conversations/#{unrelated_conversation.id}/info", headers: headers
      expect(response).to have_http_status(404)

      post "/api/v1/conversations/#{unrelated_conversation.id}/read", headers: headers
      expect(response).to have_http_status(404)

      post "/api/v1/conversations/#{unrelated_conversation.id}/unread", headers: headers
      expect(response).to have_http_status(404)

      post "/api/v1/conversations/#{unrelated_conversation.id}/messages", params: { status: 'Intrusion' }, headers: headers
      expect(response).to have_http_status(404)

      post "/api/v1/conversations/#{unrelated_conversation.id}/participants", params: { account_ids: [user.account.id] }, headers: headers
      expect(response).to have_http_status(404)

      put "/api/v1/conversations/#{unrelated_conversation.id}", params: { title: 'Hijacked' }, headers: headers
      expect(response).to have_http_status(404)

      delete "/api/v1/conversations/#{unrelated_conversation.id}/leave", headers: headers
      expect(response).to have_http_status(404)

      delete "/api/v1/conversations/#{unrelated_conversation.id}", headers: headers
      expect(response).to have_http_status(404)

      expect(unrelated_status.reload).to be_persisted
      expect(unrelated_status.conversation.reload.title).not_to eq('Hijacked')
    end
  end
end
