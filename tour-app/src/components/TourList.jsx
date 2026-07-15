import TourCard from './TourCard.jsx';

function TourList({ tours, onEnquire }) {
  return (
    <div className="tours-grid">
      {tours.map(tour => (
        <TourCard key={tour.id} tour={tour} onEnquire={onEnquire} />
      ))}
    </div>
  );
}

export default TourList;
