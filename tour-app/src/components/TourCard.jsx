import ElevationChart from './ElevationChart.jsx';

function TourCard({ tour, onEnquire }) {
  return (
    <div className="tour-card">
      <div className="tour-info">
        <h3>{tour.name}</h3>
        <div className="tour-meta">
          <span>{tour.region}</span>
          <span>{tour.duration}</span>
          <span>{tour.groupSize}</span>
        </div>
        <p className="tour-desc">{tour.desc}</p>
        <ul className="tour-highlights">
          {tour.highlights.map((h, i) => (
            <li key={i}>{h}</li>
          ))}
        </ul>
        <div className="tour-footer">
          <div className="tour-price">
            <strong>{tour.price}</strong>
            {tour.priceNote}
          </div>
          <button className="btn btn-outline" onClick={() => onEnquire(tour.id)}>
            Enquire for this route
          </button>
        </div>
      </div>
      <div className="elevation-panel">
        <ElevationChart elevation={tour.elevation} />
      </div>
    </div>
  );
}

export default TourCard;
