import { useEffect, useMemo, useState } from 'react';
import { api } from '../api.js';
import { F } from '../resources.js';
import { useSession } from '../session.jsx';

const read = (obj, key) => key.split('.').reduce((v, k) => (v && typeof v === 'object' ? v[k] : undefined), obj);

function write(body, key, value) {
  const parts = key.split('.');
  let m = body;
  for (const p of parts.slice(0, -1)) m = m[p] ??= {};
  m[parts.at(-1)] = value;
}

const pad = (n) => String(n).padStart(2, '0');
const toLocalInput = (iso) => {
  if (!iso) return '';
  const d = new Date(iso);
  if (isNaN(d)) return '';
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
};

function initialValue(field, initial) {
  let v = initial ? read(initial, field.key) : undefined;
  if (v === undefined || v === null) v = field.initialFrom && initial ? initial[field.initialFrom] : field.initial;
  switch (field.type) {
    case 'boolean': return !!v;
    case 'refMulti': return (v || []).map(String);
    case 'lines': return (v || []).map((e) => (typeof e === 'object' ? e.label : e)).join('\n');
    case 'datetime': return toLocalInput(v);
    case 'date': return v ? String(v).slice(0, 10) : '';
    default: return v === undefined || v === null ? '' : String(v);
  }
}

/** Loads options for ref / refMulti fields from the API (scoped to the selected community). */
function useRefOptions(fields, communityId) {
  const [options, setOptions] = useState({});
  useEffect(() => {
    let alive = true;
    for (const f of fields) {
      if (f.type !== 'ref' && f.type !== 'refMulti') continue;
      const query = f.refCommunity === false || !communityId ? {} : { community: communityId };
      api.listAll(f.ref, query)
        .then((list) => alive && setOptions((o) => ({ ...o, [f.key]: list })))
        .catch((e) => alive && setOptions((o) => ({ ...o, [f.key]: e })));
    }
    return () => { alive = false; };
  }, [fields, communityId]);
  return options;
}

/**
 * Generic form. `onSubmit(values)` returns a promise; errors from the API are shown above the fields.
 * Empty optional values are left out; when editing, a blank is sent only if a field was cleared.
 */
