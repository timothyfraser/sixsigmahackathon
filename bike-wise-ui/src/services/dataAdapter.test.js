import {describe,it,expect} from 'vitest'
import {getNetworks,getStations,getPickupRecommendations,getReturnRecommendations,getStationDetails,getTripSummary,getDemoReturnDiscount,getStationOptions} from './dataAdapter'
describe('UI mock adapter',()=>{
 it('provides consistent inventory in every network and replay snapshot',()=>{for(const n of getNetworks())for(let tick=0;tick<3;tick++){const stations=getStations(n.id,tick);expect(stations).toHaveLength(8);for(const s of stations){expect(s.availableBikes+s.freeDocks).toBe(s.capacity);expect(s.predictedBikes+s.predictedFreeDocks).toBe(s.capacity);expect(s.availableBikes).toBeGreaterThanOrEqual(0);expect(s.freeDocks).toBeGreaterThanOrEqual(0);expect(Number.isFinite(s.lat)).toBe(true);expect(getStationDetails(n.id,s.id,tick)).toEqual(s)}}})
 it('returns five distinct curated choices with different pickup and return order',()=>{const p=getPickupRecommendations('jersey'),r=getReturnRecommendations('jersey');expect(new Set(p.map(s=>s.id)).size).toBe(5);expect(r.map(s=>s.id)).not.toEqual(p.map(s=>s.id));expect(r.filter(s=>s.communityImpact).every(s=>s.availableBikes<5)).toBe(true)})
 it('replay changes counts and keeps recommendations aligned with station details',()=>{expect(getStations('jersey',0)).not.toEqual(getStations('jersey',1));for(const r of getReturnRecommendations('milwaukee',null,null,2))expect(r.freeDocks).toBe(getStationDetails('milwaukee',r.id,2).freeDocks)})
 it('handles invalid networks without fabricating stations',()=>expect(getStations('unknown')).toEqual([]))
 it('summarizes full and direct journeys',()=>{const p=getPickupRecommendations('jersey')[0],r=getReturnRecommendations('jersey')[0];expect(getTripSummary({pickup:p,returnStation:r}).totalMinutes).toBe(p.walkingMinutes+r.walkingMinutes+r.ridingMinutes);expect(getTripSummary({direct:true,returnStation:r}).pickup).toBeUndefined();expect(getTripSummary({direct:true,returnStation:r}).totalMinutes).toBe(r.walkingMinutes+r.ridingMinutes)})
})

describe('BikeSmart additional stations and demo incentives', () => {
 it('maps return ranks to capped demo discounts and handles missing ranks', () => {
   expect([1,2,3,4,5,6,7,8,100].map(getDemoReturnDiscount)).toEqual([0,5,10,15,20,20,20,20,20])
   for (const rank of [undefined,null,0,-2,1.5,NaN,Infinity]) expect(getDemoReturnDiscount(rank)).toBe(0)
 })
 it('keeps all eight options selectable with exactly five recommended', () => {
   for (const network of getNetworks()) for (const mode of ['rent','return']) for (let tick=0;tick<3;tick++) {
     const options=getStationOptions(network.id,mode,network.places[0],null,tick)
     expect(options).toHaveLength(8)
     expect(options.filter(s=>s.recommended)).toHaveLength(5)
     expect(new Set(options.map(s=>s.id)).size).toBe(8)
     expect(options.slice(5).every(s=>s.availableBikes>0&&s.freeDocks>0)).toBe(true)
     for (const station of options) {
       expect(station.availableBikes).toBe(getStationDetails(network.id,station.id,tick).availableBikes)
       expect(station.discountPercent).toBe(mode==='rent'?null:getDemoReturnDiscount(station.rank))
     }
   }
 })
 it('carries an outside-the-top-five choice and its incentive into summary', () => {
   const pickup=getStationOptions('jersey','rent')[6]
   const returnStation=getStationOptions('jersey','return')[7]
   const summary=getTripSummary({pickup,returnStation})
   expect(summary.pickup.id).toBe(pickup.id)
   expect(summary.returnStation.id).toBe(returnStation.id)
   expect(summary.discountPercent).toBe(20)
   expect(summary.discountLabel).toBe('20% discount')
   expect(summary.incentiveSource).toBe('demo-rank-policy')
 })
 it('assigns discounts from current return rank when the destination order changes', () => {
   const first=getReturnRecommendations('jersey')[0]
   const reordered=getReturnRecommendations('jersey',{name:'Pearl Gardens'})
   expect(reordered.find(s=>s.id===first.id).discountPercent).toBe(20)
   expect(reordered[0].discountPercent).toBe(0)
   expect(getStationOptions('missing','return')).toEqual([])
 })
})

describe('Tampa simulated network',()=>{
 it('uses the approved three UI networks and explicit Tampa station coordinates',()=>{
   expect(getNetworks().map(network=>network.id)).toEqual(['jersey','milwaukee','tampa'])
   const network=getNetworks().find(network=>network.id==='tampa')
   const stations=getStations('tampa')
   expect(network.name).toBe('Tampa')
   expect(stations).toHaveLength(8)
   stations.forEach((station,index)=>{
     expect([station.lat,station.lng]).toEqual(network.stationCoordinates[index])
     expect(station.lat).toBeGreaterThan(27.94)
     expect(station.lat).toBeLessThan(27.98)
     expect(station.lng).toBeGreaterThan(-82.47)
     expect(station.lng).toBeLessThan(-82.43)
     expect(station.id).toMatch(/^tampa-demo-/)
   })
 })
})
