// Resolve network wall times explicitly through Intl's IANA timezone database.
// Never pass a datetime-local value directly to new Date() (browser timezone).
export function localDateTime(instant, timeZone) {
  const parts = new Intl.DateTimeFormat('en-CA', {timeZone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).formatToParts(new Date(instant))
  const p = Object.fromEntries(parts.map(part=>[part.type,part.value]))
  return `${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}`
}
export function formatNetworkTime(instant, timeZone, withDate = true) {
  if (!instant || !Number.isFinite(Date.parse(instant))) return 'Time unavailable'
  return new Intl.DateTimeFormat('en-US',{timeZone,...(withDate?{month:'short',day:'numeric'}:{}),hour:'numeric',minute:'2-digit',timeZoneName:'short'}).format(new Date(instant))
}
export function addMinutes(instant, minutes) {
  return new Date(Date.parse(instant)+minutes*60000).toISOString()
}
export function resolveNetworkTime(value, timeZone, occurrence = '', referenceTime = new Date().toISOString()) {
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(value)) return {status:'invalid',message:'Choose a complete date and time.'}
  const naive = Date.parse(`${value}:00Z`)
  if (!Number.isFinite(naive) || new Date(naive).toISOString().slice(0,16)!==value) return {status:'invalid',message:'Choose a valid calendar date and time.'}
  // Probe offsets around the wall date. Matching candidates identify normal,
  // skipped (spring) and repeated (fall) local times without silent coercion.
  const offsets = new Set()
  for (let hours=-36;hours<=36;hours+=6) {
    const sample=naive+hours*3600000
    offsets.add(Date.parse(`${localDateTime(sample,timeZone)}:00Z`)-sample)
  }
  const candidates=[...offsets].map(offset=>new Date(naive-offset).toISOString()).filter(time=>localDateTime(time,timeZone)===value).sort()
  if (!candidates.length) return {status:'nonexistent',message:'This local time does not exist because clocks move forward. Choose another time.'}
  if (candidates.length>1 && !['earlier','later'].includes(occurrence)) return {status:'ambiguous',candidates,message:'This time occurs twice when clocks move back. Choose the first or second occurrence.'}
  const targetTime=candidates[occurrence==='later'?candidates.length-1:0]
  if (Date.parse(targetTime)<Date.parse(referenceTime)) return {status:'past',candidates,message:'Choose a time at or after the simulated planning clock.'}
  if (Date.parse(targetTime)>Date.parse(referenceTime)+365*86400000) return {status:'unsupported',candidates,message:'Demo predictions support times up to 365 days ahead.'}
  return {status:'ok',targetTime,candidates}
}
