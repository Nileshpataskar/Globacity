import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import { api, setOnSessionExpired, tokens } from './api.js';
import { F } from './resources.js';

const SessionContext = createContext(null);
export const useSession = () => useContext(SessionContext);

const MANAGER_ROLES = ['admin', 'manager'];

/** Who is signed in, what they manage, and which community is selected. */
export function SessionProvider({ children }) {
  const [state, setState] = useState({ loading: true, user: null, roles: null, communities: [], error: null });
  const [communityId, setCommunityId] = useState(() => {
    try { return localStorage.getItem('ga_community'); } catch { return null; }
  });
  const [summaryVersion, setSummaryVersion] = useState(0);
  const [toast, setToast] = useState(null);

  const notify = useCallback((message, error = false) => {
    setToast({ message, error, id: Date.now() });
  }, []);

  useEffect(() => {
    if (!toast) return undefined;
    const t = setTimeout(() => setToast(null), 3500);
    return () => clearTimeout(t);
  }, [toast]);

  const load = useCallback(async () => {
    if (!tokens.access) {
      setState({ loading: false, user: null, roles: null, communities: [], error: null });
      return;
    }
    setState((s) => ({ ...s, loading: true, error: null }));
    try {
      const [user, roles] = await Promise.all([api.get('/me/'), api.get('/me/roles/')]);
      const isManager = roles.is_platform_admin || roles.roles.some((r) => MANAGER_ROLES.includes(r.role));
      if (!isManager) {
        tokens.clear();
        setState({ loading: false, user: null, roles: null, communities: [],
          error: 'This account is not a community admin or manager. Residents and guards use the mobile app.' });
        return;
      }
      const communities = await api.listAll('/manage/communities/');
      setState({ loading: false, user, roles, communities, error: null });
    } catch (e) {
      if (!tokens.access) {
        setState({ loading: false, user: null, roles: null, communities: [], error: null });
      } else {
        setState((s) => ({ ...s, loading: false, error: e.message }));
      }
    }
  }, []);

  useEffect(() => {
    setOnSessionExpired(() => setState({ loading: false, user: null, roles: null, communities: [], error: 'Session expired. Please log in again.' }));
    load();
  }, [load]);

  const community = useMemo(() => {
    const list = state.communities;
    return list.find((c) => c.id === communityId) || list[0] || null;
  }, [state.communities, communityId]);

  useEffect(() => {
    if (community?.currency) F.currency = community.currency;
  }, [community]);

  /** Tower names when this person manages only some towers (tower admin); empty otherwise. */
  const myTowers = useMemo(() => {
    const r = state.roles;
    if (!r || r.is_platform_admin) return [];
    const managerRoles = r.roles.filter((x) => MANAGER_ROLES.includes(x.role));
    if (!managerRoles.length || managerRoles.some((x) => !(x.towers || []).length)) return [];
    return managerRoles.flatMap((x) => x.towers.map((t) => t.name));
  }, [state.roles]);

  const value = {
    ...state,
    community,
    isPlatformAdmin: !!state.roles?.is_platform_admin,
    myTowers,
    isTowerAdmin: myTowers.length > 0,
    roleLabel: state.roles?.is_platform_admin
      ? 'Platform admin'
      : myTowers.length
        ? `Tower admin · ${myTowers.join(', ')}`
        : state.roles?.roles.some((r) => r.role === 'admin') ? 'Community admin' : 'Manager',
    selectCommunity: (id) => {
      setCommunityId(id);
      try { localStorage.setItem('ga_community', id); } catch { /* ignore */ }
    },
    reloadCommunities: async () => {
      const communities = await api.listAll('/manage/communities/');
      setState((s) => ({ ...s, communities }));
    },
    summaryVersion,
    bumpSummary: () => setSummaryVersion((v) => v + 1),
    notify,
    reload: load,
    logout: async () => {
      try { if (tokens.refresh) await api.post('/auth/logout/', { refresh: tokens.refresh }); } catch { /* ignore */ }
      tokens.clear();
      setState({ loading: false, user: null, roles: null, communities: [], error: null });
    },
  };

  return (
    <SessionContext.Provider value={value}>
      {children}
      {toast && <div key={toast.id} className={`toast${toast.error ? ' error' : ''}`} role="status">{toast.message}</div>}
    </SessionContext.Provider>
  );
}

export function Badge({ value }) {
  if (!value) return null;
  const [label, tone] = value;
  if (!label) return null;
  return <span className={`badge ${tone || ''}`}>{label}</span>;
}

export function Spinner() {
  return <div className="spinner" aria-label="Loading" />;
}
