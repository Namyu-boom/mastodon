import { useCallback, useEffect, useState } from 'react';
import type { FormEvent } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';

import { useHistory, useParams } from 'react-router-dom';

import { List as ImmutableList } from 'immutable';

import { Helmet } from '@unhead/react/helmet';

import { markConversationRead } from 'mastodon/actions/conversations';
import { importFetchedStatuses } from 'mastodon/actions/importer';
import api from 'mastodon/api';
import type { ApiAccountJSON } from 'mastodon/api_types/accounts';
import type { ApiSearchResultsJSON } from 'mastodon/api_types/search';
import type { ApiStatusJSON } from 'mastodon/api_types/statuses';
import { Column } from 'mastodon/components/column';
import { ColumnHeader as LegacyColumnHeader } from 'mastodon/components/column/header';
import { ColumnHeader } from 'mastodon/components/column_header';
import StatusList from 'mastodon/components/status_list';
import { me } from 'mastodon/initial_state';
import { useAppDispatch } from 'mastodon/store';
import { isRedesignEnabled } from 'mastodon/utils/environment';
import AlternateEmailIcon from '@/material-icons/400-24px/alternate_email.svg?react';

const messages = defineMessages({
  title: { id: 'conversation.title', defaultMessage: 'Conversation' },
  empty: {
    id: 'conversation.empty',
    defaultMessage: 'There are no messages in this conversation.',
  },
  loadError: {
    id: 'conversation.load_error',
    defaultMessage: 'This conversation could not be loaded.',
  },
  placeholder: {
    id: 'conversation.message_placeholder',
    defaultMessage: 'Write a message…',
  },
  send: { id: 'conversation.send', defaultMessage: 'Send' },
  sendError: {
    id: 'conversation.send_error',
    defaultMessage: 'The message could not be sent. Please try again.',
  },
  participants: { id: 'conversation.participants', defaultMessage: 'Participants' },
  groupName: { id: 'conversation.group_name', defaultMessage: 'Group name' },
  save: { id: 'conversation.save', defaultMessage: 'Save' },
  addPeople: { id: 'conversation.add_people', defaultMessage: 'Add people' },
  leave: { id: 'conversation.leave', defaultMessage: 'Leave conversation' },
  automaticReply: { id: 'conversation.automatic_reply', defaultMessage: 'Automatic reply options' },
});

interface ConversationInfoJSON {
  id: string;
  title: string | null;
  owner_id: string | null;
  accounts: ApiAccountJSON[];
}

interface AutomationChoiceJSON {
  id: string;
  label: string;
  position: number;
}

interface AutomationRuleJSON {
  id: string;
  prompt: string;
  choices: AutomationChoiceJSON[];
}

