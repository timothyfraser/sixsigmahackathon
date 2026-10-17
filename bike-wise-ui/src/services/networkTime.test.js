import {describe,it,expect} from 'vitest'
import {resolveNetworkTime,localDateTime,addMinutes,formatNetworkTime} from './networkTime'
const reference='2026-10-16T16:00:00.000Z'
describe('network timezone handling',()=>{
 it('interprets 5 PM in each network timezone rather than the browser timezone',()=>{
   expect(resolveNetworkTime('2026-10-16T17:00','America/New_York','',reference).targetTime).toBe('2026-10-16T21:00:00.000Z')
   expect(resolveNetworkTime('2026-10-16T17:00','America/Chicago','',reference).targetTime).toBe('2026-10-16T22:00:00.000Z')
   expect(localDateTime(reference,'America/New_York')).toBe('2026-10-16T12:00')
   expect(localDateTime(reference,'America/Chicago')).toBe('2026-10-16T11:00')
 })
 it('handles next-day departures and walking across midnight',()=>{
   const depart=resolveNetworkTime('2026-10-16T23:58','America/New_York','',reference).targetTime
   expect(localDateTime(addMinutes(depart,6),'America/New_York')).toBe('2026-10-17T00:04')
   expect(resolveNetworkTime('2026-10-17T08:30','America/New_York','',reference).targetTime).toBe('2026-10-17T12:30:00.000Z')
 })
 it('rejects invalid dates, empty input, past times and unsupported dates',()=>{
   for(const value of ['','2026-02-30T12:00','2026-10-16T25:00'])expect(resolveNetworkTime(value,'America/New_York','',reference).status).toBe('invalid')
   expect(resolveNetworkTime('2026-10-16T08:00','America/New_York','',reference).status).toBe('past')
   expect(resolveNetworkTime('2028-01-01T12:00','America/Chicago','',reference).status).toBe('unsupported')
 })
 it.each(['America/New_York','America/Chicago'])('requires explicit disambiguation for fall-back in %s',zone=>{
   const unresolved=resolveNetworkTime('2026-11-01T01:30',zone,'',reference)
   expect(unresolved.status).toBe('ambiguous');expect(unresolved.candidates).toHaveLength(2)
   const first=resolveNetworkTime('2026-11-01T01:30',zone,'earlier',reference)
   const second=resolveNetworkTime('2026-11-01T01:30',zone,'later',reference)
   expect(Date.parse(second.targetTime)-Date.parse(first.targetTime)).toBe(3600000)
   expect(formatNetworkTime(first.targetTime,zone)).not.toEqual(formatNetworkTime(second.targetTime,zone))
 })
 it('keeps both fall-back choices available when the first occurrence is already past',()=>{
   const now='2026-11-01T05:45:00.000Z'
   const result=resolveNetworkTime('2026-11-01T01:30','America/New_York','earlier',now)
   expect(result.status).toBe('past');expect(result.candidates).toHaveLength(2)
   expect(resolveNetworkTime('2026-11-01T01:30','America/New_York','later',now).status).toBe('ok')
 })
 it.each(['America/New_York','America/Chicago'])('rejects spring-forward nonexistent times in %s',zone=>{
   expect(resolveNetworkTime('2027-03-14T02:30',zone,'',reference).status).toBe('nonexistent')
 })
})
