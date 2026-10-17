import { networks, offsets, snapshots, predicted } from '../data/mockStations'
import {addMinutes, formatNetworkTime} from './networkTime'

// Synchronous UI fixtures. Replace this boundary with an approved API client
// plus loading/error handling when Ally and the R team define their contract.
export function getNetworks() {
  return networks.map(network => ({ ...network }))
}

export function getStations(networkId, snapshot = 0) {
  const network = networks.find(network => network.id === networkId)
  if (!network) return []
  const tick = ((snapshot % 3) + 3) % 3
  return network.stations.map((name, index) => ({
    id: `${networkId}-demo-${index + 1}`,
    name: `${name} · demo`,
    lat: network.stationCoordinates?.[index][0] ?? network.center[0] + offsets[index][0],
    lng: network.stationCoordinates?.[index][1] ?? network.center[1] + offsets[index][1],
    capacity: 15,
    availableBikes: snapshots[tick][index],
    freeDocks: 15 - snapshots[tick][index],
    predictedBikes: predicted[tick][index],
    predictedFreeDocks: 15 - predicted[tick][index],
    communityImpact: index === 1 || index === 3 ? 'Helps restock this neighborhood' : null,
  }))
}

// Demo policy ONLY. Ally's optimization output should replace this rank-based
// fallback here, not in cards, map popups or the summary. No credit is issued.
export function getDemoReturnDiscount(rank) {
  if (!Number.isInteger(rank) || rank < 1) return 0
  return Math.min((rank - 1) * 5, 20)
}

const walking = [3, 6, 5, 9, 8, 11, 12, 10]
const riding = [7, 9, 6, 11, 8, 13, 14, 12]

