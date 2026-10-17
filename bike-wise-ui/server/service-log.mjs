import {readFile,writeFile,rename,mkdir} from 'node:fs/promises'
import {createHash} from 'node:crypto'
import {spawn} from 'node:child_process'
import path from 'node:path'

function calculate(root,city,records){
 return new Promise((resolve,reject)=>{
  const child=spawn('Rscript',['--vanilla','tools/bikesmart_service_log.R'],{cwd:root,stdio:['pipe','pipe','pipe']})
  let output=''
  const timeout=setTimeout(()=>{child.kill();reject(new Error('Service-log calculation timed out. Please retry.'))},90000)
  child.stdout.on('data',chunk=>{output+=chunk;if(output.length>5000000)child.kill()});child.stderr.resume()
  child.on('error',()=>{clearTimeout(timeout);reject(new Error('The R maintenance service is unavailable.'))})
  child.on('close',code=>{clearTimeout(timeout);if(code!==0)return reject(new Error('The package could not apply this service log. No records were saved.'));try{resolve(JSON.parse(output))}catch{reject(new Error('Invalid maintenance calculation response.'))}})
  child.stdin.on('error',()=>{});child.stdin.end(JSON.stringify({city,records}))
 })
}
export function createServiceLogStore(root){
 const filename=process.env.MAINTENANCE_SERVICE_LOG_FILE??path.join(root,'bike-wise-ui/server/data/service-log.json')
 const cache=new Map();let transaction=Promise.resolve()
 async function baseline(city){const all=JSON.parse(await readFile(path.join(root,'bike-wise-ui/server/data/maintenance.json'),'utf8'));return all[city]}
 async function read(){
  const all=JSON.parse(await readFile(path.join(root,'bike-wise-ui/server/data/maintenance.json'),'utf8'))
  const seeds=Object.entries(all).flatMap(([city,base])=>(base.service_log??[]).map(row=>{
   const service_time=new Date(row.service_time).toISOString().replace(/\.\d{3}Z$/,'+0000')
   return{...row,city,service_time,id:createHash('sha256').update(`${city}/${row.BIKEID}/${service_time}`).digest('hex').slice(0,24),note:'Team-supplied simulated service record',source:'team_dataset'}
  }))
  let saved=[]
  try{const value=JSON.parse(await readFile(filename,'utf8'));if(!Array.isArray(value.records))throw new Error();saved=value.records}catch(error){if(error.code!=='ENOENT')throw new Error('The service log cannot be read. Existing records were left unchanged.')}
  return [...new Map([...seeds,...saved].map(row=>[row.id,row])).values()]
 }
 async function report(city,records){
  const base=await baseline(city),entries=records.filter(row=>row.city===city)
  if(entries.every(row=>row.source==='team_dataset'))return{...base,service_log_summary:{total:entries.length,effective:entries.filter(row=>Date.parse(row.service_time)<=Date.parse(base.reference_time)).length,pending:entries.filter(row=>Date.parse(row.service_time)>Date.parse(base.reference_time)).length}}
  const key=createHash('sha256').update(JSON.stringify([base,entries])).digest('hex')
  if(cache.get(city)?.key===key)return cache.get(city).value
  const updated=await calculate(root,city,entries)
  const effective=entries.filter(row=>Date.parse(row.service_time)<=Date.parse(base.reference_time)).length
  const value={...base,...updated,
   starting_hours:base.starting_hours.replace('no service log supplied.','service log applied to accumulated ride hours.'),
   service_log_summary:{total:entries.length,effective,pending:entries.length-effective}}
  cache.set(city,{key,value});return value
 }
 async function append(city,incoming,user){
  if(!Array.isArray(incoming)||!incoming.length||incoming.length>500)throw new Error('Supply 1 to 500 service records.')
  const base=await baseline(city),known=new Set((base.service_status??base.service_due).map(row=>row.BIKEID))
  const cleaned=incoming.map((row,index)=>{
   if(typeof row.BIKEID!=='string'||!known.has(row.BIKEID.trim()))throw new Error(`Row ${index+1}: choose a bike in this city.`)
   if(row.city&&row.city!==city&&!(row.city==='jersey'&&city==='jersey_city'))throw new Error(`Row ${index+1}: the record belongs to another city.`)
   const raw=row.service_time
   if(typeof raw!=='string'||!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})$/.test(raw)||!Number.isFinite(Date.parse(raw))||new Date(`${raw.slice(0,10)}T00:00:00Z`).toISOString().slice(0,10)!==raw.slice(0,10))throw new Error(`Row ${index+1}: use an ISO timestamp with seconds and a UTC offset.`)
   if(row.note!=null&&(typeof row.note!=='string'||row.note.length>240))throw new Error(`Row ${index+1}: notes must be at most 240 characters.`)
   const service_time=new Date(raw).toISOString().replace(/\.\d{3}Z$/,'+0000'),BIKEID=row.BIKEID.trim()
   return{id:createHash('sha256').update(`${city}/${BIKEID}/${service_time}`).digest('hex').slice(0,24),city,BIKEID,service_time,note:row.note?.trim()??'',recorded_by:user,recorded_at:new Date().toISOString()}
  })
  const existing=await read(),ids=new Set(existing.map(row=>row.id)),added=cleaned.filter(row=>{if(ids.has(row.id))return false;ids.add(row.id);return true})
  const next=[...existing,...added]
  const analysis=await report(city,next)
  await mkdir(path.dirname(filename),{recursive:true})
  await writeFile(filename+'.tmp',JSON.stringify({version:1,records:next})+'\n')
  await rename(filename+'.tmp',filename)
  return{records:next.filter(row=>row.city===city),added:added.length,report:analysis}
 }
 return{
  async getReport(city){return report(city,await read())},
  async getRecords(city){return(await read()).filter(row=>row.city===city)},
  append(city,records,user){const task=transaction.then(()=>append(city,records,user));transaction=task.catch(()=>{});return task},
 }
}
