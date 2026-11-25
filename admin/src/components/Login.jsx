import { useState } from 'react';
import { ArrowRight, Building2, KeyRound, ReceiptText, ShieldCheck, Smartphone, Users } from 'lucide-react';
import { api, tokens } from '../api.js';
import { useSession } from '../session.jsx';
import { BrandMark, Wordmark } from './Brand.jsx';

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
    <div className="login-split">
      <aside className="login-hero">
        <span className="blob b1" />
        <span className="blob b2" />
        <div style={{ position: 'relative' }}><Wordmark size={22} onDark /></div>
        <div className="hero-body">
          <BrandMark size={84} className="hero-mark" />
          <h1>Run your community<br />from one place.</h1>
          <p>Approvals, towers, bills, help desk and security for every building you manage.</p>
          <div className="hero-points stagger">
            {[
              [Users, 'Approve residents tower by tower'],
              [Building2, 'Set up towers and flats in seconds'],
              [ReceiptText, 'Bill every flat and track dues'],
              [ShieldCheck, 'Visitors, SOS alerts and incidents'],
            ].map(([Icon, text]) => (
              <div className="hero-point" key={text}><span className="ic"><Icon size={18} /></span>{text}</div>
            ))}
          </div>
        </div>
        <div className="hero-foot">© GlobaCity · Admin dashboard</div>
      </aside>

      <main className="login-pane">
        <div className="login-card fade-up">
          <h2>Welcome back</h2>
          <p className="muted" style={{ margin: '6px 0 22px' }}>Sign in as a community admin, tower admin or manager.</p>
          <div className="tabs" style={{ marginBottom: 20 }}>
            <button className={mode === 'password' ? 'active' : ''} onClick={() => { setMode('password'); setError(null); }}>
              <KeyRound size={15} /> Password
            </button>
            <button className={mode === 'otp' ? 'active' : ''} onClick={() => { setMode('otp'); setError(null); }}>
              <Smartphone size={15} /> Phone code
            </button>
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
              <button className="btn primary block" disabled={busy}>{busy ? 'Signing in…' : <>Sign in <ArrowRight size={17} /></>}</button>
            </form>
          ) : !codeSent ? (
            <form onSubmit={sendCode}>
              <label className="field"><span>Mobile number</span>
                <input type="tel" autoFocus value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="+919812345678" required />
                <small className="hint">The phone number your community admin added you with.</small>
              </label>
              <button className="btn primary block" disabled={busy}>{busy ? 'Sending…' : <>Send code <ArrowRight size={17} /></>}</button>
            </form>
          ) : (
            <form onSubmit={verify}>
              {codeSent.debug_code && <div className="info-box">Test mode: your code is <b>{codeSent.debug_code}</b></div>}
              <label className="field"><span>Code sent to {phone}</span>
                <input type="text" inputMode="numeric" autoFocus value={code} onChange={(e) => setCode(e.target.value)} required />
              </label>
              <button className="btn primary block" disabled={busy}>{busy ? 'Verifying…' : <>Verify &amp; sign in <ArrowRight size={17} /></>}</button>
              <button type="button" className="btn ghost block" style={{ marginTop: 8 }} onClick={() => { setCodeSent(null); setCode(''); }}>
                Use a different number
              </button>
            </form>
          )}
        </div>
      </main>
    </div>
  );
}
