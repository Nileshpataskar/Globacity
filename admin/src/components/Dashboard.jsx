import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  AlertTriangle, ArrowRight, Building2, CheckCircle2, DoorOpen, Footprints, LayoutDashboard, Megaphone,
  ReceiptText, ShieldAlert, Siren, Truck, UserCheck, UserCog, Users, Wallet, Wrench,
} from 'lucide-react';
import { api } from '../api.js';
import { F } from '../resources.js';
import { BrandLoader, useSession } from '../session.jsx';

const plural = (n, word) => `${n} ${word}${n === 1 ? '' : 's'}`;

export default function Dashboard() {
  const { community, summaryVersion, isTowerAdmin, user } = useSession();
  const navigate = useNavigate();
  const [data, setData] = useState(null);
  const [error, setError] = useState(null);

  useEffect(() => {
    if (!community) return;
    setError(null);
    api.get('/manage/summary/', { community: community.id }).then(setData).catch((e) => setError(e.message));
  }, [community, summaryVersion]);

  if (error) return <div className="error-box">{error}</div>;
  if (!data) return <BrandLoader />;

  const c = data.counts;
  const m = data.money;
  const cur = data.community.currency;
  const go = (path) => navigate(path);
  const hour = new Date().getHours();
  const greet = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
  const firstName = (user?.full_name || 'Admin').split(' ')[0];

  const alerts = [
    c.active_sos > 0 && ['danger', Siren, plural(c.active_sos, 'active SOS alert'), '/r/sos'],
    c.pending_approvals > 0 && ['warning', UserCheck, `${plural(c.pending_approvals, 'resident')} waiting for approval`, '/r/residents'],
    c.pending_move_requests > 0 && ['warning', Truck, `${plural(c.pending_move_requests, 'move request')} to review`, '/r/move-requests'],
    c.open_incidents > 0 && ['danger', ShieldAlert, plural(c.open_incidents, 'open incident'), '/r/incidents'],
  ].filter(Boolean);

  return (
    <>
      <div className="page-head">
        <span className="page-icon"><LayoutDashboard size={22} /></span>
        <div className="grow">
          <h1>{greet}, {firstName}</h1>
          <p className="muted" style={{ margin: '2px 0 0' }}>
            {isTowerAdmin ? `Your towers in ${data.community.name}` : `Here's what's happening at ${data.community.name}`}
          </p>
        </div>
        <button className="btn" onClick={() => go('/r/residents')}><UserCheck size={16} /> Approvals</button>
        <button className="btn" onClick={() => go('/r/notices')}><Megaphone size={16} /> Post notice</button>
        <button className="btn primary" onClick={() => go('/bulk-bill')}><ReceiptText size={16} /> Bill all flats</button>
      </div>

      <div className="stagger">
        {alerts.map(([tone, Icon, text, path]) => (
          <div key={text} className={`alert ${tone}`} onClick={() => go(path)}>
            <Icon size={18} /> {text}<span className="go">Review <ArrowRight size={15} /></span>
          </div>
        ))}
        {!alerts.length && (
          <div className="alert success"><CheckCircle2 size={18} /> All clear. Nothing needs your attention right now.</div>
        )}
      </div>

      <h2 className="section-title"><Wallet size={17} /> Money this month</h2>
      <div className="grid money stagger">
        <div className="money-hero" onClick={() => go('/r/payments')}>
          <span className="blob b1" />
          <div className="label">Collected this month</div>
          <div className="value">{F.money(m.collected_this_month, cur)}</div>
          <div className="sub">of {F.money(m.invoiced_this_month, cur)} billed</div>
        </div>
        <Stat icon={ReceiptText} label="Billed this month" value={F.money(m.invoiced_this_month, cur)} onClick={() => go('/r/invoices?f=4')} />
        <Stat icon={Wallet} tone="warning" label="Outstanding" value={F.money(m.outstanding, cur)} onClick={() => go('/r/invoices')} />
        <Stat icon={AlertTriangle} tone="danger" label={`Overdue · ${plural(c.defaulter_units, 'flat')}`} value={F.money(m.overdue, cur)}
          onClick={() => go('/r/defaulters')} />
      </div>

      <h2 className="section-title"><Building2 size={17} /> {isTowerAdmin ? 'My towers' : 'Towers'}</h2>
      <div className="grid tower-grid stagger">
        {data.towers.map((t) => <TowerCard key={t.id} t={t} currency={cur} go={go} />)}
        {!data.towers.length && (
          <div className="card empty">
            <div className="empty-ic"><Building2 size={28} /></div>
            <h3>No towers yet</h3>
            <p style={{ margin: '0 0 14px' }}>Add a tower and its flats are created automatically.</p>
            <button className="btn primary" onClick={() => go('/r/towers')}>Add tower</button>
          </div>
        )}
      </div>

      <h2 className="section-title"><Users size={17} /> Community</h2>
      <div className="grid stats stagger">
        <Stat icon={DoorOpen} label="Flats occupied" value={`${c.occupied_units} / ${c.units}`} onClick={() => go('/r/units')} />
        <Stat icon={Users} label="Residents" value={c.residents} onClick={() => go('/r/residents?f=1')} />
        <Stat icon={Wrench} label="Open tickets" value={c.open_tickets} onClick={() => go('/r/tickets')} />
        <Stat icon={Footprints} label="Visitors today" value={c.visitors_today} onClick={() => go('/r/visitor-log')} />
        <Stat icon={Footprints} label="Visitors inside" value={c.inside_now} onClick={() => go('/r/visitor-log?f=1')} />
        {!isTowerAdmin && <Stat icon={UserCog} label="Staff" value={c.staff} onClick={() => go('/r/staff')} />}
      </div>
    </>
  );
}

