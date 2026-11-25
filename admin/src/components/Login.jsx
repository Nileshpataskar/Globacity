import { useState } from 'react';
import { api, tokens } from '../api.js';
import { useSession } from '../session.jsx';

/** Password login (e.g. "admin") or one-time code to the phone (tower admins, managers). */
export default function Login() {
  const { reload, error: sessionError } = useSession();
  const [mode, setMode] = useState('password');
  const [identifier, setIdentifier] = useState('');
  const [password, setPassword] = useState('');
  const [phone, setPhone] = useState('+91');
  const [code, setCode] = useState('');
  const [codeSent, setCodeSent] = useState(null);
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);

  const attempt = async (fn) => {
    setBusy(true);
    setError(null);
    try {
      await fn();
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  };

  const signedIn = async (res) => {
    tokens.save(res.access, res.refresh);
    await reload();
  };

  const loginPassword = (e) => {
    e.preventDefault();
    attempt(async () => signedIn(await api.post('/auth/login/', { identifier: identifier.trim(), password }, { auth: false })));
  };

  const sendCode = (e) => {
    e.preventDefault();
    attempt(async () => {
      const res = await api.post('/auth/otp/request/', { phone: phone.replace(/\s/g, '') }, { auth: false });
      setCodeSent(res);
    });
  };

  const verify = (e) => {
    e.preventDefault();
    attempt(async () => signedIn(await api.post('/auth/otp/verify/', { phone: phone.replace(/\s/g, ''), code: code.trim() }, { auth: false })));
  };

  return (
    <div className="login-wrap">
      <div className="login-card">
        <div className="brand"><span className="brand-mark">G</span> Globacity Admin</div>
        <p className="muted" style={{ margin: '10px 0 22px' }}>
          Management dashboard for community admins, tower admins and managers.
        </p>
        <div className="tabs" style={{ marginBottom: 20 }}>
          <button className={mode === 'password' ? 'active' : ''} onClick={() => { setMode('password'); setError(null); }}>Password</button>
          <button className={mode === 'otp' ? 'active' : ''} onClick={() => { setMode('otp'); setError(null); }}>Phone code</button>
        </div>
        {(error || sessionError) && <div className="error-box">{error || sessionError}</div>}

        {mode === 'password' ? (
          <form onSubmit={loginPassword}>
            <label className="field"><span>Username, phone or email</span>
              <input type="text" autoFocus value={identifier} onChange={(e) => setIdentifier(e.target.value)} placeholder="admin" required />
            </label>
            <label className="field"><span>Password</span>
              <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} required />
            </label>
            <button className="btn primary block" disabled={busy}>{busy ? 'Signing in…' : 'Sign in'}</button>
          </form>
        ) : !codeSent ? (
          <form onSubmit={sendCode}>
            <label className="field"><span>Mobile number</span>
              <input type="tel" autoFocus value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="+919812345678" required />
              <small className="hint">The phone number your community admin added you with.</small>
            </label>
            <button className="btn primary block" disabled={busy}>{busy ? 'Sending…' : 'Send code'}</button>
          </form>
        ) : (
          <form onSubmit={verify}>
            {codeSent.debug_code && <div className="info-box">Test mode: your code is <b>{codeSent.debug_code}</b></div>}
            <label className="field"><span>Code sent to {phone}</span>
              <input type="text" inputMode="numeric" autoFocus value={code} onChange={(e) => setCode(e.target.value)} required />
            </label>
            <button className="btn primary block" disabled={busy}>{busy ? 'Verifying…' : 'Verify & sign in'}</button>
            <button type="button" className="btn ghost block" style={{ marginTop: 8 }} onClick={() => { setCodeSent(null); setCode(''); }}>
              Use a different number
            </button>
          </form>
        )}
      </div>
    </div>
  );
}
