# Globacity Admin (React)

Web dashboard for community admins, tower admins and managers. Talks to the Django API on port 8000.

```bash
npm install          # first time
npm run dev          # live-reloading dev server on http://localhost:5173
npm run build        # production build to dist/ (served by Docker on http://localhost:8080)
```

- Log in with a password (`admin` / `admin123` in the demo) or a one-time code sent to the staff member's phone.
- Every management area is described in `src/resources.js` (columns, filters, form fields, actions) and rendered by
  `src/components/ResourcePage.jsx`. Add a new area there.
- The API address defaults to the same host on port 8000. Override with `VITE_API_URL=https://api.example.com/api/v1`.