function Stat({ icon: Icon, label, value, tone, onClick }) {
  const color = tone ? `var(--${tone})` : 'var(--primary)';
  const bg = tone ? `var(--${tone}-soft)` : 'var(--primary-soft)';
  return (
    <div className="card stat" onClick={onClick}>
      <div className="top">
        <span className="label">{label}</span>
        <span className="ic" style={{ color, background: bg }}><Icon size={18} /></span>
      </div>
      <div className="value" style={tone ? { color } : undefined}>{value}</div>
    </div>
  );
}

function TowerCard({ t, currency, go }) {
  const overdue = Number(t.overdue) > 0;
  const pct = t.units ? Math.round((t.occupied_units / t.units) * 100) : 0;
  return (
    <div className="card tower-card">
      <div className="head">
        <span className="tic"><Building2 size={20} /></span>
        <div style={{ flex: 1, minWidth: 0 }}>
          <h2>{t.name}</h2>
          <div className="muted small">{t.admins.length ? `Tower admin: ${t.admins.join(', ')}` : 'Managed by community admin'}</div>
        </div>
        <span className={`badge ${t.approval_mode === 'auto' ? 'info' : ''}`}>{t.approval_mode === 'auto' ? 'Auto-approve' : 'Manual approval'}</span>
      </div>
      <div className="progress" title={`${pct}% occupied`}><div style={{ width: `${pct}%` }} /></div>
      <div className="muted small" style={{ marginTop: 6 }}>{t.occupied_units} of {t.units} flats occupied · {pct}%</div>
      <div className="metrics">
        <div><span className="muted small">Residents</span><b>{t.residents}</b></div>
        <div><span className="muted small">Pending</span><b style={t.pending_approvals ? { color: 'var(--warning)' } : undefined}>{t.pending_approvals}</b></div>
        <div><span className="muted small">Open tickets</span><b>{t.open_tickets}</b></div>
        <div><span className="muted small">Overdue</span><b style={overdue ? { color: 'var(--danger)' } : undefined}>{F.money(t.overdue, currency)}</b></div>
        <div style={{ gridColumn: 'span 2' }}><span className="muted small">Maintenance / flat</span>
          <b>{t.maintenance_amount == null ? 'Not set' : F.money(t.maintenance_amount, currency)}</b></div>
      </div>
      <div className="row">
        {t.pending_approvals > 0 && (
          <button className="btn warning sm" onClick={() => go(`/r/residents?t=${t.id}`)}><UserCheck size={14} /> Review {plural(t.pending_approvals, 'request')}</button>
        )}
        <button className="btn sm" onClick={() => go(`/r/residents?f=1&t=${t.id}`)}>Residents</button>
        <button className="btn sm" onClick={() => go(`/r/invoices?t=${t.id}`)}>Bills</button>
        <button className="btn sm ghost" onClick={() => go('/r/towers')}>Settings</button>
      </div>
    </div>
  );
}
