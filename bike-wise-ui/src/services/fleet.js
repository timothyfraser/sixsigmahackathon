// Replay helpers derived from demo/fleet_viz/app.R. Positions follow the demo's
// inferred station-corner routes; inventory and docked states use recorded snapshots.
import {maintenanceRequest} from './maintenance'
const networks=new Map(),days=new Map()
export function clearFleetCache(){networks.clear();days.clear()}
export async function fetchFleetNetwork(city,signal){
 if(networks.has(city))return networks.get(city)
 const value=await maintenanceRequest(`fleet/network?city=${encodeURIComponent(city)}`,{signal})
 networks.set(city,value);return value
}
export async function fetchFleetDay(city,date,signal){
 const key=`${city}/${date}`
 if(days.has(key))return days.get(key)
 const value=await maintenanceRequest(`fleet/day?city=${encodeURIComponent(city)}&date=${encodeURIComponent(date)}`,{signal})
 days.set(key,value)
 // Bound browser memory; old days can be fetched again after scrubbing the calendar.
 if(days.size>6)days.delete(days.keys().next().value)
 return value
}
export function replayTrips(payload){
 const trips=payload.trips
 return Array.from({length:trips.n},(_,i)=>({bike:trips.b_id[i],from:trips.d1[i],to:trips.d2[i],start:trips.start_step[i],end:trips.end_step[i],route:trips.r_idx[i]}))
}
export function fleetSnapshot(day,step,capacity=30){
 const index=Math.round(step)-1
 if(!day.observed_steps.includes(index+1))return null
 const counts=day.dock_mat[index],bikes=day.bike_docks[index]
 return {counts,bikes,inTransit:bikes.filter(dock=>dock===-1).length,
  empty:counts.filter(value=>value===0).length,full:counts.filter(value=>value===capacity).length}
}
export function stationInventoryMetrics(day,station,capacity=30){
 const values=day.observed_steps.map(step=>day.dock_mat[step-1][station])
 if(!values.length)return null
 return {minimum:Math.min(...values),maximum:Math.max(...values),mean:values.reduce((a,b)=>a+b,0)/values.length,
  emptyMinutes:values.filter(value=>value===0).length*5,fullMinutes:values.filter(value=>value===capacity).length*5,
  observedMinutes:values.length*5}
}
export function singleBikeState(day,trips,bike,step){
 const index=Math.round(step)-1,dock=day.bike_docks[index]?.[bike]??-2
 const rides=trips.filter(trip=>trip.bike===bike)
 return {dock,active:rides.find(trip=>trip.start<step&&trip.end>step)??null,
  completed:rides.filter(trip=>trip.end<=step).length,total:rides.length}
}
// Progress follows cumulative street length, so short segments and bends do not
// change the bike's speed. Legacy corner routes are retained only for old fixtures.
function routeFractions(route){return route.cumulative??(route.n===2?[0,1]:[0,route.w1,1])}
function routeSegment(route,progress){
 const p=Math.max(0,Math.min(1,progress)),fractions=routeFractions(route)
 let low=1,high=fractions.length-1
 while(low<high){const middle=(low+high)>>1;if(fractions[middle]<p)low=middle+1;else high=middle}
 return {p,fractions,index:low}
}
export function routePoint(route,progress){
 const {p,fractions,index}=routeSegment(route,progress),a=index-1
 const span=fractions[index]-fractions[a],portion=span?(p-fractions[a])/span:0
 return[route.lats[a]+portion*(route.lats[index]-route.lats[a]),route.lons[a]+portion*(route.lons[index]-route.lons[a])]
}
export function routeTrail(route,progress){
 const {index}=routeSegment(route,progress)
 return [...route.lats.slice(0,index).map((lat,i)=>[lat,route.lons[i]]),routePoint(route,progress)]
}
export const zoneColor=zone=>({office:'#2563eb',residential:'#10b981',retail:'#f59e0b'}[zone?.toLowerCase()]??'#6b7280')
