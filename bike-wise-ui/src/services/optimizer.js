import data from '../data/optimizer.json'

export const optimizerCity = id => id === 'jersey' ? 'jersey_city' : id
export const getOptimizerLocations = id => data.locations.filter(row => row.city === optimizerCity(id))
export function getOptimizerOptions(networkId, locationId, mode) {
  const city = optimizerCity(networkId)
  const stations = new Map(data.stations.filter(s => s.city === city).map(s => [s.dockID, s]))
  return data.records.filter(r => r.city === city && r.location_id === locationId && r.mode === (mode === 'rent' ? 'pickup' : mode))
    .map(r => ({...r, ...stations.get(r.dockID)}))
    .sort((a,b) => (a.distance_miles ?? Infinity) - (b.distance_miles ?? Infinity) || a.dockID.localeCompare(b.dockID))
}
export const exclusionReason = reason => ({
  fewer_than_one_projected_bike: 'Fewer than 1 projected bike at arrival',
  fewer_than_one_projected_space: 'Fewer than 1 projected free space at arrival',
  no_route: 'No usable route available',
}[reason] ?? reason ?? 'Projection unavailable')
export const optimizerNumber = (value, decimals = 1) => value == null ? '—' : value.toFixed(decimals)
