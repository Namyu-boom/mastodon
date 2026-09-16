import { useCallback, useEffect, useState } from 'react';

import { defineMessages, useIntl } from 'react-intl';
import { useHistory } from 'react-router-dom';

import { Helmet } from '@unhead/react/helmet';

import api, { getLinks } from 'mastodon/api';
import type { ApiAccountJSON } from 'mastodon/api_types/accounts';
import type { ApiStatusJSON } from 'mastodon/api_types/statuses';
import { Column } from 'mastodon/components/column';
import { ColumnHeader } from 'mastodon/components/column_header';

interface AdminConversationJSON {
  id: string;
  title: string | null;
  accounts: ApiAccountJSON[];
  last_status: ApiStatusJSON | null;
}

const messages = defineMessages({
  title: { id: 'messages.admin_all', defaultMessage: 'All conversations' },
  empty: { id: 'messages.admin_empty', defaultMessage: 'No conversations found.' },
  error: { id: 'messages.admin_error', defaultMessage: 'Conversations could not be loaded.' },
  more: { id: 'messages.admin_more', defaultMessage: 'Load more' },
});

const AdminConversations: React.FC<{ multiColumn?: boolean }> = ({ multiColumn }) => {
  const intl = useIntl();
  const history = useHistory();
  const [conversations, setConversations] = useState<AdminConversationJSON[]>([]);
  const [failed, setFailed] = useState(false);
  const [next, setNext] = useState<string | null>(null);

  const load = useCallback((url: string, append = false) => {
    void api()
      .get<AdminConversationJSON[]>(url)
      .then((response) => {
        setConversations((current) =>
          append ? [...current, ...response.data] : response.data,
        );
        const nextLink = getLinks(response).refs.find(({ rel }) => rel === 'next');
        setNext(nextLink?.uri ?? null);
      })
      .catch(() => setFailed(true));
  }, []);

  useEffect(() => {
    load('/api/v1/admin/conversations');
  }, [load]);

  return (
    <Column bindToDocument={!multiColumn} label={intl.formatMessage(messages.title)}>
      <ColumnHeader title={intl.formatMessage(messages.title)} withBackButton />
      <div className='admin-conversations'>
        {failed && <p role='alert'>{intl.formatMessage(messages.error)}</p>}
        {!failed && conversations.length === 0 && <p>{intl.formatMessage(messages.empty)}</p>}
        {conversations.map((conversation) => (
          <button
            type='button'
            key={conversation.id}
            onClick={() => history.push(`/conversations/admin/${conversation.id}`)}
          >
            <strong>
              {conversation.title || conversation.accounts.map(({ acct }) => `@${acct}`).join(', ')}
            </strong>
            {conversation.last_status && (
              <span>{new Date(conversation.last_status.created_at).toLocaleString()}</span>
            )}
          </button>
        ))}
        {next && (
          <button type='button' onClick={() => load(next, true)}>
            <strong>{intl.formatMessage(messages.more)}</strong>
          </button>
        )}
      </div>
      <Helmet>
        <title>{intl.formatMessage(messages.title)}</title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default AdminConversations;
