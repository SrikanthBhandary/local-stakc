function ElevationChart({ elevation }) {
  const w = 260, h = 90, padX = 10, padY = 16;
  const values = elevation.map(p => p.m);
  const min = Math.min(...values);
  const max = Math.max(...values);
  const range = max - min || 1;
  const stepX = (w - padX * 2) / (elevation.length - 1);

  const points = elevation.map((p, i) => {
    const x = padX + i * stepX;
    const y = padY + (h - padY * 2) * (1 - (p.m - min) / range);
    return { x, y };
  });

  const peakIndex = values.indexOf(max);
  const peak = elevation[peakIndex];
  const linePoints = points.map(pt => `${pt.x},${pt.y}`).join(' ');
  const areaPoints = `${padX},${h - padY} ${linePoints} ${w - padX},${h - padY}`;

  return (
    <div>
      <div className="elevation-label">Elevation profile</div>
      <svg className="elevation-svg" viewBox={`0 0 ${w} ${h}`} xmlns="http://www.w3.org/2000/svg">
        <polygon points={areaPoints} fill="#3e5c76" opacity="0.08" />
        <polyline points={linePoints} fill="none" stroke="#3e5c76" strokeWidth="1.6" />
        {points.map((pt, i) => (
          <circle
            key={i}
            cx={pt.x}
            cy={pt.y}
            r={i === peakIndex ? 4 : 2.5}
            fill={i === peakIndex ? '#b25e2e' : '#3e5c76'}
          />
        ))}
      </svg>
      <div className="elevation-peak">
        Highest point: {peak.m.toLocaleString()}m — {peak.label}
      </div>
    </div>
  );
}

export default ElevationChart;
