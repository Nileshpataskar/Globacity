import { useEffect, useMemo, useState } from 'react';
import { Building2, Check, Minus, Plus, Trash2, X } from 'lucide-react';
import { api } from '../api.js';
import { F } from '../resources.js';
import { Spinner, useSession } from '../session.jsx';

const pad2 = (n) => String(n).padStart(2, '0');

/** Numbering styles. `make(floor, index, code)` builds a flat number. */
export const NUMBERING = [
  { id: 'plain', label: '101, 102, 201 …', make: (f, i) => `${f}${pad2(i)}` },
  { id: 'code', label: 'A-101, A-102 … (tower code first)', make: (f, i, c) => `${c}-${f}${pad2(i)}` },
  { id: 'codeplain', label: 'A101, A102 …', make: (f, i, c) => `${c}${f}${pad2(i)}` },
  { id: 'dash', label: '1-1, 1-2, 2-1 … (floor-flat)', make: (f, i) => `${f}-${i}` },
];

export function towerCode(tower) {
  if (tower?.code) return tower.code;
  const words = String(tower?.name || '').trim().split(/\s+/);
  const last = words.at(-1) || '';
  return /^[A-Za-z0-9]{1,3}$/.test(last) ? last.toUpperCase() : (words[0]?.[0] || 'T').toUpperCase();
}

const buildPlan = (from, to, perFloor, style, code) => {
  const s = NUMBERING.find((n) => n.id === style) || NUMBERING[0];
  const floors = [];
  for (let f = to; f >= from && floors.length < 200; f--) {
    floors.push({ floor: f, flats: Array.from({ length: perFloor }, (_, k) => ({ number: s.make(f, k + 1, code), on: true })) });
  }
  return floors;
};

/**
 * Building plan for one tower.
 * - "view": existing flats by floor, coloured by occupancy; select flats to delete.
 * - "plan": preview of flats to create (floors × flats per floor); remove / add flats and floors, then create.
 */
