function Hero() {
  return (
    <div className="hero">
      <div className="wrap">
        <nav className="hero-nav">
          <span className="mark">High Passes</span>
          <a href="#tours">Routes</a>
        </nav>
        <div className="hero-eyebrow">Ladakh &amp; Manali · small-group overland journeys</div>
        <h1>Where the road runs out of <em>oxygen.</em></h1>
        <p className="lede">
          Cold deserts, monastery passes, and valleys that don't make it onto
          postcards. Every route below is run by drivers and guides who live
          along it.
        </p>
        <div className="hero-actions">
          <a href="#tours" className="btn btn-primary">See the routes</a>
          <a href="#enquire" className="btn btn-ghost">Send an enquiry</a>
        </div>
      </div>
      <svg className="ridgeline" viewBox="0 0 1200 140" preserveAspectRatio="none" xmlns="http://www.w3.org/2000/svg">
        <polygon points="0,140 0,90 120,60 260,95 380,40 520,80 650,30 790,75 920,50 1040,95 1200,70 1200,140" fill="#1a2530" />
        <polygon points="0,140 0,110 150,85 300,115 450,75 600,105 760,65 900,100 1050,80 1200,105 1200,140" fill="#25384a" opacity="0.85" />
      </svg>
    </div>
  );
}

export default Hero;
