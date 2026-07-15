package main

import "strings"

const geohashBase32 = "0123456789bcdefghjkmnpqrstuvwxyz"

// geohashEncode returns a base32 geohash string of the given length for a
// lat/lng pair. Shorter strings = bigger cells (precision 6 ≈ 0.6km,
// precision 4 ≈ 20km). Store this alongside each enquiry's lat/lng so it can
// be queried via the GSI without a full table scan.
func geohashEncode(lat, lng float64, precision int) string {
	latRange := [2]float64{-90, 90}
	lngRange := [2]float64{-180, 180}

	var sb strings.Builder
	even := true
	bit := 0
	ch := 0

	for sb.Len() < precision {
		if even {
			mid := (lngRange[0] + lngRange[1]) / 2
			if lng > mid {
				ch |= 1 << uint(4-bit)
				lngRange[0] = mid
			} else {
				lngRange[1] = mid
			}
		} else {
			mid := (latRange[0] + latRange[1]) / 2
			if lat > mid {
				ch |= 1 << uint(4-bit)
				latRange[0] = mid
			} else {
				latRange[1] = mid
			}
		}
		even = !even

		if bit < 4 {
			bit++
		} else {
			sb.WriteByte(geohashBase32[ch])
			bit = 0
			ch = 0
		}
	}

	return sb.String()
}

// geohashDecode returns the center point and half-width/half-height (in
// degrees) of the bounding box for a geohash string.
func geohashDecode(hash string) (lat, lng, latErr, lngErr float64) {
	latRange := [2]float64{-90, 90}
	lngRange := [2]float64{-180, 180}
	even := true

	for i := 0; i < len(hash); i++ {
		cd := strings.IndexByte(geohashBase32, hash[i])
		if cd < 0 {
			continue
		}
		for j := 4; j >= 0; j-- {
			bit := (cd >> uint(j)) & 1
			if even {
				mid := (lngRange[0] + lngRange[1]) / 2
				if bit == 1 {
					lngRange[0] = mid
				} else {
					lngRange[1] = mid
				}
			} else {
				mid := (latRange[0] + latRange[1]) / 2
				if bit == 1 {
					latRange[0] = mid
				} else {
					latRange[1] = mid
				}
			}
			even = !even
		}
	}

	lat = (latRange[0] + latRange[1]) / 2
	lng = (lngRange[0] + lngRange[1]) / 2
	latErr = (latRange[1] - latRange[0]) / 2
	lngErr = (lngRange[1] - lngRange[0]) / 2
	return
}

// geohashNeighbors returns the (up to) 8 geohash cells surrounding the given
// one at the same precision. A proximity search should query the center cell
// plus all of these, then filter results by exact haversine distance, since
// two points close together can fall either side of a cell boundary.
func geohashNeighbors(hash string) []string {
	lat, lng, latErr, lngErr := geohashDecode(hash)
	precision := len(hash)

	var neighbors []string
	for _, dLat := range []float64{-1, 0, 1} {
		for _, dLng := range []float64{-1, 0, 1} {
			if dLat == 0 && dLng == 0 {
				continue
			}
			nLat := lat + dLat*latErr*2
			nLng := lng + dLng*lngErr*2

			if nLat > 90 {
				nLat = 90
			}
			if nLat < -90 {
				nLat = -90
			}
			for nLng > 180 {
				nLng -= 360
			}
			for nLng < -180 {
				nLng += 360
			}

			neighbors = append(neighbors, geohashEncode(nLat, nLng, precision))
		}
	}
	return neighbors
}
