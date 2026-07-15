import { useState } from 'react';

// Set VITE_ENQUIRY_API_URL in .env (see .env.example) to your API Gateway
// invoke URL once the writer Lambda is deployed. Left unset, the form shows
// the fallback contact message instead of attempting a network call.
const ENQUIRY_API_URL = import.meta.env.VITE_ENQUIRY_API_URL;

const FALLBACK_MESSAGE =
  "We couldn't reach the booking system just yet — email us directly at hello@highpasses.example and we'll take it from there.";

const initialForm = { name: '', email: '', phone: '', travelers: 2, dates: '', message: '' };

function EnquiryForm({ tours, selectedTourId, onSelectedTourChange }) {
  const [form, setForm] = useState(initialForm);
  const [status, setStatus] = useState(null); // { text, error }
  const [submitting, setSubmitting] = useState(false);

  function updateField(field, value) {
    setForm(prev => ({ ...prev, [field]: value }));
  }

  async function handleSubmit(e) {
    e.preventDefault();
    setSubmitting(true);
    setStatus(null);

    const payload = {
      id: crypto.randomUUID ? crypto.randomUUID() : String(Date.now()),
      tour: selectedTourId,
      ...form,
      travelers: Number(form.travelers)
    };

    if (!ENQUIRY_API_URL) {
      console.warn('VITE_ENQUIRY_API_URL is not set — payload not sent:', payload);
      setStatus({ text: FALLBACK_MESSAGE, error: true });
      setSubmitting(false);
      return;
    }

    try {
      const res = await fetch(ENQUIRY_API_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });
      if (!res.ok) throw new Error('Request failed');
      setStatus({ text: "Enquiry sent — we'll be in touch within 24 hours.", error: false });
      setForm(initialForm);
    } catch (err) {
      setStatus({ text: FALLBACK_MESSAGE, error: true });
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="enquire-box">
      <h2>Tell us where you want to go</h2>
      <p>
        No payment needed here — this just starts the conversation. Our
        travel desk will follow up with confirmed dates, hotel options, and
        a detailed itinerary.
      </p>

      <form onSubmit={handleSubmit}>
        <div className="form-row">
          <div className="field">
            <label htmlFor="name">Full name</label>
            <input
              id="name"
              required
              value={form.name}
              onChange={e => updateField('name', e.target.value)}
            />
          </div>
          <div className="field">
            <label htmlFor="email">Email</label>
            <input
              id="email"
              type="email"
              required
              value={form.email}
              onChange={e => updateField('email', e.target.value)}
            />
          </div>
        </div>

        <div className="form-row">
          <div className="field">
            <label htmlFor="phone">Phone</label>
            <input
              id="phone"
              type="tel"
              required
              value={form.phone}
              onChange={e => updateField('phone', e.target.value)}
            />
          </div>
          <div className="field">
            <label htmlFor="travelers">Travelers</label>
            <input
              id="travelers"
              type="number"
              min="1"
              required
              value={form.travelers}
              onChange={e => updateField('travelers', e.target.value)}
            />
          </div>
        </div>

        <div className="form-row">
          <div className="field">
            <label htmlFor="tour">Route</label>
            <select
              id="tour"
              required
              value={selectedTourId}
              onChange={e => onSelectedTourChange(e.target.value)}
            >
              {tours.map(tour => (
                <option key={tour.id} value={tour.id}>
                  {tour.name} ({tour.duration})
                </option>
              ))}
            </select>
          </div>
          <div className="field">
            <label htmlFor="dates">Preferred dates</label>
            <input
              id="dates"
              required
              placeholder="e.g. Late August, flexible"
              value={form.dates}
              onChange={e => updateField('dates', e.target.value)}
            />
          </div>
        </div>

        <div className="field">
          <label htmlFor="message">Anything else we should know</label>
          <textarea
            id="message"
            placeholder="Trip experience, dietary needs, fitness level, altitude concerns..."
            value={form.message}
            onChange={e => updateField('message', e.target.value)}
          />
        </div>

        <div className="submit-row">
          <button type="submit" className="btn btn-primary" disabled={submitting}>
            {submitting ? 'Sending...' : 'Send enquiry'}
          </button>
        </div>

        {status && (
          <div className={`form-msg show ${status.error ? 'err' : 'ok'}`}>
            {status.text}
          </div>
        )}
      </form>
    </div>
  );
}

export default EnquiryForm;
