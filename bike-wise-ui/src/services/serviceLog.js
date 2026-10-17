import {resolveNetworkTime} from './networkTime'
export function resolveServiceTime(value,timeZone,occurrence=''){
 const naive=Date.parse(`${value}:00Z`)
 if(!Number.isFinite(naive))return{status:'invalid',message:'Choose a complete service date and time.'}
 // Resolve the wall clock with the existing DST-aware helper. The relative
 // reference only bypasses rider departure limits; service events can be historical.
 return resolveNetworkTime(value,timeZone,occurrence,new Date(naive-2*86400000).toISOString())
}
export function parseServiceCsv(text){
 const input=text.replace(/^\uFEFF/,''),rows=[];let row=[],field='',quoted=false
 for(let i=0;i<input.length;i++){
  const c=input[i]
  if(quoted){if(c==='"'&&input[i+1]==='"'){field+='"';i++}else if(c==='"')quoted=false;else field+=c}
  else if(c==='"'){if(field)throw new Error('Invalid CSV quoting.');quoted=true}
  else if(c===','){row.push(field);field=''}
  else if(c==='\n'||c==='\r'){if(c==='\r'&&input[i+1]==='\n')i++;row.push(field);if(row.some(v=>v.trim()))rows.push(row);row=[];field=''}
  else field+=c
 }
 if(quoted)throw new Error('The CSV has an unclosed quoted field.')
 row.push(field);if(row.some(v=>v.trim()))rows.push(row)
 const headers=(rows.shift()??[]).map(v=>v.trim())
 if(!headers.includes('BIKEID')||!headers.includes('service_time')||new Set(headers).size!==headers.length)throw new Error('CSV needs unique BIKEID and service_time columns; note and city are optional.')
 if(!rows.length||rows.length>500)throw new Error('Import 1 to 500 service records at a time.')
 return rows.map((values,index)=>{
  if(values.length!==headers.length)throw new Error(`CSV row ${index+2} has an unexpected number of columns.`)
  const entry=Object.fromEntries(headers.map((header,i)=>[header,values[i].trim()]))
  return{BIKEID:entry.BIKEID,service_time:entry.service_time,...(entry.note?{note:entry.note}:{}),...(entry.city?{city:entry.city}:{})}
 })
}