// All selectable options, including the top five. Each carries the same schema
// so an outside-the-top-five selection can use the entire trip workflow.
export function getStationAvailabilityPrediction(networkId, stationId, targetTime, mode, options = {}) {
  const station = getStationDetails(networkId, stationId, options.snapshot ?? 0)
  const referenceTime = options.referenceTime ?? new Date().toISOString()
  const base = {networkId, stationId, requestedPredictionTimestamp: targetTime ?? null,
    currentAvailableBikes: station?.availableBikes ?? null, currentFreeDocks: station?.freeDocks ?? null,
    capacity: station?.capacity ?? null, predictedAvailableBikes: null, predictedFreeDocks: null,
    predictionSource: 'mock', predictionLabel: 'DEMO PREDICTION', status: 'error', availabilityStatus: 'Prediction unavailable', error: null}
  if (!station) return {...base,error:'unknown_station'}
  if (!['rent','return'].includes(mode)) return {...base,error:'invalid_mode'}
  if (typeof targetTime!=='string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,3})?)?(Z|[+-]\d{2}:\d{2})$/.test(targetTime) || !Number.isFinite(Date.parse(targetTime)) || new Date(Date.parse(`${targetTime.slice(0,16)}:00Z`)).toISOString().slice(0,16)!==targetTime.slice(0,16)) return {...base,error:'invalid_time'}
  const delta=Date.parse(targetTime)-Date.parse(referenceTime)
  if (!Number.isFinite(delta)||delta<0) return {...base,status:'unsupported',error:'past_time'}
  if (delta>365*86400000) return {...base,status:'unsupported',error:'unsupported_horizon'}
  // Deterministic illustrative buckets, not a forecast or production model.
  // Ally: replace this fixture block with the approved prediction response.
  const seed=[...`${networkId}/${stationId}`].reduce((n,c)=>n+c.charCodeAt(0),0)
  const bucket=Math.floor(Date.parse(targetTime)/300000)
  const predictedAvailableBikes=delta===0?station.availableBikes:((bucket+seed*3+(options.snapshot??0)*2)%16+16)%16
  const predictedFreeDocks=station.capacity-predictedAvailableBikes
  const relevant=mode==='rent'?predictedAvailableBikes:predictedFreeDocks
  return {...base,requestedPredictionTimestamp:new Date(targetTime).toISOString(),predictedAvailableBikes,predictedFreeDocks,status:'ok',availabilityStatus:relevant===0?(mode==='rent'?'No bikes expected':'No docks expected'):relevant<4?'Limited availability expected':mode==='rent'?'Bikes expected':'Docks expected'}
}

export function getStationOptions(networkId, mode, point, planning = null, snapshot = 0) {
  const stations = getStations(networkId, snapshot)
  if (!stations.length) return []
  const network = networks.find(n=>n.id===networkId)
  const context = planning && typeof planning==='object' ? planning : null
  const topOrder = mode === 'rent' ? [0, 2, 1, 4, 3] : [1, 3, 0, 4, 2]
  const placeShift = point?.name?.includes('Park') || point?.name?.includes('Gardens')
  const orderedTop = placeShift ? [...topOrder.slice(1), topOrder[0]] : topOrder
  let order = [...orderedTop, 5, 6, 7]
  // A rotating fixture order demonstrates time-sensitive backend rankings.
  // It is not an optimization. Network optimization rank is intentionally null.
  if (context?.scheduled && context?.departureTime) {
    const shift=Math.floor(Date.parse(context.departureTime)/900000)%order.length
    order=[...order.slice(shift),...order.slice(0,shift)]
  }
  return order.map((index, position) => {
    const station = stations[index], rank = position + 1
    let targetTime = null
    if (context?.valid !== false) {
      if (mode==='rent' && context?.departureTime) targetTime=addMinutes(context.departureTime,walking[index])
      if (mode==='return') targetTime=context?.returnTargetTime ?? (context?.rideStartTime?addMinutes(context.rideStartTime,riding[index]):null)
    }
    const prediction=context?getStationAvailabilityPrediction(networkId,station.id,targetTime,mode,{snapshot,referenceTime:context.referenceTime}):null
    const predictedBikes=prediction?prediction.predictedAvailableBikes:station.predictedBikes
    const predictedFreeDocks=prediction?prediction.predictedFreeDocks:station.predictedFreeDocks
    const discountPercent = mode === 'return' ? getDemoReturnDiscount(rank) : null
    return {...station, predictedBikes, predictedFreeDocks, prediction, targetTime,
      arrivalLabel:targetTime?formatNetworkTime(targetTime,network.timeZone):null,
      usePredictions:context?.usePredictions??false, predictionValid:prediction?prediction.status==='ok':true,
      rank, riderConvenienceRank:rank, networkOptimizationRank:null, rankingSource:'curated-demo', recommended:rank<=5,
      walkingMinutes:walking[index], walkingMeters:walking[index]*75, ridingMinutes:riding[index], arrivalTime:targetTime,
      discountPercent, discountLabel:mode==='return'?discountPercent?`${discountPercent}% discount`:'No discount':null,
      incentiveSource:mode==='return'?'demo-rank-policy':null,
      label:rank>5?'Other available station':rank===1?'Best overall':index===0?'Closest':rank===2?'Good alternative':'Another option',
      status:prediction?prediction.availabilityStatus:mode==='rent'?station.availableBikes===0?'No bikes now':predictedBikes<4?'Limited bikes expected':'Bikes expected':station.freeDocks===0?'No docks now':predictedFreeDocks<3?'Limited docks expected':'Docks expected',
      explanation:rank>5?'An additional demo station you can choose from the map.':mode==='rent'?'Illustrative balance of walking time and expected bikes.':station.communityImpact?'A little farther, with room to help refill this area.':'A convenient example dock near your destination.',
    }
  })
}

export function getPickupRecommendations(networkId, origin, planning = null, snapshot = 0) {
  return getStationOptions(networkId, 'rent', origin, planning, snapshot).filter(station => station.recommended)
}
export function getReturnRecommendations(networkId, destination, planning = null, snapshot = 0) {
  return getStationOptions(networkId, 'return', destination, planning, snapshot).filter(station => station.recommended)
}
export function getStationDetails(networkId, stationId, snapshot = 0) {
  return getStations(networkId, snapshot).find(station => station.id === stationId) ?? null
}
export function getTripSummary({ origin, destination, pickup, returnStation, direct = false }) {
  const walkingMinutes = (direct ? 0 : pickup?.walkingMinutes ?? 0) + (returnStation?.walkingMinutes ?? 0)
  const cyclingMinutes = returnStation?.ridingMinutes ?? 0
  return {
    origin, destination, pickup, returnStation, direct, walkingMinutes, cyclingMinutes,
    totalMinutes: walkingMinutes + cyclingMinutes,
    communityImpact: returnStation?.communityImpact ?? null,
    discountPercent: returnStation?.discountPercent ?? 0,
    discountLabel: returnStation?.discountLabel ?? 'No discount',
    incentiveSource: returnStation?.incentiveSource ?? null,
    pickupTime: pickup?.targetTime ?? null, returnTime: returnStation?.targetTime ?? null,
  }
}
