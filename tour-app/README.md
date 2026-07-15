# High Passes — frontend

React + Vite site for the Ladakh/Manali tour enquiry flow.

## Develop

```
npm install
npm run dev
```

## Configure data sources

Copy `.env.example` to `.env` and fill in either or both:

- `VITE_TOURS_API_URL` — if set, tour cards are fetched from this endpoint
  (expects a JSON array shaped like `src/data/tours.js`). If unset, the site
  serves the static list in `src/data/tours.js` — no backend required.
- `VITE_ENQUIRY_API_URL` — if set, the enquiry form POSTs here. If unset, the
  form shows a fallback "email us directly" message instead of submitting.

Vite bakes `VITE_*` env vars in at **build time** — there's no runtime config
swap on a static site. If you need to point the same build at different
environments (dev/staging/prod) without rebuilding, let me know and I can add
a `config.json` fetched at page load instead.

## Build for S3

```
npm run build
aws s3 sync dist/ s3://your-bucket-name --delete
```

`dist/` is a fully static bundle — same deployment story as the earlier
plain-HTML version, just built from components now.
