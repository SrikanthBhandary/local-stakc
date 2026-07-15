import { useEffect, useRef, useState } from 'react';
import Hero from './components/Hero.jsx';
import TourList from './components/TourList.jsx';
import EnquiryForm from './components/EnquiryForm.jsx';
import Footer from './components/Footer.jsx';
import { fetchTours } from './api/tours.js';

function App() {
  const [tours, setTours] = useState([]);
  const [loading, setLoading] = useState(true);
  const [selectedTourId, setSelectedTourId] = useState('');
  const enquireRef = useRef(null);

  useEffect(() => {
    let active = true;
    fetchTours().then(data => {
      if (!active) return;
      setTours(data);
      setLoading(false);
      if (data.length > 0) setSelectedTourId(data[0].id);
    });
    return () => { active = false; };
  }, []);

  function handleEnquire(tourId) {
    setSelectedTourId(tourId);
    enquireRef.current?.scrollIntoView({ behavior: 'smooth' });
  }

  return (
    <>
      <Hero />

      <section className="section" id="tours">
        <div className="wrap">
          <div className="section-head">
            <div className="section-eyebrow">Current routes</div>
            <h2>Three ways up.</h2>
            <p>
              Each card's line is the actual elevation profile of the route —
              where you climb, where you drop, and where the air gets thin.
            </p>
          </div>

          {loading ? (
            <p className="tours-loading">Loading routes...</p>
          ) : (
            <TourList tours={tours} onEnquire={handleEnquire} />
          )}
        </div>
      </section>

      <section className="section enquire" id="enquire" ref={enquireRef}>
        <div className="wrap">
          <EnquiryForm
            tours={tours}
            selectedTourId={selectedTourId}
            onSelectedTourChange={setSelectedTourId}
          />
        </div>
      </section>

      <Footer />
    </>
  );
}

export default App;
