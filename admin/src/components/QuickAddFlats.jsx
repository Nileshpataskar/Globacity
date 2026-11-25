import { useEffect, useMemo, useState } from 'react';
import { api } from '../api.js';
import { F } from '../resources.js';
import { useSession } from '../session.jsx';

const pad2 = (n) => String(n).padStart(2, '0');
const LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

/** Numbering styles. `format` is the server-side Python format; `preview` mirrors it in JS. */
export const NUMBERING = [
  { id: 'plain', label: '101, 102, 201 …', format: () => '{floor}{index:02d}', preview: (f, i) => `${f}${pad2(i)}` },
  { id: 'code', label: 'A-101, A-102 … (tower code first)', format: (code) => `${esc(code)}-{floor}{index:02d}`,
    preview: (f, i, code) => `${code}-${f}${pad2(i)}` },
  { id: 'codeplain', label: 'A101, A102 …', format: (code) => `${esc(code)}{floor}{index:02d}`,
    preview: (f, i, code) => `${code}${f}${pad2(i)}` },
  { id: 'dash', label: '1-1, 1-2, 2-1 … (floor-flat)', format: () => '{floor}-{index}', preview: (f, i) => `${f}-${i}` },
];
const esc = (s) => String(s || '').replace(/[{}]/g, '');

export function towerCode(tower) {
  if (tower?.code) return tower.code;
  const words = String(tower?.name || '').trim().split(/\s+/);
  const last = words.at(-1) || '';
  return /^[A-Za-z0-9]{1,3}$/.test(last) ? last.toUpperCase() : (words[0]?.[0] || 'T').toUpperCase();
}

export function previewNumbers(style, from, to, perFloor, code) {
  const s = NUMBERING.find((n) => n.id === style) || NUMBERING[0];
  const floors = [];
  for (let f = from; f <= to && floors.length < 200; f++) {
    floors.push([f, Array.from({ length: perFloor }, (_, k) => s.preview(f, k + 1, code))]);
  }
  return floors;
}

/** Creates flats for a tower: floors × flats per floor, with a live preview. */
export default function QuickAddFlats({ tower: fixedTower, onDone, onCancel }) {
  const { community, notify } = useSession();
  const [towers, setTowers] = useState(fixedTower ? [fixedTower] : null);
  const [towerId, setTowerId] = useState(fixedTower?.id || '');
  const [from, setFrom] = useState(1);
  const [to, setTo] = useState(fixedTower?.floors || 3);
  const [perFloor, setPerFloor] = useState(4);
  const [style, setStyle] = useState('plain');
  const [type, setType] = useState('apartment');
  const [error, setError] = useState(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (fixedTower || !community) return;
    api.listAll('/manage/towers/', { community: community.id }).then((list) => {
      setTowers(list);
      if (list.length) {
        setTowerId((id) => id || list[0].id);
        setTo((t) => list[0].floors || t);
      }
    }).catch((e) => setError(e.message));
  }, [fixedTower, community]);

  const tower = towers?.find((t) => t.id === towerId);
  const code = towerCode(tower);
  const nFrom = Number(from);
  const nTo = Number(to);
  const nPer = Number(perFloor);
  const valid = tower && Number.isInteger(nFrom) && Number.isInteger(nTo) && nFrom >= 0 && nTo >= nFrom && nPer >= 1 && nPer <= 100;
  const floors = useMemo(() => (valid ? previewNumbers(style, nFrom, nTo, nPer, code) : []),
    [valid, style, nFrom, nTo, nPer, code]);
  const total = valid ? (nTo - nFrom + 1) * nPer : 0;

  const submit = async (e) => {
    e.preventDefault();
    if (!valid) return;
    setSaving(true);
    setError(null);
    try {
      const fmt = NUMBERING.find((n) => n.id === style).format(code);
      const res = await api.post(`/manage/towers/${tower.id}/generate-units/`, {
        floor_from: nFrom, floor_to: nTo, units_per_floor: nPer, unit_type: type, number_format: fmt,
      });
      notify(res.skipped ? `Created ${res.created} flats (${res.skipped} already existed)` : `Created ${res.created} flats in ${tower.name}`);
      onDone?.(res);
    } catch (err) {
      setError(err.message);
      setSaving(false);
    }
  };

  if (towers && !towers.length) {
    return <div className="info-box">Add a tower first (Property → Towers), then quick-add its flats here.</div>;
  }

  return (
    <form onSubmit={submit}>
      {error && <div className="error-box">{error}</div>}
      {!fixedTower && (
        <label className="field"><span>Tower *</span>
          <select value={towerId} onChange={(e) => {
            setTowerId(e.target.value);
            const t = towers.find((x) => x.id === e.target.value);
            if (t?.floors) setTo(t.floors);
          }}>
            {!towers && <option>Loading…</option>}
            {towers?.map((t) => <option key={t.id} value={t.id}>{t.name}{t.units_count ? ` (${t.units_count} flats)` : ''}</option>)}
          </select>
        </label>
      )}
      <div className="grid" style={{ gridTemplateColumns: '1fr 1fr 1fr' }}>
        <label className="field"><span>From floor</span>
          <input type="number" min="0" value={from} onChange={(e) => setFrom(e.target.value)} />
        </label>
        <label className="field"><span>To floor</span>
          <input type="number" min="0" value={to} onChange={(e) => setTo(e.target.value)} />
        </label>
        <label className="field"><span>Flats per floor</span>
          <input type="number" min="1" max="100" value={perFloor} onChange={(e) => setPerFloor(e.target.value)} />
        </label>
      </div>
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

      <div className="card card-pad" style={{ background: 'var(--surface-2)', marginBottom: 16 }}>
        <h3 style={{ marginBottom: 8 }}>
          {valid ? `Preview: ${total} flats on ${nTo - nFrom + 1} floor${nTo === nFrom ? '' : 's'}` : 'Check the numbers above'}
        </h3>
        <div style={{ maxHeight: 220, overflowY: 'auto' }}>
          {floors.map(([f, nums]) => (
            <div key={f} className="row" style={{ marginBottom: 6 }}>
              <span className="muted small" style={{ width: 58 }}>Floor {f}</span>
              {nums.map((n) => <span key={n} className="badge">{n}</span>)}
            </div>
          ))}
        </div>
        {valid && <p className="muted small" style={{ margin: '8px 0 0' }}>Flats that already exist are skipped, so it&apos;s safe to run again.</p>}
      </div>

      <div className="row">
        <button className="btn primary" disabled={!valid || saving}>{saving ? 'Creating…' : `Create ${total || ''} flats`}</button>
        {onCancel && <button type="button" className="btn ghost" onClick={onCancel}>Cancel</button>}
      </div>
    </form>
  );
}