const ConversationDetail: React.FC<{ multiColumn?: boolean }> = ({
  multiColumn,
}) => {
  const { id } = useParams<{ id: string }>();
  const dispatch = useAppDispatch();
  const intl = useIntl();
  const history = useHistory();
  const [statusIds, setStatusIds] = useState(ImmutableList<string>());
  const [isLoading, setIsLoading] = useState(true);
  const [loadFailed, setLoadFailed] = useState(false);
  const [message, setMessage] = useState('');
  const [isSending, setIsSending] = useState(false);
  const [sendFailed, setSendFailed] = useState(false);
  const [info, setInfo] = useState<ConversationInfoJSON | null>(null);
  const [title, setTitle] = useState('');
  const [participantQuery, setParticipantQuery] = useState('');
  const [participantResults, setParticipantResults] = useState<ApiAccountJSON[]>([]);
  const [automationRules, setAutomationRules] = useState<AutomationRuleJSON[]>([]);

  const loadConversation = useCallback(() => {
    setIsLoading(true);
    setLoadFailed(false);

    void api()
      .get<ApiStatusJSON[]>(`/api/v1/conversations/${id}`, {
        params: { limit: 40 },
      })
      .then(({ data }) => {
        dispatch(importFetchedStatuses(data));
        // The API is newest-first. Chat messages read naturally oldest-first.
        setStatusIds(ImmutableList(data.map((status) => status.id).reverse()));
        dispatch(markConversationRead(id));
      })
      .catch(() => {
        setLoadFailed(true);
      })
      .finally(() => {
        setIsLoading(false);
      });

    void api()
      .get<ConversationInfoJSON>(`/api/v1/conversations/${id}/info`)
      .then(({ data }) => {
        setInfo(data);
        setTitle(data.title ?? '');
      })
      .catch(() => setLoadFailed(true));

    void api()
      .get<AutomationRuleJSON[]>(`/api/v1/conversations/${id}/automation_choices`)
      .then(({ data }) => setAutomationRules(data))
      .catch(() => setLoadFailed(true));
  }, [dispatch, id]);

  useEffect(() => {
    loadConversation();
  }, [loadConversation]);

  useEffect(() => {
    if (info?.owner_id !== me || participantQuery.trim().length < 2) {
      setParticipantResults([]);
      return undefined;
    }

    let active = true;
    const timeout = window.setTimeout(() => {
      void api()
        .get<ApiSearchResultsJSON>('/api/v2/search', {
          params: {
            q: participantQuery.trim(),
            type: 'accounts',
            resolve: true,
            limit: 8,
          },
        })
        .then(({ data }) => {
          if (!active) return;
          const existingIds = new Set([
            me,
            ...info.accounts.map(({ id }) => id),
          ]);
          setParticipantResults(
            data.accounts.filter(({ id }) => !existingIds.has(id)),
          );
        })
        .catch(() => {
          if (active) setParticipantResults([]);
        });
    }, 250);

    return () => {
      active = false;
      window.clearTimeout(timeout);
    };
  }, [info, participantQuery]);

  const saveTitle = useCallback(() => {
    void api()
      .put<ConversationInfoJSON>(`/api/v1/conversations/${id}`, { title })
      .then(({ data }) => setInfo(data))
      .catch(() => setSendFailed(true));
  }, [id, title]);

  const addParticipant = useCallback(
    (account: ApiAccountJSON) => {
      void api()
        .post<ConversationInfoJSON>(`/api/v1/conversations/${id}/participants`, {
          account_ids: [account.id],
        })
        .then(({ data }) => {
          setInfo(data);
          setParticipantQuery('');
          setParticipantResults([]);
        })
        .catch(() => setSendFailed(true));
    },
    [id],
  );

  const leaveConversation = useCallback(() => {
    void api()
      .delete(`/api/v1/conversations/${id}/leave`)
      .then(() => history.replace('/conversations'))
      .catch(() => setSendFailed(true));
  }, [history, id]);

  const selectAutomationChoice = useCallback(
    (ruleId: string, choiceId: string) => {
      setSendFailed(false);
      void api()
        .post<ApiStatusJSON>(
          `/api/v1/conversations/${id}/automation_choices/${choiceId}`,
        )
        .then(({ data }) => {
          dispatch(importFetchedStatuses([data]));
          setStatusIds((current) => current.push(data.id));
          setAutomationRules((current) =>
            current.filter(({ id: currentRuleId }) => currentRuleId !== ruleId),
          );
        })
        .catch(() => setSendFailed(true));
    },
    [dispatch, id],
  );

  const handleSubmit = useCallback(
    (event: FormEvent<HTMLFormElement>) => {
      event.preventDefault();
      const status = message.trim();
      if (!status || isSending) return;

      setIsSending(true);
      setSendFailed(false);
      void api()
        .post<ApiStatusJSON>(`/api/v1/conversations/${id}/messages`, {
          status,
        })
        .then(() => {
          setMessage('');
          loadConversation();
        })
        .catch(() => {
          setSendFailed(true);
        })
        .finally(() => {
          setIsSending(false);
        });
    },
    [id, isSending, loadConversation, message],
  );

  const emptyMessage = (
    <FormattedMessage {...(loadFailed ? messages.loadError : messages.empty)} />
  );

  return (
    <Column
      bindToDocument={!multiColumn}
      label={intl.formatMessage(messages.title)}
    >
      {isRedesignEnabled() ? (
        <ColumnHeader
          title={info?.title || intl.formatMessage(messages.title)}
          withBackButton
        />
      ) : (
        <LegacyColumnHeader
          icon='at'
          iconComponent={AlternateEmailIcon}
          title={info?.title || intl.formatMessage(messages.title)}
          multiColumn={multiColumn}
        />
      )}

      {info && (
        <details className='conversation-members'>
          <summary>
            {intl.formatMessage(messages.participants)} ({info.accounts.length + 1})
          </summary>
          <div className='conversation-members__body'>
            <div className='conversation-members__accounts'>
              {info.accounts.map((account) => (
                <span key={account.id}>@{account.acct}</span>
              ))}
            </div>

            {info.owner_id === me ? (
              <>
                <label>
                  <span>{intl.formatMessage(messages.groupName)}</span>
                  <div>
                    <input
                      value={title}
                      maxLength={100}
                      onChange={(event) =>
                        setTitle(event.currentTarget.value)
                      }
                    />
                    <button type='button' onClick={saveTitle}>
                      {intl.formatMessage(messages.save)}
                    </button>
                  </div>
                </label>
                <label>
                  <span>{intl.formatMessage(messages.addPeople)}</span>
                  <input
                    value={participantQuery}
                    onChange={(event) =>
                      setParticipantQuery(event.currentTarget.value)
                    }
                  />
                </label>
                {participantResults.map((account) => (
                  <button
                    type='button'
                    key={account.id}
                    onClick={() => addParticipant(account)}
                  >
                    {account.display_name || account.username} (@{account.acct})
                  </button>
                ))}
              </>
            ) : (
              <button
                type='button'
                className='conversation-members__leave'
                onClick={leaveConversation}
              >
                {intl.formatMessage(messages.leave)}
              </button>
            )}
          </div>
        </details>
      )}

      <div className='conversation-thread'>
        <StatusList
          statusIds={statusIds}
          scrollKey={`conversation-${id}`}
          isLoading={isLoading}
          emptyMessage={emptyMessage}
          bindToDocument={!multiColumn}
          timelineId='direct'
          trackScroll
        />
      </div>

      {automationRules.length > 0 && (
        <section className='conversation-automation' aria-label={intl.formatMessage(messages.automaticReply)}>
          {automationRules.map((rule) => (
            <div key={rule.id}>
              <small className='conversation-automation__label'>
                {intl.formatMessage(messages.automaticReply)}
              </small>
              <strong>{rule.prompt}</strong>
              <div>
                {rule.choices.map((choice) => (
                  <button
                    type='button'
                    key={choice.id}
                    onClick={() => selectAutomationChoice(rule.id, choice.id)}
                  >
                    {choice.label}
                  </button>
                ))}
              </div>
            </div>
          ))}
        </section>
      )}

      <form className='conversation-composer' onSubmit={handleSubmit}>
        <div className='conversation-composer__input'>
          <textarea
            value={message}
            onChange={(event) => setMessage(event.currentTarget.value)}
            placeholder={intl.formatMessage(messages.placeholder)}
            rows={2}
            disabled={isSending}
          />
          {sendFailed && (
            <span role='alert'>{intl.formatMessage(messages.sendError)}</span>
          )}
        </div>
        <button type='submit' disabled={isSending || !message.trim()}>
          {intl.formatMessage(messages.send)}
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
export default ConversationDetail;
