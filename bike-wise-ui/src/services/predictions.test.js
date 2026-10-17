import {describe,it,expect} from 'vitest'
import {getNetworks,getStationOptions,getStationAvailabilityPrediction,getDemoReturnDiscount} from './dataAdapter'
const referenceTime='2026-10-16T16:00:00.000Z',departureTime='2026-10-16T21:00:00.000Z'
const planning={referenceTime,departureTime,valid:true,scheduled:true,usePredictions:true}
describe('arrival-time demo predictions',()=>{
 it('uses each pickup walk and each return ride, not one departure timestamp',()=>{
   const pickups=getStationOptions('jersey','rent',null,planning)
   for(const station of pickups)expect(Date.parse(station.targetTime)-Date.parse(departureTime)).toBe(station.walkingMinutes*60000)
   const selected=pickups.find(s=>s.id==='jersey-demo-2')
   expect(selected.targetTime).toBe('2026-10-16T21:06:00.000Z')
   const returns=getStationOptions('jersey','return',null,{...planning,rideStartTime:selected.targetTime})
   for(const station of returns){expect(Date.parse(station.targetTime)-Date.parse(selected.targetTime)).toBe(station.ridingMinutes*60000);expect(station.targetTime).not.toBe(departureTime)}
   expect(new Set(returns.map(s=>s.targetTime)).size).toBeGreaterThan(1)
 })
 it('uses a direct or adjusted return time as the exact dock arrival',()=>{
   const time='2026-10-17T00:30:00.000Z'
   for(const station of getStationOptions('tampa','return',null,{...planning,returnTargetTime:time}))expect(station.targetTime).toBe(time)
 })
 it('is deterministic, capacity-consistent and separate from current inventories',()=>{
   for(const network of getNetworks())for(let snapshot=0;snapshot<3;snapshot++)for(const mode of ['rent','return'])for(let hour=0;hour<24;hour++){
     const time=new Date(Date.parse(departureTime)+hour*3600000).toISOString()
     const result=getStationAvailabilityPrediction(network.id,`${network.id}-demo-1`,time,mode,{referenceTime,snapshot})
     expect(result).toEqual(getStationAvailabilityPrediction(network.id,`${network.id}-demo-1`,time,mode,{referenceTime,snapshot}))
     expect(result.status).toBe('ok');expect(result.predictionSource).toBe('mock')
     expect(result.currentAvailableBikes+result.currentFreeDocks).toBe(result.capacity)
     expect(result.predictedAvailableBikes+result.predictedFreeDocks).toBe(result.capacity)
     expect(result.predictedAvailableBikes).toBeGreaterThanOrEqual(0);expect(result.predictedFreeDocks).toBeGreaterThanOrEqual(0)
   }
 })
 it('keeps a prediction requested exactly now equal to the current snapshot',()=>{
   const result=getStationAvailabilityPrediction('jersey','jersey-demo-1',referenceTime,'return',{referenceTime,snapshot:1})
   expect(result.predictedAvailableBikes).toBe(result.currentAvailableBikes)
   expect(result.predictedFreeDocks).toBe(result.currentFreeDocks)
 })
 it('updates the curated recommendations and forecasts when time changes while preserving IDs',()=>{
   const a=getStationOptions('jersey','rent',null,planning)
   const b=getStationOptions('jersey','rent',null,{...planning,departureTime:'2026-10-16T21:20:00.000Z'})
   expect(a.slice(0,5).map(s=>s.id)).not.toEqual(b.slice(0,5).map(s=>s.id))
   expect(a.find(s=>s.id==='jersey-demo-1').predictedBikes).not.toBe(b.find(s=>s.id==='jersey-demo-1').predictedBikes)
   expect(a.map(s=>s.id).sort()).toEqual(b.map(s=>s.id).sort())
 })
 it('returns explicit errors and no invented forecast for unsupported input',()=>{
   for(const [id,time,mode,error] of [['unknown',departureTime,'rent','unknown_station'],['jersey-demo-1','2026-10-17T17:00','rent','invalid_time'],['jersey-demo-1','2026-02-30T12:00:00Z','rent','invalid_time'],['jersey-demo-1','2026-10-15T00:00:00Z','rent','past_time'],['jersey-demo-1','2028-10-16T21:00:00Z','rent','unsupported_horizon'],['jersey-demo-1',departureTime,'invalid','invalid_mode']]){
     const prediction=getStationAvailabilityPrediction('jersey',id,time,mode,{referenceTime})
     expect(prediction.error).toBe(error);expect(prediction.predictedAvailableBikes).toBeNull()
   }
 })
 it('keeps the agreed discount rule on the displayed rider rank, without network rank claims',()=>{
   for(const station of getStationOptions('milwaukee','return',null,{...planning,returnTargetTime:departureTime})){
     expect(station.discountPercent).toBe(getDemoReturnDiscount(station.riderConvenienceRank));expect(station.discountPercent).toBeLessThanOrEqual(20);expect(station.networkOptimizationRank).toBeNull()
   }
 })
})
