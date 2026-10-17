import {lazy,Suspense,useEffect,useState} from 'react'
import {Bike,MapPin} from 'lucide-react'
import OptimizerHome from './components/OptimizerHome'
import {getNetworks} from './services/dataAdapter'
import {maintenanceRequest} from './services/maintenance'
import {clearFleetCache} from './services/fleet'
import './maintenance.css'
const MaintenancePortal=lazy(()=>import('./components/MaintenancePortal'))

const networks=getNetworks()
export default function App(){
 const [networkId,setNetworkId]=useState('jersey')
 const [restart,setRestart]=useState(0)
 const [view,setView]=useState('rider'),[user,setUser]=useState(null),[accountError,setAccountError]=useState('')
 useEffect(()=>{maintenanceRequest('session').then(session=>{if(session.authenticated)setUser(session)}).catch(()=>{})},[])
 useEffect(()=>{if(view==='rider')requestAnimationFrame(()=>window.dispatchEvent(new Event('resize')))},[view])
 async function logout(){try{await maintenanceRequest('logout',{method:'POST'});clearFleetCache();setUser(null);setView('rider');setAccountError('')}catch(error){setAccountError(error.message)}}
 const network=networks.find(n=>n.id===networkId)
 return <div className="app">
  <header className="header"><a className="brand" href="#" onClick={e=>{e.preventDefault();if(view!=='rider')setView('rider');else setRestart(value=>value+1)}}><span className="brand-icon"><Bike size={25}/></span>Bike<span>Smart</span></a><span className="header-tagline">A better ride starts here.</span><div className="network-control"><MapPin size={16}/><select aria-label="Supported network" value={networkId} onChange={e=>setNetworkId(e.target.value)}>{networks.map(n=><option key={n.id} value={n.id}>{n.name}</option>)}</select></div><span className="team">BIG RED CREW <span> / CORNELL 2026</span></span><div className="maintenance-header-actions">{view==='rider'?<button className="maintenance-entry" onClick={()=>setView('maintenance')}>maintenance login here</button>:<><button className="maintenance-entry" onClick={()=>setView('rider')}>Back to rider site</button>{user&&<button className="maintenance-signout" onClick={logout}>Sign out</button>}</>}</div></header>
  {accountError&&<p className="maintenance-error" role="alert">{accountError}</p>}
  <div hidden={view!=='rider'}><OptimizerHome key={`${network.id}/${restart}`} network={network}/></div>
  {view==='maintenance'&&<Suspense fallback={<p className="maintenance-loading" role="status">Loading maintenance…</p>}><MaintenancePortal user={user} network={network} onNetworkChange={setNetworkId} onLogin={session=>setUser(session)} onBack={()=>setView('rider')} onExpired={()=>{clearFleetCache();setUser(null);setView('maintenance')}}/></Suspense>}
 </div>
}
