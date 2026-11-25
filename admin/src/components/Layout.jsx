import { useEffect, useState } from 'react';
import { NavLink, Outlet, useLocation } from 'react-router-dom';
import { Building2, ChevronsUpDown, LogOut, Menu } from 'lucide-react';
import { api } from '../api.js';
import { iconFor } from '../icons.js';
import { NAV, R } from '../resources.js';
import { useSession } from '../session.jsx';
import { Wordmark } from './Brand.jsx';

/** Pages a tower admin can't use (community-wide settings and modules). */
const COMMUNITY_ONLY_ROUTES = ['settings'];

const initials = (name) => (name || '?').trim().split(/\s+/).map((p) => p[0]).slice(0, 2).join('').toUpperCase();

export default function Layout() {
  const s = useSession();
  const { community, communities, isTowerAdmin, isPlatformAdmin, summaryVersion } = s;
  const [open, setOpen] = useState(false);
  const [pending, setPending] = useState(0);
  const location = useLocation();

  useEffect(() => setOpen(false), [location]);

  useEffect(() => {
    if (!community) return;
    api.get('/manage/summary/', { community: community.id })
      .then((sum) => setPending(sum.counts.pending_approvals || 0))
      .catch(() => setPending(0));
  }, [community, summaryVersion, location]);

  const visible = (route, key) => {
    const spec = key ? R[key] : null;
    if (spec?.platformOnly) return isPlatformAdmin;
    if (isTowerAdmin && (spec?.communityOnly || COMMUNITY_ONLY_ROUTES.includes(route))) return false;
    return true;
  };

  const userName = s.user?.full_name || s.user?.phone || 'Admin';

  return (
    <div className="layout">
      <nav className={`sidebar${open ? ' open' : ''}`}>
        <div className="sidebar-brand"><Wordmark size={20} onDark /></div>
        {NAV.map(([group, items]) => {
          const shown = items.filter(([route, , key]) => visible(route, key));
          if (!shown.length) return null;
          return (
            <div className="nav-group" key={group || 'main'}>
              {group && <div className="nav-group-title">{group}</div>}
              {shown.map(([route, label, key]) => {
                const Icon = iconFor(key || route);
                return (
                  <NavLink key={route} to={`/${route}`} end={route === 'overview'}
                    className={({ isActive }) => `nav-item${isActive ? ' active' : ''}`}>
                    <Icon size={17} strokeWidth={2} />
                    {label}
                    {key === 'residents' && pending > 0 && <span className="badge">{pending}</span>}
                  </NavLink>
                );
              })}
            </div>
          );
        })}
      </nav>
      {open && <div className="overlay" style={{ zIndex: 25 }} onClick={() => setOpen(false)} />}

      <div className="main">
        <header className="topbar">
          <button className="btn ghost menu-btn" onClick={() => setOpen(true)} aria-label="Menu"><Menu size={20} /></button>
          <div className="community-pill">
            <span className="ic"><Building2 size={17} /></span>
            <div>
              {communities.length > 1 ? (
                <div style={{ position: 'relative', display: 'flex', alignItems: 'center' }}>
                  <select value={community?.id || ''} onChange={(e) => s.selectCommunity(e.target.value)} aria-label="Community"
                    style={{ appearance: 'none', WebkitAppearance: 'none', cursor: 'pointer' }}>
                    {communities.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
                  </select>
                  <ChevronsUpDown size={14} style={{ position: 'absolute', right: 2, pointerEvents: 'none', color: 'var(--muted)' }} />
                </div>
              ) : (
                <b>{community?.name || 'No community yet'}</b>
              )}
              {community && <div className="sub">{[community.city_name, community.currency].filter(Boolean).join(' · ')}</div>}
            </div>
          </div>
          <div className="spacer" />
          <span className="badge primary plain">{s.roleLabel}</span>
          <div className="user-box">
            <div className="meta">
              <div style={{ fontWeight: 650 }}>{userName}</div>
              <div className="small muted">{s.user?.phone}</div>
            </div>
            <span className="avatar" title={userName}>{initials(userName)}</span>
          </div>
          <button className="btn ghost sm" onClick={s.logout} title="Log out"><LogOut size={16} /></button>
        </header>
        <main className="content" key={location.pathname}>
          {community || location.pathname.startsWith('/r/platform') ? <Outlet /> : (
            <div className="card card-pad fade-up">
              <h2>No community yet</h2>
              <p className="muted">
                {isPlatformAdmin ? 'Create your first community under Platform → All communities.' : 'You are not assigned to a community.'}
              </p>
            </div>
          )}
        </main>
      </div>
    </div>
  );
}
