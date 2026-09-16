# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'API V1 Admin Conversations' do
  include_context 'with API authentication', user_fabricator: :admin_user, oauth_scopes: 'read:statuses'

  let(:alice) { Fabricate(:user, account_attributes: { username: 'alice' }) }
  let(:bob) { Fabricate(:user, account_attributes: { username: 'bob' }) }
  let(:carol) { Fabricate(:user, account_attributes: { username: 'carol' }) }
  let(:dave) { Fabricate(:user, account_attributes: { username: 'dave' }) }
  let!(:alice_message) { PostStatusService.new.call(bob.account, text: 'Private for @alice', visibility: 'direct') }
  let!(:carol_message) { PostStatusService.new.call(dave.account, text: 'Private for @carol', visibility: 'direct') }

  describe 'GET /api/v1/admin/conversations', :inline_jobs do
    it 'shows every direct conversation without adding the administrator as a participant' do
      get '/api/v1/admin/conversations', headers: headers

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to contain_exactly(alice_message.conversation_id.to_s, carol_message.conversation_id.to_s)
      expect(alice_message.active_mentions.pluck(:account_id)).not_to include(user.account.id)
      expect(alice_message.conversation.conversation_memberships.where(account: user.account)).not_to exist
    end

    it 'records access in the administrator audit log' do
      expect do
        get '/api/v1/admin/conversations', headers: headers
      end.to change { Admin::ActionLog.where(account: user.account, action: 'view_direct_messages').count }.by(1)
    end
  end

  describe 'GET /api/v1/admin/conversations/:id', :inline_jobs do
    it 'returns messages even when the administrator is not a participant and records the access' do
      expect do
        get "/api/v1/admin/conversations/#{alice_message.conversation_id}", headers: headers
      end.to change { Admin::ActionLog.where(account: user.account, action: 'view_direct_message', target: alice_message.conversation).count }.by(1)

      expect(response).to have_http_status(200)
      expect(response.parsed_body.pluck(:id)).to eq [alice_message.id.to_s]
    end

    it 'does not grant the administrator access through participant mutation APIs' do
      participant_conversation = alice.account.conversations.find_by!(conversation_id: alice_message.conversation_id)

      post "/api/v1/conversations/#{participant_conversation.id}/messages", params: { status: 'Admin injection' }, headers: headers

      expect(response).to have_http_status(404)
      expect(alice_message.conversation.statuses.where(account: user.account)).not_to exist
    end
  end

  context 'when the requester is not an administrator' do
    let(:user) { Fabricate(:user) }

    it 'rejects access' do
      get '/api/v1/admin/conversations', headers: headers

      expect(response).to have_http_status(403)
    end
  end
end
