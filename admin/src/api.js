/* REST client for the Django API: JWT auth with refresh, error messages, paged list helper. */

export const API_BASE =
  import.meta.env.VITE_API_URL || `${window.location.protocol}//${window.location.hostname}:8000/api/v1`;

const store = {
  get(k) {
    try { return localStorage.getItem(k); } catch { return null; }
  },
  set(k, v) {
    try { v == null ? localStorage.removeItem(k) : localStorage.setItem(k, v); } catch { /* storage unavailable */ }
  },
};

export const tokens = {
  access: store.get('ga_access'),
  refresh: store.get('ga_refresh'),
  save(access, refresh) {
    this.access = access;
    store.set('ga_access', access);
    if (refresh) {
      this.refresh = refresh;
      store.set('ga_refresh', refresh);
    }
  },
  clear() {
    this.access = this.refresh = null;
    store.set('ga_access', null);
    store.set('ga_refresh', null);
  },
};

export class ApiError extends Error {
  constructor(message, status) {
    super(message);
    this.status = status;
  }
}

function pickMessage(data) {
  if (data == null) return null;
  if (typeof data === 'string') return data;
  if (Array.isArray(data)) return data.length ? pickMessage(data[0]) : null;
  if (typeof data === 'object') {
    if (data.detail) return pickMessage(data.detail);
    for (const [k, v] of Object.entries(data)) {
      const m = pickMessage(v);
      if (m) return k === 'non_field_errors' ? m : `${k.replace(/_/g, ' ')}: ${m}`;
    }
  }
  return null;
}

let refreshing = null;
let onExpired = () => {};
export const setOnSessionExpired = (fn) => { onExpired = fn; };

async function refreshToken() {
  const res = await fetch(`${API_BASE}/auth/token/refresh/`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ refresh: tokens.refresh }),
  });
  if (!res.ok) {
    const err = new ApiError('Session expired. Please log in again.', res.status);
    if (res.status === 400 || res.status === 401) {
      tokens.clear();
      onExpired();
    }
    throw err;
  }
  const data = await res.json();
  tokens.save(data.access, data.refresh);
}

export async function request(method, path, body, { auth = true, query } = {}) {
  const url = new URL(API_BASE + path);
  for (const [k, v] of Object.entries(query || {})) {
    if (v !== undefined && v !== null && v !== '') url.searchParams.set(k, v);
  }
  const send = () => fetch(url, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(auth && tokens.access ? { Authorization: `Bearer ${tokens.access}` } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  let res;
  try {
    res = await send();
    if (res.status === 401 && auth && tokens.refresh) {
      await (refreshing ??= refreshToken().finally(() => { refreshing = null; }));
      res = await send();
    }
  } catch (e) {
    if (e instanceof ApiError) throw e;
    throw new ApiError(`Cannot reach the server at ${API_BASE}. Is the backend running?`, 0);
  }
  if (res.status === 204) return null;
  const text = await res.text();
  let data = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = text; }
  if (!res.ok) throw new ApiError(pickMessage(data) || `Request failed (${res.status})`, res.status);
  return data;
}

export const api = {
  get: (path, query) => request('GET', path, undefined, { query }),
  post: (path, body = {}, opts) => request('POST', path, body, opts),
  patch: (path, body) => request('PATCH', path, body),
  del: (path) => request('DELETE', path),
  /** Every page of a list endpoint (the API returns at most 100 per page). */
  async listAll(path, query = {}) {
    const out = [];
    for (let page = 1; page < 50; page++) {
      const data = await request('GET', path, undefined, { query: { page_size: 100, page, ...query } });
      if (Array.isArray(data)) return data;
      out.push(...data.results);
      if (!data.next) break;
    }
    return out;
  },
};
