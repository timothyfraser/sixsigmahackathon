import {randomBytes,createHash,timingSafeEqual} from 'node:crypto'
import {readFile} from 'node:fs/promises'
import {spawn} from 'node:child_process'
import {fileURLToPath} from 'node:url'
import path from 'node:path'
import {createServiceLogStore} from './service-log.mjs'

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..')
const defaultPasswordDigest='a665a45920422f9d417e4867efdc4fb8a04a1f3fff1fa07e998e86f7f7a27ae3'
const lifetime=8*60*60*1000
const cities=new Set(['jersey_city','milwaukee','tampa'])
const digest=value=>createHash('sha256').update(value).digest()
const safeEqual=(a,b)=>a.length===b.length&&timingSafeEqual(a,b)

function reliability(input){
 return new Promise((resolve,reject)=>{
  const child=spawn('Rscript',['--vanilla','tools/bikesmart_reliability.R'],{cwd:root,stdio:['pipe','pipe','pipe']})
  let output='';let oversized=false
  const timeout=setTimeout(()=>{child.kill();reject(new Error('Analysis timed out. Try again.'))},15000)
  child.stdout.on('data',chunk=>{output+=chunk;if(output.length>1000000){oversized=true;child.kill()}})
  child.stderr.resume()
  child.on('error',()=>{clearTimeout(timeout);reject(new Error('R analysis is unavailable.'))})
  child.on('close',code=>{clearTimeout(timeout);if(code!==0||oversized)return reject(new Error('Check the defect rates and projected bike count.'));try{resolve(JSON.parse(output))}catch{reject(new Error('R returned an invalid response.'))}})
  child.stdin.on('error',()=>{})
  child.stdin.end(JSON.stringify(input))
 })
}
async function body(req,limit=16000){
 if(!req.headers['content-type']?.startsWith('application/json'))throw new Error('JSON input is required.')
 let raw=''
 for await(const chunk of req){raw+=chunk;if(raw.length>limit)throw new Error('Request is too large.')}
 return JSON.parse(raw)
}
export function createMaintenanceApi(){
 const sessions=new Map(),attempts=new Map()
 const serviceLog=createServiceLogStore(root)
 const email=process.env.MAINTENANCE_EMAIL??'maintenance@cornell.edu'
 const passwordDigest=process.env.MAINTENANCE_PASSWORD_SHA256??defaultPasswordDigest
 if(!/^[a-f0-9]{64}$/i.test(passwordDigest))throw new Error('Invalid maintenance password digest configuration.')
 const expected=Buffer.from(passwordDigest,'hex')
 return async function maintenanceApi(req,res,next){
  const url=new URL(req.url,'http://localhost')
  if(!url.pathname.startsWith('/api/maintenance/'))return next()
  res.setHeader('Cache-Control','no-store');res.setHeader('X-Content-Type-Options','nosniff')
  const send=(status,data)=>{res.statusCode=status;res.setHeader('Content-Type','application/json');res.end(JSON.stringify(data))}
  const cookie=(req.headers.cookie??'').split(';').map(c=>c.trim()).find(c=>c.startsWith('maintenance_session='))?.slice('maintenance_session='.length)
  let session=sessions.get(cookie)
  if(session&&session.expires<=Date.now()){sessions.delete(cookie);session=null}
  if(req.method==='POST'&&req.headers.origin){
   let origin
   try{origin=new URL(req.headers.origin)}catch{return send(403,{error:'Invalid request origin.'})}
   if(origin.host!==req.headers.host)return send(403,{error:'Invalid request origin.'})
  }
  try{
   if(url.pathname==='/api/maintenance/session'&&req.method==='GET')return send(200,{authenticated:!!session,email:session?email:null})
   if(url.pathname==='/api/maintenance/login'&&req.method==='POST'){
    const key=req.socket.remoteAddress??'local',now=Date.now()
    const attempt=attempts.get(key)
    if(attempt&&attempt.expires>now&&attempt.count>=8)return send(429,{error:'Too many attempts. Try again later.'})
    const input=await body(req)
    const valid=typeof input.email==='string'&&typeof input.password==='string'&&
     input.email.trim().toLowerCase()===email.toLowerCase()&&safeEqual(digest(input.password),expected)
    if(!valid){attempts.set(key,{count:attempt&&attempt.expires>now?attempt.count+1:1,expires:now+15*60000});return send(401,{error:'Email or password is incorrect.'})}
    attempts.delete(key)
    if(cookie)sessions.delete(cookie)
    const token=randomBytes(32).toString('hex')
    sessions.set(token,{expires:now+lifetime})
    // A TLS deployment proxy can opt into Secure cookies with MAINTENANCE_COOKIE_SECURE=true.
    const secure=req.socket.encrypted||process.env.MAINTENANCE_COOKIE_SECURE==='true'?'; Secure':''
    res.setHeader('Set-Cookie',`maintenance_session=${token}; HttpOnly; SameSite=Strict; Path=/api/maintenance; Max-Age=28800${secure}`)
    return send(200,{authenticated:true,email})
   }
   if(!session)return send(401,{error:'Please sign in to maintenance.'})
   if(url.pathname==='/api/maintenance/logout'&&req.method==='POST'){
    sessions.delete(cookie);res.setHeader('Set-Cookie','maintenance_session=; HttpOnly; SameSite=Strict; Path=/api/maintenance; Max-Age=0')
    return send(200,{authenticated:false})
   }
   if(['/api/maintenance/fleet/network','/api/maintenance/fleet/day'].includes(url.pathname)&&req.method==='GET'){
    const city=url.searchParams.get('city')==='jersey'?'jersey_city':url.searchParams.get('city')
    if(!cities.has(city))return send(400,{error:'Choose a supported city.'})
    const day=url.searchParams.get('date')
    const network=url.pathname.endsWith('/network')
    if(!network&&(!day||!/^\d{4}-\d{2}-\d{2}$/.test(day)))return send(400,{error:'Choose an available replay date.'})
    let data
    try{data=await readFile(path.join(root,'bike-wise-ui/server/data/fleet',city,`${network?'network':day}.json.gz`))}
    catch{return send(404,{error:'Replay data is not available for this date. Refresh the fleet export or choose another date.'})}
    res.statusCode=200;res.setHeader('Content-Type','application/json');res.setHeader('Content-Encoding','gzip');res.end(data);return
   }
   if(url.pathname==='/api/maintenance/report'&&req.method==='GET'){
    const city=url.searchParams.get('city')==='jersey'?'jersey_city':url.searchParams.get('city')
    if(!cities.has(city))return send(400,{error:'Choose a supported city.'})
    try{return send(200,await serviceLog.getReport(city))}
    catch(error){return send(503,{error:error.message})}
   }
   if(url.pathname==='/api/maintenance/service-log'){
    const city=url.searchParams.get('city')==='jersey'?'jersey_city':url.searchParams.get('city')
    if(!cities.has(city))return send(400,{error:'Choose a supported city.'})
    try{
     if(req.method==='GET')return send(200,{records:await serviceLog.getRecords(city)})
     if(req.method==='POST'){const input=await body(req,128000);return send(200,await serviceLog.append(city,input.records,email))}
    }catch(error){return send(422,{error:error.message})}
   }
   if(url.pathname==='/api/maintenance/reliability'&&req.method==='POST'){
    const input=await body(req)
    if(!input.rates||typeof input.rates!=='object'||Array.isArray(input.rates)||Object.keys(input.rates).length>20||
      Object.entries(input.rates).some(([key,value])=>!key||typeof value!=='number'||!Number.isFinite(value)||value<0||value>1)||
      typeof input.projected!=='number'||!Number.isFinite(input.projected)||input.projected<0||input.projected>1000000)
     return send(400,{error:'Use defect proportions from 0 to 1 and a nonnegative bike count.'})
    try{return send(200,await reliability(input))}catch(error){return send(422,{error:error.message})}
   }
   return send(404,{error:'Maintenance endpoint not found.'})
  }catch{return send(400,{error:'Check your request and try again.'})}
 }
}

export function maintenanceApiPlugin(){
 const middleware=createMaintenanceApi()
 return {name:'bikesmart-maintenance-api',configureServer(server){server.middlewares.use(middleware)},configurePreviewServer(server){server.middlewares.use(middleware)}}
}
