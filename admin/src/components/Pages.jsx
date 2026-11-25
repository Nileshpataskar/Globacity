import { useNavigate } from 'react-router-dom';
import { api } from '../api.js';
import { BULK_BILL_FIELDS, COMMUNITY_SETTINGS_FIELDS } from '../resources.js';
import { useSession } from '../session.jsx';
import Form from './Form.jsx';

export function BulkBill() {
  const { community, notify, bumpSummary } = useSession();
  const navigate = useNavigate();
  return (
    <>
      <div className="page-head"><div className="grow">
        <h1>Bill all flats</h1>
        <p className="muted" style={{ margin: '4px 0 0' }}>
          Creates one bill per flat. Tax (GST / VAT) uses your country&apos;s rate. Residents are notified and can pay in the app.
        </p>
      </div></div>
      <div className="card card-pad" style={{ maxWidth: 640 }}>
        <Form
          fields={BULK_BILL_FIELDS}
          submitLabel="Create bills"
          onSubmit={async (values) => {
            const res = await api.post('/manage/invoices/bulk/', { community: community.id, ...values });
            notify(`Created ${res.created} bills`);
            bumpSummary();
            navigate('/r/invoices');
          }}
        />
      </div>
    </>
  );
}

export function CommunitySettings() {
  const { community, notify, reloadCommunities } = useSession();
  return (
    <>
      <div className="page-head"><div className="grow">
        <h1>Community settings</h1>
        <p className="muted" style={{ margin: '4px 0 0' }}>{community.name}</p>
      </div></div>
      <div className="card card-pad" style={{ maxWidth: 640 }}>
        <Form
          key={community.id}
          fields={COMMUNITY_SETTINGS_FIELDS}
          initial={community}
          submitLabel="Save settings"
          onSubmit={async (values) => {
            const settings = { ...(community.settings || {}), ...(values.settings || {}) };
            await api.patch(`/manage/communities/${community.id}/`, { ...values, settings });
            await reloadCommunities();
            notify('Settings saved');
          }}
        />
      </div>
    </>
  );
}
