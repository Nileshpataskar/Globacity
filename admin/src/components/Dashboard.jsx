import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api } from '../api.js';
import { F } from '../resources.js';
import { Spinner, useSession } from '../session.jsx';

const plural = (n, word) => `${n} ${word}${n === 1 ? '' : 's'}`;

export default function Dashboard() {
  const { community, summaryVersion, isTowerAdmin } = useSession();
  const navigate = useNavigate();
  const [data, setData] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    if (!community) return;
    setError(null);
    api.get('/manage/summary/', { community: community.id }).then(setData).catch((e) => setError(e.message));
  }, [community, summaryVersion]);

  if (error) return <div className="error-box">{error}</div>;
  if (!data) return <Spinner />;

  const c = data.counts;
  const m = data.money;
  const cur = data.community.currency;
  const go = (path) => navigate(path);

  const alerts = [
    c.active_sos > 0 && ['danger', `🆘 ${plural(c.active_sos, 'active SOS alert')}`, '/r/sos'],
    c.pending_approvals > 0 && ['warning', `🙋 ${plural(c.pending_approvals, 'resident')} waiting for approval`, '/r/residents'],
    c.pending_move_requests > 0 && ['warning', `🚚 ${plural(c.pending_move_requests, 'move request')} to review`, '/r/move-requests'],
    c.open_incidents > 0 && ['danger', `🚨 ${plural(c.open_incidents, 'open incident')}`, '/r/incidents'],
  ].filter(Boolean);

  return (
    <>
      <div className="page-head">
        <div className="grow">
          <h1>Overview</h1>
          <p className="muted" style={{ margin: '4px 0 0' }}>
            {isTowerAdmin ? `Your towers in ${data.community.name}` : data.community.name}
          </p>
        </div>
        <button className="btn" onClick={() => go('/r/residents')}>Approvals</button>
        <button className="btn" onClick={() => go('/r/notices')}>Post notice</button>
        <button className="btn primary" onClick={() => go('/bulk-bill')}>Bill all flats</button>
      </div>

      {alerts.map(([tone, text, path]) => (
        <div key={text} className={`alert ${tone}`} onClick={() => go(path)}>{text}<span className="go">Review →</span></div>
      ))}
      {!alerts.length && <div className="alert success">✓ All clear. Nothing needs your attention.</div>}

      <h2 className="section-title">Money this month</h2>
      <div className="grid money">
        <Stat label="Collected" value={F.money(m.collected_this_month, cur)} tone="success" onClick={() => go('/r/payments')} />
        <Stat label="Billed" value={F.money(m.invoiced_this_month, cur)} onClick={() => go('/r/invoices?f=4')} />
        <Stat label="Outstanding" value={F.money(m.outstanding, cur)} tone="warning" onClick={() => go('/r/invoices')} />
        <Stat label={`Overdue · ${plural(c.defaulter_units, 'flat')}`} value={F.money(m.overdue, cur)} tone="danger" onClick={() => go('/r/defaulters')} />
      </div>

      <h2 className="section-title">{isTowerAdmin ? 'My towers' : 'Towers'}</h2>
      <div className="grid tower-grid">
        {data.towers.map((t) => <TowerCard key={t.id} t={t} currency={cur} go={go} />)}
        {!data.towers.length && <div className="card card-pad muted">No towers yet. Add one under Property → Towers.</div>}
      </div>

      <h2 className="section-title">Community</h2>
      <div className="grid stats">
        <Stat label="Flats occupied" value={`${c.occupied_units} / ${c.units}`} onClick={() => go('/r/units')} />
        <Stat label="Residents" value={c.residents} onClick={() => go('/r/residents?f=1')} />
        <Stat label="Open tickets" value={c.open_tickets} onClick={() => go('/r/tickets')} />
        <Stat label="Visitors today" value={c.visitors_today} onClick={() => go('/r/visitor-log')} />
        <Stat label="Visitors inside" value={c.inside_now} onClick={() => go('/r/visitor-log?f=1')} />
        {!isTowerAdmin && <Stat label="Staff" value={c.staff} onClick={() => go('/r/staff')} />}
      </div>
    </>
  );
}

function Stat({ label, value, tone, onClick }) {
  return (
    <div className="card stat" onClick={onClick}>
      <div className="label">{label}</div>
      <div className="value" style={tone ? { color: `var(--${tone})` } : undefined}>{value}</div>
    </div>
  );
}

function TowerCard({ t, currency, go }) {
  const overdue = Number(t.overdue) > 0;
  return (
    <div className="card tower-card">
      <div className="row" style={{ justifyContent: 'space-between' }}>
        <div>
          <h2>🏢 {t.name}</h2>
          <div className="muted small">{t.admins.length ? `Tower admin: ${t.admins.join(', ')}` : 'Managed by community admin'}</div>
        </div>
        <span className={`badge ${t.approval_mode === 'auto' ? 'info' : ''}`}>{t.approval_mode === 'auto' ? 'Auto-approve' : 'Manual approval'}</span>
      </div>
      <div className="metrics">
        <div><span className="muted small">Occupied</span><b>{t.occupied_units}/{t.units}</b></div>
        <div><span className="muted small">Residents</span><b>{t.residents}</b></div>
        <div><span className="muted small">Pending</span><b style={t.pending_approvals ? { color: 'var(--warning)' } : undefined}>{t.pending_approvals}</b></div>
        <div><span className="muted small">Open tickets</span><b>{t.open_tickets}</b></div>
        <div><span className="muted small">Overdue</span><b style={overdue ? { color: 'var(--danger)' } : undefined}>{F.money(t.overdue, currency)}</b></div>
        <div><span className="muted small">Maintenance</span><b>{t.maintenance_amount == null ? 'Not set' : F.money(t.maintenance_amount, currency)}</b></div>
      </div>
      <div className="row">
        {t.pending_approvals > 0 && (
          <button className="btn warning sm" onClick={() => go(`/r/residents?t=${t.id}`)}>Review {plural(t.pending_approvals, 'request')}</button>
        )}
        <button className="btn sm" onClick={() => go(`/r/residents?f=1&t=${t.id}`)}>Residents</button>
        <button className="btn sm" onClick={() => go(`/r/invoices?t=${t.id}`)}>Bills</button>
        <button className="btn sm ghost" onClick={() => go('/r/towers')}>Settings</button>
      </div>
    </div>
  );
}