export default function QuickAddFlats({ tower: fixedTower, preset, startIn = 'plan', onDone, onCancel }) {
  const { community, notify } = useSession();
  const [towers, setTowers] = useState(fixedTower ? [fixedTower] : null);
  const [towerId, setTowerId] = useState(fixedTower?.id || '');
  const [mode, setMode] = useState(startIn);
  const [existing, setExisting] = useState(null); // units of the tower
  const [occupancy, setOccupancy] = useState({}); // unit id -> 'approved' | 'pending'
  const [error, setError] = useState(null);

  useEffect(() => {
    if (fixedTower || !community) return;
    api.listAll('/manage/towers/', { community: community.id }).then((list) => {
      setTowers(list);
      if (list.length) setTowerId((id) => id || list[0].id);
    }).catch((e) => setError(e.message));
  }, [fixedTower, community]);

  const tower = towers?.find((t) => t.id === towerId);

  const loadExisting = async () => {
    if (!towerId) return;
    setExisting(null);
    try {
      const [units, members] = await Promise.all([
        api.listAll('/manage/units/', { tower: towerId }),
        api.listAll('/manage/memberships/', { unit__tower: towerId }),
      ]);
      const occ = {};
      for (const m of members) {
        if (m.status === 'approved') occ[m.unit] = 'approved';
        else if (m.status === 'pending' && occ[m.unit] !== 'approved') occ[m.unit] = 'pending';
      }
      setOccupancy(occ);
      setExisting(units);
    } catch (e) {
      setError(e.message);
    }
  };
  useEffect(() => { loadExisting(); }, [towerId]); // eslint-disable-line react-hooks/exhaustive-deps

  if (towers && !towers.length) {
    return <div className="info-box">Add a tower first (Property → Towers), then plan its flats here.</div>;
  }

  return (
    <div>
      {error && <div className="error-box">{error}</div>}
      {!fixedTower && (
        <label className="field"><span>Tower</span>
          <select value={towerId} onChange={(e) => setTowerId(e.target.value)}>
            {!towers && <option>Loading…</option>}
            {towers?.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
          </select>
        </label>
      )}
      <div className="tabs" style={{ marginBottom: 18 }}>
        <button className={mode === 'view' ? 'active' : ''} onClick={() => setMode('view')}><Building2 size={15} /> Building plan</button>
        <button className={mode === 'plan' ? 'active' : ''} onClick={() => setMode('plan')}><Plus size={15} /> Add flats</button>
      </div>
      {!tower || existing === null ? <Spinner /> : mode === 'view' ? (
        <ExistingPlan tower={tower} units={existing} occupancy={occupancy} notify={notify}
          onChanged={loadExisting} onAdd={() => setMode('plan')} />
      ) : (
        <PlanEditor key={tower.id} tower={tower} preset={preset} existing={existing} notify={notify}
          onCreated={(res) => { loadExisting(); setMode('view'); onDone?.(res, false); }}
          onCancel={onCancel} />
      )}
    </div>
  );
}

/** Existing flats drawn as a building; click flats to select them for deletion. */
function ExistingPlan({ tower, units, occupancy, notify, onChanged, onAdd }) {
  const [selected, setSelected] = useState(new Set());
  const [busy, setBusy] = useState(false);
  const floors = useMemo(() => {
    const byFloor = new Map();
    for (const u of units) {
      const f = u.floor ?? 0;
      if (!byFloor.has(f)) byFloor.set(f, []);
      byFloor.get(f).push(u);
    }
    return [...byFloor.entries()].sort((a, b) => b[0] - a[0])
      .map(([floor, list]) => ({ floor, flats: list.sort((a, b) => a.number.localeCompare(b.number, undefined, { numeric: true })) }));
  }, [units]);

  if (!units.length) {
    return (
      <div className="empty" style={{ padding: '30px 10px' }}>
        <div className="empty-ic"><Building2 size={28} /></div>
        <h3>{tower.name} has no flats yet</h3>
        <p style={{ margin: '0 0 14px' }}>Plan the floors and flats, check the preview, then create them.</p>
        <button className="btn primary" onClick={onAdd}><Plus size={16} /> Add flats</button>
      </div>
    );
  }

  const toggle = (id) => setSelected((s) => {
    const n = new Set(s);
    n.has(id) ? n.delete(id) : n.add(id);
    return n;
  });
  const occupiedSelected = [...selected].filter((id) => occupancy[id]).length;

  const del = async () => {
    const extra = occupiedSelected ? `\n\n${occupiedSelected} of them have residents or pending requests, which will be removed too.` : '';
    if (!window.confirm(`Delete ${selected.size} flat${selected.size === 1 ? '' : 's'} from ${tower.name}?${extra}`)) return;
    setBusy(true);
    try {
      const res = await api.post('/manage/units/bulk-delete/', { ids: [...selected] });
      notify(`Deleted ${res.deleted} flats`);
      setSelected(new Set());
      onChanged();
    } catch (e) {
      notify(e.message, true);
    } finally {
      setBusy(false);
    }
  };

  const counts = { total: units.length, occupied: units.filter((u) => occupancy[u.id] === 'approved').length,
    pending: units.filter((u) => occupancy[u.id] === 'pending').length };

  return (
    <>
      <div className="plan-legend">
        <span><i className="sw occupied" /> Occupied {counts.occupied}</span>
        <span><i className="sw pending" /> Pending {counts.pending}</span>
        <span><i className="sw vacant" /> Vacant {counts.total - counts.occupied - counts.pending}</span>
        <span className="muted">Click flats to select them</span>
      </div>
      <div className="building">
        <div className="roof">{tower.name}</div>
        {floors.map(({ floor, flats }) => (
          <div className="floor" key={floor}>
            <div className="floor-no">{floor === 0 ? 'G' : floor}</div>
            <div className="flats">
              {flats.map((u) => (
                <button key={u.id} type="button" title={`${u.number} · ${occupancy[u.id] || 'vacant'}`}
                  className={`flat ${occupancy[u.id] === 'approved' ? 'occupied' : occupancy[u.id] || 'vacant'}${selected.has(u.id) ? ' selected' : ''}`}
                  onClick={() => toggle(u.id)}>
                  {selected.has(u.id) && <Check size={12} />}{u.number}
                </button>
              ))}
            </div>
          </div>
        ))}
        <div className="ground" />
      </div>
      <div className="row" style={{ marginTop: 16 }}>
        {selected.size > 0 ? (
          <>
            <button className="btn danger" disabled={busy} onClick={del}><Trash2 size={15} /> Delete {selected.size} selected</button>
            <button className="btn ghost" onClick={() => setSelected(new Set())}>Clear selection</button>
          </>
        ) : (
          <button className="btn primary" onClick={onAdd}><Plus size={16} /> Add more flats</button>
        )}
      </div>
    </>
  );
}

/** Preview of flats to create. Nothing is saved until "Create". */
function PlanEditor({ tower, preset, existing, notify, onCreated, onCancel }) {
  const code = towerCode(tower);
  const existingNumbers = useMemo(() => new Set(existing.map((u) => u.number)), [existing]);
  const topExisting = existing.reduce((m, u) => Math.max(m, u.floor ?? 0), 0);
  const [from, setFrom] = useState(preset?.from ?? (existing.length ? topExisting + 1 : 1));
  const [to, setTo] = useState(preset?.to ?? Math.max(tower.floors || 3, existing.length ? topExisting + 1 : 1));
  const [perFloor, setPerFloor] = useState(preset?.perFloor ?? 4);
  const [style, setStyle] = useState(preset?.numbering ?? 'plain');
  const [type, setType] = useState('apartment');
  const [floors, setFloors] = useState(null);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(null);

  const nFrom = Number(from);
  const nTo = Number(to);
  const nPer = Number(perFloor);
  const valid = Number.isInteger(nFrom) && Number.isInteger(nTo) && nFrom >= 0 && nTo >= nFrom && nPer >= 1 && nPer <= 50;

  // Rebuild the preview whenever the inputs change.
  useEffect(() => {
    setFloors(valid ? buildPlan(nFrom, nTo, nPer, style, code) : []);
  }, [nFrom, nTo, nPer, style, code, valid]);

  const styleDef = NUMBERING.find((n) => n.id === style) || NUMBERING[0];
  const update = (fn) => setFloors((fl) => fn(fl.map((f) => ({ ...f, flats: [...f.flats] }))));
  const toggleFlat = (fi, i) => update((fl) => { fl[fi].flats[i] = { ...fl[fi].flats[i], on: !fl[fi].flats[i].on }; return fl; });
  const addFlat = (fi) => update((fl) => {
    const f = fl[fi];
    let i = f.flats.length + 1;
    while (f.flats.some((x) => x.number === styleDef.make(f.floor, i, code))) i++;
    f.flats.push({ number: styleDef.make(f.floor, i, code), on: true, added: true });
    return fl;
  });
  const removeFloor = (fi) => update((fl) => fl.filter((_, i) => i !== fi));
  const addFloorOnTop = () => update((fl) => {
    const top = fl.length ? fl[0].floor + 1 : nFrom;
    const count = fl.length ? fl[0].flats.length : nPer;
    return [{ floor: top, flats: Array.from({ length: count }, (_, k) => ({ number: styleDef.make(top, k + 1, code), on: true, added: true })) }, ...fl];
  });

  const toCreate = (floors || []).flatMap((f) => f.flats.filter((x) => x.on && !existingNumbers.has(x.number))
    .map((x) => ({ number: x.number, floor: f.floor, unit_type: type })));
  const dupes = (floors || []).flatMap((f) => f.flats.filter((x) => x.on && existingNumbers.has(x.number))).length;

  const create = async () => {
    setSaving(true);
    setError(null);
    try {
      const res = await api.post(`/manage/towers/${tower.id}/bulk-units/`, { units: toCreate });
      notify(`Created ${res.created} flats in ${tower.name}`);
      onCreated(res);
    } catch (e) {
      setError(e.message);
      setSaving(false);
    }
  };

  return (
    <>
      {error && <div className="error-box">{error}</div>}
      <div className="grid" style={{ gridTemplateColumns: '1fr 1fr 1fr', gap: 10 }}>
        <label className="field"><span>From floor</span><input type="number" min="0" value={from} onChange={(e) => setFrom(e.target.value)} /></label>
        <label className="field"><span>To floor</span><input type="number" min="0" value={to} onChange={(e) => setTo(e.target.value)} /></label>
        <label className="field"><span>Flats / floor</span><input type="number" min="1" max="50" value={perFloor} onChange={(e) => setPerFloor(e.target.value)} /></label>
      </div>
      <div className="grid" style={{ gridTemplateColumns: '1.4fr 1fr', gap: 10 }}>
        <label className="field"><span>Numbering</span>
          <select value={style} onChange={(e) => setStyle(e.target.value)}>
            {NUMBERING.map((n) => <option key={n.id} value={n.id}>{n.id.startsWith('code') ? n.label.replaceAll('A', code) : n.label}</option>)}
          </select>
        </label>
        <label className="field"><span>Type</span>
          <select value={type} onChange={(e) => setType(e.target.value)}>
            {['apartment', 'villa', 'townhouse', 'office', 'shop'].map((t) => <option key={t} value={t}>{F.human(t)}</option>)}
          </select>
        </label>
      </div>

      <div className="plan-legend">
        <span><i className="sw new" /> Will be created</span>
        <span><i className="sw off" /> Removed</span>
        {dupes > 0 && <span><i className="sw exists" /> Already exists ({dupes})</span>}
        <span className="muted">Click a flat to remove / restore it</span>
      </div>

      {!valid ? <div className="info-box">Check the floor numbers and flats per floor.</div> : (
        <div className="building">
          <div className="roof">
            {tower.name}
            <button type="button" className="btn sm" onClick={addFloorOnTop}><Plus size={13} /> Floor on top</button>
          </div>
          {(floors || []).map((f, fi) => (
            <div className="floor" key={f.floor}>
              <div className="floor-no">{f.floor === 0 ? 'G' : f.floor}</div>
              <div className="flats">
                {f.flats.map((x, i) => {
                  const exists = existingNumbers.has(x.number);
                  return (
                    <button type="button" key={x.number} disabled={exists}
                      className={`flat ${exists ? 'exists' : x.on ? 'new' : 'off'}`}
                      title={exists ? 'Already exists: skipped' : x.on ? 'Click to remove' : 'Click to restore'}
                      onClick={() => toggleFlat(fi, i)}>
                      {!exists && !x.on && <X size={12} />}{x.number}
                    </button>
                  );
                })}
                <button type="button" className="flat add" title="Add a flat on this floor" onClick={() => addFlat(fi)}><Plus size={13} /></button>
              </div>
              <button type="button" className="btn ghost sm floor-del" title="Remove this floor" onClick={() => removeFloor(fi)}><Minus size={14} /></button>
            </div>
          ))}
          <div className="ground" />
        </div>
      )}

      <div className="plan-summary">
        <b>{toCreate.length}</b> flat{toCreate.length === 1 ? '' : 's'} will be created on <b>{new Set(toCreate.map((u) => u.floor)).size}</b> floor(s)
        {dupes > 0 && <span className="muted"> · {dupes} already exist and will be skipped</span>}
      </div>
      <div className="row">
        <button className="btn primary" disabled={!toCreate.length || saving} onClick={create}>
          <Check size={16} /> {saving ? 'Creating…' : `Create ${toCreate.length} flats`}
        </button>
        <button type="button" className="btn ghost" onClick={onCancel}>Cancel</button>
      </div>
    </>
  );
}
