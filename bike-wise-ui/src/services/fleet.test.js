import {describe,it,expect} from 'vitest'
import {fleetSnapshot,stationInventoryMetrics,singleBikeState,routePoint,routeTrail} from './fleet'
const day={observed_steps:[1,2,3],dock_mat:[[0,2],[30,1],[15,0]],bike_docks:[[-1,1],[0,1],[0,-1]]}
describe('fleet_viz snapshot and inspector behavior',()=>{
 it('counts actual transit, empty and full snapshots',()=>{
  expect(fleetSnapshot(day,1)).toMatchObject({inTransit:1,empty:1,full:0})
  expect(fleetSnapshot(day,2)).toMatchObject({inTransit:0,empty:0,full:1})
  expect(fleetSnapshot(day,4)).toBeNull()
 })
 it('includes zero-inventory bins in daily metrics and ignores unobserved bins',()=>{
  expect(stationInventoryMetrics(day,0)).toEqual({minimum:0,maximum:30,mean:15,emptyMinutes:5,fullMinutes:5,observedMinutes:15})
  expect(stationInventoryMetrics({...day,observed_steps:[2]},0)).toEqual({minimum:30,maximum:30,mean:30,emptyMinutes:0,fullMinutes:5,observedMinutes:5})
  expect(stationInventoryMetrics({...day,observed_steps:[]},0)).toBeNull()
 })
 it('uses raw snapshots for bike location even if no inferred trip exists',()=>{
  expect(singleBikeState(day,[],0,1)).toEqual({dock:-1,active:null,completed:0,total:0})
  expect(singleBikeState(day,[],0,2).dock).toBe(0)
 })
 it('interpolates both legs through the same route corner as fleet_viz',()=>{
  const route={lats:[0,0,10],lons:[0,10,10],n:3,w1:.5}
  expect(routePoint(route,.25)).toEqual([0,5])
  expect(routePoint(route,.75)).toEqual([5,10])
  expect(routeTrail(route,.75)).toEqual([[0,0],[0,10],[5,10]])
  expect(routePoint(route,1)).toEqual([10,10])
  expect(routePoint({lats:[0,10],lons:[0,10],n:2,w1:1},.5)).toEqual([5,5])
 })
 it('follows every street vertex and interpolates by cumulative distance',()=>{
  const route={lats:[0,0,2,2,4],lons:[0,1,1,4,4],n:5,cumulative:[0,.1,.3,.7,1]}
  expect(routePoint(route,.2)[0]).toBeCloseTo(1)
  expect(routePoint(route,.2)[1]).toBe(1)
  expect(routePoint(route,.5)[0]).toBe(2)
  expect(routePoint(route,.5)[1]).toBeCloseTo(2.5)
  expect(routeTrail(route,.5).slice(0,-1)).toEqual([[0,0],[0,1],[2,1]])
  expect(routeTrail(route,.5).at(-1)[1]).toBeCloseTo(2.5)
  expect(routePoint(route,-1)).toEqual([0,0])
  expect(routePoint(route,2)).toEqual([4,4])
 })

})
