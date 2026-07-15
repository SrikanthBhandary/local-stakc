import { staticTours } from '../data/tours.js';

// Set VITE_TOURS_API_URL in .env (see .env.example) to point this at your
// real backend, e.g. an API Gateway endpoint backed by a Lambda that reads
// the tours/packages table. Leave it unset to serve the static list below.
const TOURS_API_URL = import.meta.env.VITE_TOURS_API_URL;

export async function fetchTours() {
  if (!TOURS_API_URL) {
    return staticTours;
  }

  try {
    const res = await fetch(TOURS_API_URL);
    if (!res.ok) throw new Error(`Tours API responded with ${res.status}`);
    const data = await res.json();
    return Array.isArray(data) && data.length > 0 ? data : staticTours;
  } catch (err) {
    console.warn('Falling back to static tour data:', err);
    return staticTours;
  }
}
