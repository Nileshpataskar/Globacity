import { useCallback, useEffect, useState } from 'react';
import { useParams, useSearchParams } from 'react-router-dom';
import { api } from '../api.js';
import { F, R } from '../resources.js';
import { Badge, Spinner, useSession } from '../session.jsx';
import Form from './Form.jsx';
import QuickAddFlats, { NUMBERING, towerCode } from './QuickAddFlats.jsx';

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
  const [drawer, setDrawer] = useState(null); // {mode: 'detail'|'create'|'edit'|'action', item, action}

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

  return (
    <>
      <div className="page-head">
        <div className="grow">
          <h1>{spec.title}</h1>
          {spec.empty && <p className="muted" style={{ margin: '4px 0 0' }}>{spec.empty}</p>}
        </div>
        <button className="btn" onClick={load}>↻ Refresh</button>
        {spec.quickAdd && <button className="btn primary" onClick={() => setDrawer({ mode: 'quick' })}>⚡ Quick add flats</button>}
        {canCreate && (
          <button className={`btn ${spec.quickAdd ? '' : 'primary'}`} onClick={() => setDrawer({ mode: 'create' })}>
            + {spec.createLabel || 'Add'}
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
          <input type="search" placeholder="Search…" value={search} onChange={(e) => setSearch(e.target.value)} />
        )}
      </div>

      <div className="card">
        {error && <div className="empty"><div className="error-box">{error}</div><button className="btn" onClick={load}>Retry</button></div>}
        {!error && items === null && <Spinner />}
        {!error && items && items.length === 0 && (
          <div className="empty">
            <p>Nothing here yet.</p>
            {spec.quickAdd && <button className="btn primary" onClick={() => setDrawer({ mode: 'quick' })}>⚡ Quick add flats</button>}
          </div>
        )}
        {!error && items && items.length > 0 && (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>{spec.columns.map((c, i) => <th key={i}>{c.label}</th>)}</tr>
              </thead>
              <tbody>
                {items.map((item, idx) => (
                  <tr key={item[spec.idKey || 'id'] ?? idx} onClick={() => setDrawer({ mode: 'detail', item })}>
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
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
      {items && items.length > 0 && <p className="count" style={{ marginTop: 8 }}>{items.length} {items.length === 1 ? 'item' : 'items'}</p>}

      {drawer && (
        <Drawer
          title={drawer.mode === 'quick' ? `Quick add flats${drawer.item ? ` · ${drawer.item.name}` : ''}`
            : drawer.mode === 'create' ? (spec.createLabel || `Add ${spec.title.toLowerCase()}`)
            : drawer.mode === 'action' ? drawer.action.label
              : drawer.mode === 'edit' ? `Edit ${spec.titleOf(drawer.item)}` : spec.titleOf(drawer.item)}
          onClose={() => setDrawer(null)}
        >
          {drawer.mode === 'quick' && (
            <QuickAddFlats tower={drawer.item} onDone={changed} onCancel={() => setDrawer(drawer.item ? { mode: 'detail', item: drawer.item } : null)} />
          )}
          {drawer.mode === 'detail' && (
            <Detail spec={spec} item={drawer.item} canEdit={canEdit} canDelete={canDelete}
              onEdit={() => setDrawer({ mode: 'edit', item: drawer.item })}
              onAction={(action) => setDrawer(action.custom === 'quickFlats'
                ? { mode: 'quick', item: drawer.item } : { mode: 'action', item: drawer.item, action })}
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
                } else {
                  // Fields starting with "_" are form-only extras (e.g. flats per floor for a new tower).
                  const extras = Object.fromEntries(Object.entries(values).filter(([k]) => k.startsWith('_')));
                  const clean = Object.fromEntries(Object.entries(values).filter(([k]) => !k.startsWith('_')));
                  const body = spec.sendCommunity === false || !community ? clean : { community: community.id, ...clean };
                  const created = await api.post(spec.path, body);
                  let msg = 'Created';
                  if (spec.key === 'towers' && extras._flats_per_floor > 0 && created.floors > 0) {
                    const style = NUMBERING.find((n) => n.id === extras._numbering) || NUMBERING[0];
                    const res = await api.post(`/manage/towers/${created.id}/generate-units/`, {
                      floor_from: 1, floor_to: created.floors, units_per_floor: extras._flats_per_floor,
                      number_format: style.format(towerCode(created)),
                    });
                    msg = `${created.name} created with ${res.created} flats`;
                  }
                  if (spec.key === 'platform-communities') {
                    // A new building complex: make it selectable at once and switch to it.
                    await reloadCommunities();
                    selectCommunity(created.id);
                    msg = `${created.name} created. You're now managing it: add its towers and flats next.`;
                  }
                  notify(msg);
                }
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
            {a.label}
          </button>
        ))}
        {canEdit && <button className="btn" disabled={busy} onClick={onEdit}>✎ Edit</button>}
        {canDelete && (
          <button className="btn ghost" style={{ color: 'var(--danger)' }} disabled={busy}
            onClick={() => window.confirm(`Delete "${spec.titleOf(item)}"? This cannot be undone.`)
              && run(() => api.del(itemUrl(spec, item)), 'Deleted')}>
            Delete
          </button>
        )}
      </div>
    </>
  );
}

export function Drawer({ title, subtitle, onClose, children }) {
  useEffect(() => {
    const onKey = (e) => e.key === 'Escape' && onClose();
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);
  return (
    <>
      <div className="overlay" onClick={onClose} />
      <aside className="drawer" role="dialog" aria-label={title}>
        <div className="drawer-head">
          <div className="grow">
            <h2>{title}</h2>
            {subtitle && <div className="muted small">{subtitle}</div>}
          </div>
          <button className="btn ghost" onClick={onClose} aria-label="Close">✕</button>
        </div>
        <div className="drawer-body">{children}</div>
      </aside>
    </>
  );
}

