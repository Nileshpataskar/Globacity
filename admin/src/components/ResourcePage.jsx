import { useCallback, useEffect, useMemo, useState } from 'react';
import { useParams, useSearchParams } from 'react-router-dom';
import { Building2, Pencil, Plus, RefreshCw, Search, Trash2, X, Zap } from 'lucide-react';
import { api } from '../api.js';
import { iconFor } from '../icons.js';
import { R } from '../resources.js';
import { Badge, Spinner, useSession } from '../session.jsx';
import Form from './Form.jsx';
import QuickAddFlats from './QuickAddFlats.jsx';

const itemUrl = (spec, item, suffix) => {
  const id = item[spec.idKey || 'id'];
  if (suffix && suffix.startsWith('/')) return suffix.replace('{id}', id);
  return `${spec.path}${id}/${suffix || ''}`;
};

export default function ResourcePage() {
  const { key } = useParams();
  const spec = R[key];
  if (!spec) return <div className="empty">Unknown page.</div>;
  return <ResourceList key={key} spec={spec} />;
}

function ResourceList({ spec }) {
  const session = useSession();
  const { community, isTowerAdmin, notify, bumpSummary, reloadCommunities, selectCommunity } = session;
  const [params, setParams] = useSearchParams();
  const filterIdx = Number(params.get('f') || 0);
  const tower = params.get('t') || '';
  const [search, setSearch] = useState('');
  const [query, setQuery] = useState('');
  const [items, setItems] = useState(null);
  const [error, setError] = useState(null);
  const [towers, setTowers] = useState([]);
  const [selected, setSelected] = useState(new Set());
  const [deleting, setDeleting] = useState(false);
  // {mode: 'detail'|'create'|'edit'|'action'|'plan', item, action, startIn, preset}
  const [drawer, setDrawer] = useState(null);
  const Icon = iconFor(spec.key);
  const idOf = (item) => item[spec.idKey || 'id'];

  const updateParam = (k, v) => {
    const next = new URLSearchParams(params);
    v === '' || v === null || v === undefined ? next.delete(k) : next.set(k, v);
    setParams(next, { replace: true });
  };

  useEffect(() => {
    const t = setTimeout(() => setQuery(search.trim()), 350);
    return () => clearTimeout(t);
  }, [search]);

  useEffect(() => {
    if (!spec.towerFilter || !community) return;
    api.listAll('/manage/towers/', { community: community.id }).then(setTowers).catch(() => setTowers([]));
  }, [spec, community]);

  const load = useCallback(async () => {
    setItems(null);
    setError(null);
    setSelected(new Set());
    try {
      const q = {
        ...(spec.filterByCommunity === false || !community ? {} : { community: community.id }),
        ...(spec.filters ? spec.filters[filterIdx]?.[1] : {}),
        ...(tower && spec.towerFilter ? { [spec.towerFilter]: tower } : {}),
        ...(query ? { search: query } : {}),
      };
      setItems(await api.listAll(spec.path, q));
    } catch (e) {
      setError(e.message);
    }
  }, [spec, community, filterIdx, tower, query]);

  useEffect(() => { load(); }, [load]);

  const changed = () => {
    setDrawer(null);
    bumpSummary();
    load();
  };

  const canCreate = spec.canCreate !== false && spec.fields && !(isTowerAdmin && spec.communityOnlyCreate);
  const canEdit = spec.canEdit !== false && spec.fields;
  const canDelete = spec.canDelete !== false;
  const canBulk = canDelete && spec.bulkDelete !== false;
  const selectedTower = towers.find((t) => t.id === tower);

  const allIds = useMemo(() => (items || []).map(idOf), [items]); // eslint-disable-line react-hooks/exhaustive-deps
  const allSelected = allIds.length > 0 && allIds.every((id) => selected.has(id));
  const toggle = (id) => setSelected((s) => {
    const n = new Set(s);
    n.has(id) ? n.delete(id) : n.add(id);
    return n;
  });

  const bulkDelete = async () => {
    const n = selected.size;
    const warn = spec.key === 'towers' ? '\n\nDeleting a tower also deletes all its flats and residents.' : '';
    if (!window.confirm(`Delete ${n} ${n === 1 ? 'item' : 'items'} from ${spec.title}? This cannot be undone.${warn}`)) return;
    setDeleting(true);
    try {
      const res = await api.post(`${spec.path}bulk-delete/`, { ids: [...selected] });
      notify(`Deleted ${res.deleted} ${res.deleted === 1 ? 'item' : 'items'}`);
      bumpSummary();
      load();
    } catch (e) {
      notify(e.message, true);
    } finally {
      setDeleting(false);
    }
  };

  const openPlan = (item, startIn, preset) => setDrawer({ mode: 'plan', item, startIn, preset });

  return (
    <>
      <div className="page-head">
        <span className="page-icon"><Icon size={22} /></span>
        <div className="grow">
          <h1>{spec.title}</h1>
          {spec.empty && <p className="muted" style={{ margin: '2px 0 0' }}>{spec.empty}</p>}
        </div>
        <button className="btn" onClick={load} title="Refresh"><RefreshCw size={15} /> Refresh</button>
        {spec.quickAdd && (
          <>
            <button className="btn" onClick={() => openPlan(selectedTower, 'view')}><Building2 size={15} /> Building plan</button>
            <button className="btn primary" onClick={() => openPlan(selectedTower, 'plan')}><Zap size={15} /> Quick add flats</button>
          </>
        )}
        {canCreate && (
          <button className={`btn ${spec.quickAdd ? '' : 'primary'}`} onClick={() => setDrawer({ mode: 'create' })}>
            <Plus size={16} /> {spec.createLabel || 'Add'}
          </button>
        )}
      </div>

      <div className="toolbar">
        {spec.filters && spec.filters.length > 1 && (
          <div className="chips">
            {spec.filters.map(([label], i) => (
              <button key={label} className={`chip-btn${i === filterIdx ? ' active' : ''}`} onClick={() => updateParam('f', i || '')}>
                {label}
              </button>
            ))}
          </div>
        )}
        {spec.towerFilter && towers.length > 0 && (
          <select value={tower} onChange={(e) => updateParam('t', e.target.value)} aria-label="Tower">
            <option value="">All towers</option>
            {towers.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
          </select>
        )}
        {spec.searchable !== false && (
          <div className="search-box">
            <Search size={16} />
            <input type="search" placeholder={`Search ${spec.title.toLowerCase()}…`} value={search} onChange={(e) => setSearch(e.target.value)} />
          </div>
        )}
      </div>

      {canBulk && selected.size > 0 && (
        <div className="bulk-bar">
          <b>{selected.size} selected</b>
          <span style={{ flex: 1 }} />
          <button className="btn danger sm" disabled={deleting} onClick={bulkDelete}><Trash2 size={14} /> {deleting ? 'Deleting…' : 'Delete selected'}</button>
          <button className="btn ghost sm" style={{ color: '#fff' }} onClick={() => setSelected(new Set())}><X size={14} /> Clear</button>
        </div>
      )}

      <div className="card fade-up">
        {error && <div className="empty"><div className="error-box">{error}</div><button className="btn" onClick={load}>Retry</button></div>}
        {!error && items === null && <Spinner />}
        {!error && items && items.length === 0 && (
          <div className="empty">
            <div className="empty-ic"><Icon size={28} /></div>
            <h3>Nothing here yet</h3>
            {spec.quickAdd && (
              <button className="btn primary" style={{ marginTop: 10 }} onClick={() => openPlan(selectedTower, 'plan')}>
                <Zap size={15} /> Quick add flats
              </button>
            )}
            {!spec.quickAdd && canCreate && (
              <button className="btn primary" style={{ marginTop: 10 }} onClick={() => setDrawer({ mode: 'create' })}>
                <Plus size={15} /> {spec.createLabel || 'Add'}
              </button>
            )}
          </div>
        )}
        {!error && items && items.length > 0 && (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  {canBulk && (
                    <th className="sel">
                      <input type="checkbox" aria-label="Select all" checked={allSelected}
                        onChange={() => setSelected(allSelected ? new Set() : new Set(allIds))} />
                    </th>
                  )}
                  {spec.columns.map((c, i) => <th key={i}>{c.label}</th>)}
                </tr>
              </thead>
              <tbody>
                {items.map((item, idx) => {
                  const id = idOf(item);
                  return (
                    <tr key={id ?? idx} className={selected.has(id) ? 'is-selected' : ''}
                      style={{ animationDelay: `${Math.min(idx, 15) * 18}ms` }}
                      onClick={() => setDrawer({ mode: 'detail', item })}>
                      {canBulk && (
                        <td className="sel" onClick={(e) => e.stopPropagation()}>
                          <input type="checkbox" aria-label="Select" checked={selected.has(id)} onChange={() => toggle(id)} />
                        </td>
                      )}
                      {spec.columns.map((c, i) => (
                        <td key={i}>
                          {c.badge ? <Badge value={c.badge(item)} /> : (
                            <>
                              <div>{c.value(item) || (i === 0 ? '—' : '')}</div>
                              {c.sub && c.sub(item) ? <div className="sub">{c.sub(item)}</div> : null}
                            </>
                          )}
                        </td>
                      ))}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
      {items && items.length > 0 && <p className="count" style={{ marginTop: 10 }}>{items.length} {items.length === 1 ? 'item' : 'items'}</p>}

      {drawer && (
        <Drawer
          title={drawer.mode === 'plan' ? (drawer.item ? `${drawer.item.name} · building plan` : 'Building plan')
            : drawer.mode === 'create' ? (spec.createLabel || `Add ${spec.title.toLowerCase()}`)
              : drawer.mode === 'action' ? drawer.action.label
                : drawer.mode === 'edit' ? `Edit ${spec.titleOf(drawer.item)}` : spec.titleOf(drawer.item)}
          wide={drawer.mode === 'plan'}
          onClose={() => { if (drawer.mode === 'plan') { bumpSummary(); load(); } setDrawer(null); }}
        >
          {drawer.mode === 'plan' && (
            <QuickAddFlats tower={drawer.item} startIn={drawer.startIn} preset={drawer.preset}
              onDone={() => { bumpSummary(); load(); }}
              onCancel={() => { load(); setDrawer(drawer.item && spec.key === 'towers' ? { mode: 'detail', item: drawer.item } : null); }} />
          )}
          {drawer.mode === 'detail' && (
            <Detail spec={spec} item={drawer.item} canEdit={canEdit} canDelete={canDelete}
              onEdit={() => setDrawer({ mode: 'edit', item: drawer.item })}
              onAction={(action) => (action.custom
                ? openPlan(drawer.item, action.custom === 'plan' ? 'view' : 'plan')
                : setDrawer({ mode: 'action', item: drawer.item, action }))}
              onDone={changed} />
          )}
          {(drawer.mode === 'create' || drawer.mode === 'edit') && (
            <Form
              fields={spec.fields.filter((f) => !(drawer.mode === 'edit' && f.createOnly))}
              initial={drawer.mode === 'edit' ? drawer.item : null}
              submitLabel={drawer.mode === 'edit' ? 'Save changes' : (spec.createLabel || 'Create')}
              onCancel={() => setDrawer(drawer.mode === 'edit' ? { mode: 'detail', item: drawer.item } : null)}
              onSubmit={async (values) => {
                if (drawer.mode === 'edit') {
                  await api.patch(itemUrl(spec, drawer.item), values);
                  if (spec.key === 'platform-communities') await reloadCommunities();
                  notify('Saved');
                  changed();
                  return;
                }
                // Fields starting with "_" are form-only extras (e.g. flats per floor for a new tower).
                const extras = Object.fromEntries(Object.entries(values).filter(([k]) => k.startsWith('_')));
                const clean = Object.fromEntries(Object.entries(values).filter(([k]) => !k.startsWith('_')));
                const body = spec.sendCommunity === false || !community ? clean : { community: community.id, ...clean };
                const created = await api.post(spec.path, body);
                if (spec.key === 'towers' && extras._flats_per_floor > 0 && created.floors > 0) {
                  // Show the building plan first; nothing is created until the admin confirms.
                  notify(`${created.name} created. Check the flats below, then create them.`);
                  bumpSummary();
                  load();
                  openPlan(created, 'plan', { from: 1, to: created.floors, perFloor: extras._flats_per_floor, numbering: extras._numbering });
                  return;
                }
                let msg = 'Created';
                if (spec.key === 'platform-communities') {
                  // A new building complex: make it selectable at once and switch to it.
                  await reloadCommunities();
                  selectCommunity(created.id);
                  msg = `${created.name} created. You're now managing it: add its towers and flats next.`;
                }
                notify(msg);
                changed();
              }}
            />
          )}
          {drawer.mode === 'action' && (
            <Form
              fields={drawer.action.fields}
              initial={drawer.item}
              submitLabel={drawer.action.label}
              onCancel={() => setDrawer({ mode: 'detail', item: drawer.item })}
              onSubmit={async (values) => {
                await runAction(spec, drawer.item, drawer.action, values, community);
                notify(drawer.action.success || `${drawer.action.label}: done`);
                changed();
              }}
            />
          )}
        </Drawer>
      )}
    </>
  );
}

async function runAction(spec, item, action, values, community) {
  const body = { ...(action.body ? action.body(item) : {}), ...values };
  if (action.sendCommunity && community) body.community = community.id;
  const url = itemUrl(spec, item, action.path);
  return action.method === 'patch' ? api.patch(url, body) : api.post(url, body);
}

function Detail({ spec, item, canEdit, canDelete, onEdit, onAction, onDone }) {
  const { notify, community } = useSession();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const details = spec.details ? spec.details(item) : spec.columns.filter((c) => c.label && c.value).map((c) => [c.label, c.value(item)]);
  const actions = (spec.actions || []).filter((a) => !a.visible || a.visible(item));

  const run = async (fn, success) => {
    setBusy(true);
    setError(null);
    try {
      await fn();
      notify(success);
      onDone();
    } catch (e) {
      setError(e.message);
      setBusy(false);
    }
  };

  return (
    <>
      {error && <div className="error-box">{error}</div>}
      <dl className="details">
        {details.filter(([, v]) => v !== null && v !== undefined && String(v).trim() !== '').map(([k, v]) => (
          <div key={k} style={{ display: 'contents' }}>
            <dt>{k}</dt>
            <dd>{String(v)}</dd>
          </div>
        ))}
      </dl>
      <div className="actions">
        {actions.map((a) => (
          <button key={a.label} className={`btn ${a.tone || 'primary'}`} disabled={busy}
            onClick={() => {
              if (a.fields || a.custom) return onAction(a);
              if (a.confirm && !window.confirm(a.confirm)) return undefined;
              return run(() => runAction(spec, item, a, {}, community), a.success || `${a.label}: done`);
            }}>
            {a.custom === 'plan' && <Building2 size={15} />}{a.custom === 'quickFlats' && <Zap size={15} />}{a.label}
          </button>
        ))}
        {canEdit && <button className="btn" disabled={busy} onClick={onEdit}><Pencil size={15} /> Edit</button>}
        {canDelete && (
          <button className="btn danger" disabled={busy}
            onClick={() => {
              const warn = spec.key === 'towers' ? '\n\nThis also deletes all its flats and residents.' : '';
              if (window.confirm(`Delete "${spec.titleOf(item)}"? This cannot be undone.${warn}`)) {
                run(() => api.del(itemUrl(spec, item)), 'Deleted');
              }
            }}>
            <Trash2 size={15} /> Delete
          </button>
        )}
      </div>
    </>
  );
}

export function Drawer({ title, subtitle, onClose, children, wide = false }) {
  useEffect(() => {
    const onKey = (e) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);
  return (
    <>
      <div className="overlay" onClick={onClose} />
      <aside className="drawer" role="dialog" aria-label={title} style={wide ? { width: 'min(760px, 100%)' } : undefined}>
        <div className="drawer-head">
          <div className="grow">
            <h2>{title}</h2>
            {subtitle && <div className="muted small">{subtitle}</div>}
          </div>
          <button className="btn ghost" onClick={onClose} aria-label="Close"><X size={18} /></button>
        </div>
        <div className="drawer-body">{children}</div>
      </aside>
    </>
  );
}
