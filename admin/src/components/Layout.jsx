import { useEffect, useState } from 'react';
import { NavLink, Outlet, useLocation } from 'react-router-dom';
import { api } from '../api.js';
import { NAV, R } from '../resources.js';
import { useSession } from '../session.jsx';

/** Pages a tower admin can't use (community-wide settings and modules). */
const COMMUNITY_ONLY_ROUTES = ['settings'];

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

  return (
    <div className="layout">
      <nav className={`sidebar${open ? ' open' : ''}`}>
        <div className="brand"><span className="brand-mark">G</span> Globacity Admin</div>
        {NAV.map(([group, items]) => {
          const shown = items.filter(([route, , key]) => visible(route, key));
          if (!shown.length) return null;
          return (
            <div className="nav-group" key={group || 'main'}>
              {group && <div className="nav-group-title">{group}</div>}
              {shown.map(([route, label, key]) => (
                <NavLink key={route} to={`/${route}`} end={route === 'overview'}
                  className={({ isActive }) => `nav-item${isActive ? ' active' : ''}`}>
                  <span aria-hidden>{key ? R[key].icon : route === 'overview' ? '📊' : route === 'settings' ? '⚙️' : '🧾'}</span>
                  {label}
                  {key === 'residents' && pending > 0 && <span className="badge">{pending}</span>}
                </NavLink>
              ))}
            </div>
          );
        })}
      </nav>
      {open && <div className="overlay" style={{ zIndex: 25 }} onClick={() => setOpen(false)} />}

      <div className="main">
        <header className="topbar">
          <button className="btn ghost menu-btn" onClick={() => setOpen(true)} aria-label="Menu">☰</button>
          {communities.length > 1 ? (
            <select style={{ width: 'auto', maxWidth: 280 }} value={community?.id || ''} onChange={(e) => s.selectCommunity(e.target.value)}
              aria-label="Community">
              {communities.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
          ) : (
            <h2>{community?.name || 'No community yet'}</h2>
          )}
          {community && <span className="muted small">{community.city_name}{community.currency ? ` · ${community.currency}` : ''}</span>}
          <div className="spacer" />
          <span className="badge primary">{s.roleLabel}</span>
          <span className="small" title={s.user?.phone}>{s.user?.full_name || s.user?.phone}</span>
          <button className="btn sm" onClick={s.logout}>Log out</button>
        </header>
        <main className="content">
          {community || location.pathname.startsWith('/r/platform') ? <Outlet /> : (
            <div className="card card-pad">
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
