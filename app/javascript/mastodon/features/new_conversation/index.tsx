import { useCallback, useEffect, useState } from 'react';
import type { FormEvent } from 'react';

import { defineMessages, useIntl } from 'react-intl';
import { useHistory } from 'react-router-dom';

import { Helmet } from '@unhead/react/helmet';

import api from 'mastodon/api';
import type { ApiAccountJSON } from 'mastodon/api_types/accounts';
import type { ApiSearchResultsJSON } from 'mastodon/api_types/search';
import { Column } from 'mastodon/components/column';
import { ColumnHeader as LegacyColumnHeader } from 'mastodon/components/column/header';
import { ColumnHeader } from 'mastodon/components/column_header';
import { me } from 'mastodon/initial_state';
import { isRedesignEnabled } from 'mastodon/utils/environment';
import AlternateEmailIcon from '@/material-icons/400-24px/alternate_email.svg?react';

const PARTICIPANTS_LIMIT = 20;

interface ConversationJSON {
  id: string;
}

const messages = defineMessages({
  title: { id: 'conversation.new', defaultMessage: 'New conversation' },
  search: {
    id: 'conversation.search_accounts',
    defaultMessage: 'Search people by name or handle',
  },
  message: {
    id: 'conversation.first_message',
    defaultMessage: 'Write the first message...',
  },
  create: { id: 'conversation.create', defaultMessage: 'Create conversation' },
  remove: { id: 'conversation.remove_participant', defaultMessage: 'Remove' },
  error: {
    id: 'conversation.create_error',
    defaultMessage: 'The conversation could not be created.',
  },
});

const NewConversation: React.FC<{ multiColumn?: boolean }> = ({
  multiColumn,
}) => {
  const intl = useIntl();
  const history = useHistory();
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<ApiAccountJSON[]>([]);
  const [participants, setParticipants] = useState<ApiAccountJSON[]>([]);
  const [message, setMessage] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    const normalizedQuery = query.trim();
    if (normalizedQuery.length < 2) {
      setResults([]);
      return undefined;
    }

    let active = true;
    const timeout = window.setTimeout(() => {
      void api()
        .get<ApiSearchResultsJSON>('/api/v2/search', {
          params: {
            q: normalizedQuery,
            type: 'accounts',
            resolve: true,
            limit: 10,
          },
        })
        .then(({ data }) => {
          if (!active) return;
          const selectedIds = new Set(participants.map(({ id }) => id));
          setResults(
            data.accounts.filter(
              ({ id }) => id !== me && !selectedIds.has(id),
            ),
          );
        })
        .catch(() => {
          if (active) setResults([]);
        });
    }, 250);

    return () => {
      active = false;
      window.clearTimeout(timeout);
    };
  }, [participants, query]);

  const addParticipant = useCallback((account: ApiAccountJSON) => {
    setParticipants((current) =>
      current.length >= PARTICIPANTS_LIMIT ? current : [...current, account],
    );
    setQuery('');
    setResults([]);
  }, []);

  const removeParticipant = useCallback((accountId: string) => {
    setParticipants((current) =>
      current.filter(({ id }) => id !== accountId),
    );
  }, []);

  const handleSubmit = useCallback(
    (event: FormEvent<HTMLFormElement>) => {
      event.preventDefault();
      const status = message.trim();
      if (!status || participants.length === 0 || isSubmitting) return;

      setFailed(false);
      setIsSubmitting(true);
      void api()
        .post<ConversationJSON>('/api/v1/conversations', {
          account_ids: participants.map(({ id }) => id),
          status,
        })
        .then(({ data }) => {
          history.replace(`/conversations/${data.id}`);
        })
        .catch(() => {
          setFailed(true);
        })
        .finally(() => {
          setIsSubmitting(false);
        });
    },
    [history, isSubmitting, message, participants],
  );

  return (
    <Column
      bindToDocument={!multiColumn}
      label={intl.formatMessage(messages.title)}
    >
      {isRedesignEnabled() ? (
        <ColumnHeader
          title={intl.formatMessage(messages.title)}
          withBackButton
        />
      ) : (
        <LegacyColumnHeader
          icon='at'
          iconComponent={AlternateEmailIcon}
          title={intl.formatMessage(messages.title)}
          multiColumn={multiColumn}
        />
      )}

      <form className='new-conversation' onSubmit={handleSubmit}>
        <label>
          <span>{intl.formatMessage(messages.search)}</span>
          <input
            type='search'
            value={query}
            onChange={(event) => setQuery(event.currentTarget.value)}
            placeholder={intl.formatMessage(messages.search)}
            disabled={participants.length >= PARTICIPANTS_LIMIT}
          />
        </label>

        {results.length > 0 && (
          <div className='new-conversation__results'>
            {results.map((account) => (
              <button
                type='button'
                key={account.id}
                onClick={() => addParticipant(account)}
              >
                <img src={account.avatar_static} alt='' />
                <span>
                  <strong>{account.display_name || account.username}</strong>
                  <small>@{account.acct}</small>
                </span>
              </button>
            ))}
          </div>
        )}

        <div className='new-conversation__participants'>
          {participants.map((account) => (
            <span key={account.id}>
              @{account.acct}
              <button
                type='button'
                onClick={() => removeParticipant(account.id)}
                aria-label={intl.formatMessage(messages.remove)}
              >
                ×
              </button>
            </span>
          ))}
        </div>

        <textarea
          value={message}
          onChange={(event) => setMessage(event.currentTarget.value)}
          placeholder={intl.formatMessage(messages.message)}
          rows={5}
        />

        {failed && (
          <p className='new-conversation__error' role='alert'>
            {intl.formatMessage(messages.error)}
          </p>
        )}

        <button
          className='new-conversation__submit'
          type='submit'
          disabled={
            isSubmitting || participants.length === 0 || !message.trim()
          }
        >
          {intl.formatMessage(messages.create)}
        </button>
      </form>

      <Helmet>
        <title>{intl.formatMessage(messages.title)}</title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default NewConversation;