export default function Form({ fields, initial, submitLabel = 'Save', onSubmit, onCancel, intro }) {
  const { community } = useSession();
  const [values, setValues] = useState(() => Object.fromEntries(fields.map((f) => [f.key, initialValue(f, initial)])));
  const [error, setError] = useState(null);
  const [saving, setSaving] = useState(false);
  const refFields = useMemo(() => fields.filter((f) => f.type === 'ref' || f.type === 'refMulti'), [fields]);
  const options = useRefOptions(refFields, community?.id);
  const set = (key, v) => setValues((s) => ({ ...s, [key]: v }));

  const collect = () => {
    const body = {};
    for (const f of fields) {
      let v = values[f.key];
      switch (f.type) {
        case 'integer': v = v === '' ? null : parseInt(v, 10); break;
        case 'decimal': v = v === '' ? null : String(v).trim(); break;
        case 'lines': v = v.split('\n').map((x) => x.trim()).filter(Boolean); break;
        case 'datetime': v = v ? new Date(v).toISOString() : null; break;
        case 'date': v = v || null; break;
        case 'ref': case 'choice': v = v || null; break;
        case 'boolean': case 'refMulti': break;
        default: v = String(v).trim();
      }
      if (v === null || v === undefined || Number.isNaN(v)) continue;
      if (v === '') {
        const before = initial ? read(initial, f.key) : null;
        if (before === null || before === undefined || before === '') continue;
      }
      write(body, f.key, v);
    }
    return body;
  };

  const submit = async (e) => {
    e.preventDefault();
    for (const f of fields) {
      const v = values[f.key];
      if (f.required && (v === '' || v === null || (Array.isArray(v) && !v.length) || (f.type === 'lines' && !v.trim()))) {
        setError(`${f.label} is required`);
        return;
      }
    }
    setError(null);
    setSaving(true);
    try {
      await onSubmit(collect());
    } catch (err) {
      setError(err.message);
      setSaving(false);
    }
  };

  const renderField = (f) => {
    const label = `${f.label}${f.required ? ' *' : ''}`;
    const v = values[f.key];
    const hint = f.hint && <small className="hint">{f.hint}</small>;
    switch (f.type) {
      case 'boolean':
        return (
          <label className="check" key={f.key}>
            <input type="checkbox" checked={v} onChange={(e) => set(f.key, e.target.checked)} />
            <span>{f.label}{hint}</span>
          </label>
        );
      case 'multiline': case 'lines':
        return (
          <label className="field" key={f.key}>
            <span>{label}</span>
            <textarea value={v} onChange={(e) => set(f.key, e.target.value)} />
            {hint}
          </label>
        );
      case 'choice':
        return (
          <label className="field" key={f.key}>
            <span>{label}</span>
            <select value={v} onChange={(e) => set(f.key, e.target.value)}>
              {!f.required && <option value="">— Select —</option>}
              {f.choices.map((c) => <option key={c} value={c}>{f.labels?.[c] || F.human(c)}</option>)}
            </select>
            {hint}
          </label>
        );
      case 'ref': case 'refMulti': {
        const list = options[f.key];
        const labelOf = (o) => String(read(o, f.refLabel || 'name') ?? o.name ?? o.id);
        if (list instanceof Error) return <div className="error-box" key={f.key}>{f.label}: {list.message}</div>;
        if (f.type === 'refMulti') {
          return (
            <div className="field" key={f.key} style={{ marginBottom: 14 }}>
              <span style={{ display: 'block', fontWeight: 600, fontSize: 13, marginBottom: 6 }}>{label}</span>
              <div className="chips">
                {!list && <span className="muted small">Loading…</span>}
                {list && !list.length && <span className="muted small">Nothing to choose yet</span>}
                {list?.map((o) => {
                  const id = String(o.id);
                  const on = v.includes(id);
                  return (
                    <button type="button" key={id} className={`chip-btn${on ? ' active' : ''}`}
                      onClick={() => set(f.key, on ? v.filter((x) => x !== id) : [...v, id])}>
                      {on ? '✓ ' : ''}{labelOf(o)}
                    </button>
                  );
                })}
              </div>
              {hint && <small className="hint" style={{ color: 'var(--muted)', fontSize: 12, display: 'block', marginTop: 4 }}>{f.hint}</small>}
            </div>
          );
        }
        return (
          <label className="field" key={f.key}>
            <span>{label}</span>
            <select value={v} onChange={(e) => set(f.key, e.target.value)} disabled={!list}>
              <option value="">{list ? (f.required ? '— Select —' : '— None —') : 'Loading…'}</option>
              {list?.map((o) => <option key={o.id} value={String(o.id)}>{labelOf(o)}</option>)}
            </select>
            {hint}
          </label>
        );
      }
      default: {
        const type = { integer: 'number', decimal: 'number', date: 'date', datetime: 'datetime-local', phone: 'tel' }[f.type] || 'text';
        return (
          <label className="field" key={f.key}>
            <span>{label}</span>
            <input type={type} step={f.type === 'decimal' ? '0.01' : undefined} value={v} onChange={(e) => set(f.key, e.target.value)} />
            {hint}
          </label>
        );
      }
    }
  };

  return (
    <form onSubmit={submit}>
      {intro && <div className="info-box">{intro}</div>}
      {error && <div className="error-box">{error}</div>}
      {fields.map(renderField)}
      <div className="row" style={{ marginTop: 8 }}>
        <button className="btn primary" type="submit" disabled={saving}>{saving ? 'Saving…' : submitLabel}</button>
        {onCancel && <button className="btn ghost" type="button" onClick={onCancel}>Cancel</button>}
      </div>
    </form>
  );
}
