import { useCallback, useEffect, useState } from 'react';

import { defineMessages, FormattedMessage, useIntl } from 'react-intl';
import { useParams } from 'react-router-dom';

import { List as ImmutableList } from 'immutable';
import { Helmet } from '@unhead/react/helmet';

import { importFetchedStatuses } from 'mastodon/actions/importer';
import api, { getLinks } from 'mastodon/api';
import type { ApiStatusJSON } from 'mastodon/api_types/statuses';
import { Column } from 'mastodon/components/column';
import { ColumnHeader } from 'mastodon/components/column_header';
import StatusList from 'mastodon/components/status_list';
import { useAppDispatch } from 'mastodon/store';

const messages = defineMessages({
  title: { id: 'messages.admin_conversation', defaultMessage: 'Admin conversation view' },
  empty: { id: 'messages.admin_conversation_empty', defaultMessage: 'No messages found.' },
  error: { id: 'messages.admin_error', defaultMessage: 'The conversation could not be loaded.' },
  notice: {
    id: 'messages.admin_read_only_notice',
    defaultMessage: 'Administrator read-only view. This access is recorded in the audit log.',
  },
  older: { id: 'messages.admin_older', defaultMessage: 'Load older messages' },
});

const AdminConversationDetail: React.FC<{ multiColumn?: boolean }> = ({ multiColumn }) => {
  const { id } = useParams<{ id: string }>();
  const intl = useIntl();
  const dispatch = useAppDispatch();
  const [statusIds, setStatusIds] = useState(ImmutableList<string>());
  const [isLoading, setIsLoading] = useState(true);
  const [failed, setFailed] = useState(false);
  const [next, setNext] = useState<string | null>(null);

  const load = useCallback((url: string, prepend = false) => {
    void api()
      .get<ApiStatusJSON[]>(url)
      .then((response) => {
        dispatch(importFetchedStatuses(response.data));
        const ids = ImmutableList(
          response.data.map(({ id: statusId }) => statusId).reverse(),
        );
        setStatusIds((current) => (prepend ? ids.concat(current) : ids));
        const nextLink = getLinks(response).refs.find(({ rel }) => rel === 'next');
        setNext(nextLink?.uri ?? null);
      })
      .catch(() => setFailed(true))
      .finally(() => setIsLoading(false));
  }, [dispatch]);

  useEffect(() => {
    load(`/api/v1/admin/conversations/${id}`);
  }, [id, load]);

  return (
    <Column bindToDocument={!multiColumn} label={intl.formatMessage(messages.title)}>
      <ColumnHeader title={intl.formatMessage(messages.title)} withBackButton />
      <div className='admin-conversation-notice'>
        {intl.formatMessage(messages.notice)}
      </div>
      {next && (
        <button className='admin-conversation-more' type='button' onClick={() => load(next, true)}>
          {intl.formatMessage(messages.older)}
        </button>
      )}
      <StatusList
        statusIds={statusIds}
        scrollKey={`admin-conversation-${id}`}
        isLoading={isLoading}
        emptyMessage={<FormattedMessage {...(failed ? messages.error : messages.empty)} />}
        bindToDocument={!multiColumn}
        timelineId='direct'
      />
      <Helmet>
        <title>{intl.formatMessage(messages.title)}</title>
        <meta name='robots' content='noindex' />
      </Helmet>
    </Column>
  );
};

// eslint-disable-next-line import/no-default-export
export default AdminConversationDetail;
