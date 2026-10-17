import {expect,it} from 'vitest'
import {parseServiceCsv,resolveServiceTime} from './serviceLog'
it('imports package service columns with quoted notes, CRLF and BOM',()=>{
 expect(parseServiceCsv('\uFEFFBIKEID,service_time,note\r\nA,2026-10-16T03:55:00Z,"Tire, chain"\r\n')).toEqual([{BIKEID:'A',service_time:'2026-10-16T03:55:00Z',note:'Tire, chain'}])
 expect(parseServiceCsv('BIKEID,service_time\nA,2026-10-16T03:55:00Z')).toHaveLength(1)
 expect(()=>parseServiceCsv('bike,time\nA,2026')).toThrow(/BIKEID/)
 expect(()=>parseServiceCsv('BIKEID,service_time\n')).toThrow(/1 to 500/)
 expect(()=>parseServiceCsv('BIKEID,service_time,note\nA,2026,"oops')).toThrow(/unclosed/)
})
it('resolves service times in city timezones without rejecting past events',()=>{
 expect(resolveServiceTime('2026-10-15T23:55','America/New_York').targetTime).toBe('2026-10-16T03:55:00.000Z')
 expect(resolveServiceTime('2026-10-15T22:55','America/Chicago').targetTime).toBe('2026-10-16T03:55:00.000Z')
 expect(resolveServiceTime('2026-03-08T02:30','America/New_York').status).toBe('nonexistent')
 expect(resolveServiceTime('2026-11-01T01:30','America/New_York').status).toBe('ambiguous')
})
