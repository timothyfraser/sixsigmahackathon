import {createServer} from 'node:http'
import {readFile} from 'node:fs/promises'
import path from 'node:path'
import {fileURLToPath} from 'node:url'
import {createMaintenanceApi} from './api.mjs'
const dist=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../dist')
const api=createMaintenanceApi()
const types={'.html':'text/html','.js':'text/javascript','.css':'text/css','.json':'application/json','.svg':'image/svg+xml','.png':'image/png','.woff2':'font/woff2'}
const port=Number(process.env.PORT??4173)
createServer((req,res)=>api(req,res,async()=>{
 const pathname=new URL(req.url,'http://localhost').pathname
 if(pathname.startsWith('/api/')){res.writeHead(404);res.end();return}
 let requested
 try{requested=path.resolve(dist,'.'+decodeURIComponent(pathname))}catch{res.writeHead(400);res.end();return}
 if(requested!==dist&&!requested.startsWith(dist+path.sep)){res.writeHead(404);res.end();return}
 if(path.extname(requested)==='')requested=path.join(dist,'index.html')
 try{const data=await readFile(requested);res.setHeader('Content-Type',types[path.extname(requested)]??'application/octet-stream');res.end(data)}
 catch{res.writeHead(404);res.end('Not found')}
})).listen(port,'127.0.0.1',()=>process.stdout.write(`BikeSmart site and maintenance API running on local port ${port}\n`))
