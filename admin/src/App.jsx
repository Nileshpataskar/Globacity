import { HashRouter, Navigate, Route, Routes } from 'react-router-dom';
import Dashboard from './components/Dashboard.jsx';
import Layout from './components/Layout.jsx';
import Login from './components/Login.jsx';
import { BulkBill, CommunitySettings } from './components/Pages.jsx';
import ResourcePage from './components/ResourcePage.jsx';
import { BrandLoader, SessionProvider, useSession } from './session.jsx';

function Gate() {
  const { loading, user } = useSession();
  if (loading) return <BrandLoader />;
  if (!user) return <Login />;
  return (
    <HashRouter>
      <Routes>
        <Route element={<Layout />}>
          <Route path="/overview" element={<Dashboard />} />
          <Route path="/r/:key" element={<ResourcePage />} />
          <Route path="/bulk-bill" element={<BulkBill />} />
          <Route path="/settings" element={<CommunitySettings />} />
          <Route path="*" element={<Navigate to="/overview" replace />} />
        </Route>
      </Routes>
    </HashRouter>
  );
}

export default function App() {
  return (
    <SessionProvider>
      <Gate />
    </SessionProvider>
  );
}
