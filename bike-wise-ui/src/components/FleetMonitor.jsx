import {useEffect,useMemo,useRef,useState} from 'react'
import {MapContainer,TileLayer,CircleMarker,Tooltip,useMap} from 'react-leaflet'
import {Play,Pause,ChevronLeft,ChevronRight,SkipBack,SkipForward,Bike,MapPin} from 'lucide-react'
import {fetchFleetDay,fetchFleetNetwork,replayTrips,fleetSnapshot,stationInventoryMetrics,singleBikeState,routeTrail,zoneColor} from '../services/fleet'
import {formatNetworkTime} from '../services/networkTime'
import '../fleet.css'

function ReplayBounds({network}){
 const map=useMap()
 useEffect(()=>{map.stop();map.fitBounds(network.stations.map(s=>[s.lat,s.lon]),{padding:[30,30],maxZoom:15,animate:false})},[map,network])
 return null
}
function ReplayStation({station,count,selected,onSelect}){
 const marker=useRef(null)
 useEffect(()=>{
  const element=marker.current?.getElement();if(!element)return
  element.setAttribute('data-fleet-station',station.dockID);element.setAttribute('role','button');element.setAttribute('tabindex','0')
  element.setAttribute('aria-label',`Inspect ${station.dockID}`)
  const press=e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();marker.current?.fire('click')}}
  element.addEventListener('keydown',press);return()=>element.removeEventListener('keydown',press)
 },[station.dockID])
 return <CircleMarker ref={marker} center={[station.lat,station.lon]} radius={10} eventHandlers={{click:onSelect}} pathOptions={{color:selected?'#173d36':'white',weight:selected?3:2,fillColor:zoneColor(station.zone),fillOpacity:1}}><Tooltip>{station.dockID} · {count} bikes · {station.zone}</Tooltip></CircleMarker>
}
// Canvas rendering and interpolation follow the demo's onRender engine, scoped to
// this map rather than global window state. Event listeners and RAF stop on exit.
function FleetCanvas({network,trips,step,singleBike,showPast,playing,speed}){
 const map=useMap(),state=useRef({network,trips,step,singleBike,showPast,playing,speed}),engine=useRef(null)
 state.current={network,trips,step,singleBike,showPast,playing,speed}
 useEffect(()=>{
  const canvas=document.createElement('canvas');canvas.className='fleet-trails-canvas';canvas.setAttribute('aria-label','Animated inferred bike paths')
  map.getContainer().appendChild(canvas)
  let current=state.current.step,frame=null,anchor=performance.now()
  function draw(){
   const {network,trips,singleBike,showPast}=state.current,ctx=canvas.getContext('2d'),size=map.getSize()
   if(!ctx)return
   ctx.clearRect(0,0,size.x,size.y)
   const project=point=>map.latLngToContainerPoint(point)
   const stroke=(points,color,width)=>{if(!points.length)return;ctx.beginPath();points.forEach((point,i)=>{const p=project(point);if(i)ctx.lineTo(p.x,p.y);else ctx.moveTo(p.x,p.y)});ctx.strokeStyle=color;ctx.lineWidth=width;ctx.stroke()}
   if(singleBike>=0&&showPast)for(const trip of trips){if(trip.bike===singleBike&&trip.end<=current){const route=network.routes[trip.route];if(route)stroke(route.lats.map((lat,i)=>[lat,route.lons[i]]),'rgba(0,180,216,.5)',3)}}
   const heads=[]
   for(const trip of trips){
    if(trip.start>=current||trip.end<=current||(singleBike>=0&&trip.bike!==singleBike))continue
    const route=network.routes[trip.route];if(!route)continue
    stroke(route.lats.map((lat,i)=>[lat,route.lons[i]]),'rgba(0,168,202,.25)',singleBike>=0?5:3)
    const points=routeTrail(route,(current-trip.start)/(trip.end-trip.start))
    stroke(points,singleBike>=0?'#00d8ed':'#00a8ca',singleBike>=0?4:2.4)
    heads.push(project(points[points.length-1]))
   }
   for(const head of heads){ctx.beginPath();ctx.arc(head.x,head.y,singleBike>=0?6:4.5,0,2*Math.PI);ctx.fillStyle='#023e8a';ctx.fill();ctx.strokeStyle='white';ctx.lineWidth=1.5;ctx.stroke()}
   canvas.dataset.activeHeads=String(heads.length);canvas.dataset.step=String(current);canvas.dataset.firstHead=JSON.stringify(heads[0]??null)
  }
  function resize(){const size=map.getSize(),ratio=window.devicePixelRatio||1;canvas.width=size.x*ratio;canvas.height=size.y*ratio;canvas.style.width=`${size.x}px`;canvas.style.height=`${size.y}px`;canvas.getContext('2d')?.setTransform(ratio,0,0,ratio,0,0);draw()}
  // Advance along the route on every display frame, independently of React's
  // five-minute snapshot counter. Scrubbing and pausing render the exact snapshot.
  function animate(now){
   frame=null
   const {step,playing,speed}=state.current
   current=step+(playing?Math.min((now-anchor)/speed,1):0)
   draw()
   if(playing)frame=requestAnimationFrame(animate)
  }
  function update(){
   if(frame!==null)cancelAnimationFrame(frame)
   anchor=performance.now();current=state.current.step;draw()
   frame=state.current.playing?requestAnimationFrame(animate):null
  }
  engine.current={update};map.on('move zoom viewreset',draw);map.on('resize',resize);resize()
  return()=>{if(frame!==null)cancelAnimationFrame(frame);map.off('move zoom viewreset',draw);map.off('resize',resize);canvas.remove();engine.current=null}
 },[map])
 useEffect(()=>{engine.current?.update()},[step,singleBike,showPast,network,trips,playing,speed])
 return null
}
export default function FleetMonitor({network:city,onNetworkChange,onExpired}){
 const [network,setNetwork]=useState(null),[date,setDate]=useState(''),[day,setDay]=useState(null),[error,setError]=useState(''),[revision,setRevision]=useState(0)
 const [step,setStep]=useState(100),[playing,setPlaying]=useState(false),[speed,setSpeed]=useState(500)
 const [mode,setMode]=useState('all'),[bike,setBike]=useState(0),[showPast,setShowPast]=useState(true),[highlight,setHighlight]=useState(null),[station,setStation]=useState(0),[inspector,setInspector]=useState(false)
 useEffect(()=>{
  const controller=new AbortController();setNetwork(null);setDay(null);setDate('');setPlaying(false);setError('');setMode('all');setBike(0);setStation(0);setInspector(false);setHighlight(null)
  fetchFleetNetwork(city.id,controller.signal).then(value=>{setNetwork(value);setDate(value.default_date)}).catch(error=>{if(error.name==='AbortError')return;if(error.status===401)onExpired();else setError(error.message)})
  return()=>controller.abort()
 },[city.id,revision])
 useEffect(()=>{
  if(!network||!date)return
  const controller=new AbortController();setPlaying(false);setDay(null);setError('')
  fetchFleetDay(city.id,date,controller.signal).then(value=>{setDay(value);setStep(previous=>Math.max(value.observed_steps[0],Math.min(previous,value.observed_steps.at(-1))))}).catch(error=>{if(error.name==='AbortError')return;if(error.status===401)onExpired();else setError(error.message)})
  return()=>controller.abort()
 },[network,date])
 useEffect(()=>{if(!playing||!day)return;const timer=setInterval(()=>setStep(value=>value>=day.observed_steps.at(-1)?day.observed_steps[0]:value+1),speed);return()=>clearInterval(timer)},[playing,day,speed])
 const trips=useMemo(()=>day?replayTrips(day):[],[day])
 if(error)return <section className="maintenance-panel fleet-error"><p role="alert">{error}</p><button className="primary" onClick={()=>setRevision(revision+1)}>Retry fleet monitor</button></section>
 if(!network||!day)return <section className="fleet-loading" role="status">Loading fleet replay…</section>
 const snapshot=fleetSnapshot(day,step,network.capacity)
 if(!snapshot)return <p className="fleet-loading">No recorded snapshot at this time.</p>
 const dateIndex=network.dates.findIndex(value=>value.date===date),first=day.observed_steps[0],last=day.observed_steps.at(-1)
 const selected=network.stations[station],metrics=stationInventoryMetrics(day,station,network.capacity)
 const single=mode==='single'?singleBikeState(day,trips,bike,step):null
 function changeDate(value){setPlaying(false);setDate(value)}
 function inspect(id){setStation(id);setInspector(true)}
 const clock=formatNetworkTime(day.timestamps[step-1],network.meta.tz)
 return <section className="fleet-monitor" aria-label="Fleet monitor" data-step={step}>
  <div className="fleet-heading"><div><h2>Fleet monitor</h2><p>{network.fleet_size} bikes · {network.stations.length} stations · recorded 5-minute snapshots</p></div><nav className="fleet-city-toggle" aria-label="Fleet city">{[['jersey','Jersey City'],['tampa','Tampa'],['milwaukee','Milwaukee']].map(([id,name])=><button key={id} aria-pressed={city.id===id} onClick={()=>onNetworkChange(id)}>{name}</button>)}</nav></div>
  <div className="fleet-layout"><aside className="fleet-controls">
   <div className="fleet-day-control"><label>Replay date<select aria-label="Replay date" value={date} onChange={e=>changeDate(e.target.value)}>{network.dates.map(value=><option key={value.date} value={value.date}>{value.date}{value.n_steps<288?' · partial day':''}</option>)}</select></label><div className="fleet-day-buttons"><button onClick={()=>changeDate(network.dates[dateIndex-1].date)} disabled={dateIndex===0}><ChevronLeft size={15}/>Previous day</button><button onClick={()=>changeDate(network.dates[dateIndex+1].date)} disabled={dateIndex===network.dates.length-1}>Next day<ChevronRight size={15}/></button></div></div>
   <div className="fleet-clock"><output aria-label="Replay timestamp">{clock}</output><span>{network.meta.tz} · snapshot {step} / 288</span></div>
   <label className="fleet-timeline">Time of day<input type="range" aria-label="Replay time" min={first} max={last} step="1" value={step} onChange={e=>{setPlaying(false);setStep(Number(e.target.value))}}/></label>
   <div className="fleet-playback"><button aria-label="Previous snapshot" disabled={step===first} onClick={()=>{setPlaying(false);setStep(step-1)}}><SkipBack size={16}/></button><button className="fleet-play" onClick={()=>setPlaying(!playing)}>{playing?<Pause size={17}/>:<Play size={17}/>} {playing?'Pause':'Play'}</button><button aria-label="Next snapshot" disabled={step===last} onClick={()=>{setPlaying(false);setStep(step+1)}}><SkipForward size={16}/></button><select aria-label="Replay speed" value={speed} onChange={e=>setSpeed(Number(e.target.value))}><option value={1000}>Slow</option><option value={500}>Normal</option><option value={250}>Fast</option></select></div>
   <div className="fleet-kpis"><div><strong data-testid="fleet-in-transit">{snapshot.inTransit}</strong><span>Bikes in transit</span></div><button aria-pressed={highlight==='empty'} onClick={()=>setHighlight(highlight==='empty'?null:'empty')}><strong data-testid="fleet-empty">{snapshot.empty}</strong><span>Stations empty</span><small>{highlight==='empty'?'Showing':'Click to highlight'}</small></button><button aria-pressed={highlight==='full'} onClick={()=>setHighlight(highlight==='full'?null:'full')}><strong data-testid="fleet-full">{snapshot.full}</strong><span>Stations full</span><small>{highlight==='full'?'Showing':'Click to highlight'}</small></button></div>
   <div className="fleet-inspector-tabs"><button aria-pressed={!inspector} onClick={()=>setInspector(false)}><Bike size={14}/>Bike paths</button><button aria-pressed={inspector} onClick={()=>setInspector(true)}><MapPin size={14}/>Station inspector</button></div>
   {!inspector?<div className="fleet-bike-controls"><fieldset><legend>Ride trails</legend><label><input type="radio" name="fleet-mode" checked={mode==='all'} onChange={()=>setMode('all')}/>All {network.fleet_size} bikes</label><label><input type="radio" name="fleet-mode" checked={mode==='single'} onChange={()=>setMode('single')}/>Single bike journey</label></fieldset>{single&&<><label>Bike to track<select aria-label="Bike to track" value={bike} onChange={e=>setBike(Number(e.target.value))}>{network.bike_ids.map((id,index)=><option key={id} value={index}>{id}</option>)}</select></label><div className="fleet-bike-status" aria-live="polite"><strong>{network.bike_ids[bike]}</strong><p>{single.dock>=0?`Docked at ${network.stations[single.dock].dockID}`:single.dock===-1?single.active?`In transit: ${network.stations[single.active.from].dockID} → ${network.stations[single.active.to].dockID}`:'In transit · route not inferred':'No observation'}</p><span>{single.completed} completed inferred trips / {single.total} today</span></div><label className="fleet-checkbox"><input type="checkbox" checked={showPast} onChange={e=>setShowPast(e.target.checked)}/>Display path history</label></>}</div>:<div className="fleet-station-inspector"><label>Selected station<select aria-label="Fleet station" value={station} onChange={e=>setStation(Number(e.target.value))}>{network.stations.map((value,index)=><option key={value.dockID} value={index}>{value.dockID}</option>)}</select></label><div className="fleet-station-status"><strong>{selected.dockID}</strong><span className="fleet-zone" style={{color:zoneColor(selected.zone)}}>{selected.zone} zone</span><p><b data-testid="fleet-station-count">{snapshot.counts[station]} / {network.capacity}</b> bikes now</p><span>Range: {metrics.minimum}–{metrics.maximum} · mean {metrics.mean.toFixed(1)}</span><span>{metrics.emptyMinutes} min empty · {metrics.fullMinutes} min full</span></div><StationInventory day={day} station={station} step={step} capacity={network.capacity}/></div>}
   <div className="fleet-zone-key">{[['Office','#2563eb'],['Residential','#10b981'],['Retail','#f59e0b'],['Moving bike','#023e8a']].map(([label,color])=><span key={label}><i style={{background:color}}/>{label}</span>)}</div>
  </aside><div className="fleet-map-panel"><MapContainer key={city.id} center={city.center} zoom={14} zoomAnimation={false} fadeAnimation={false} markerZoomAnimation={false} scrollWheelZoom={false} aria-label="Fleet replay map"><TileLayer attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors' url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"/><ReplayBounds network={network}/><FleetCanvas network={network} trips={trips} step={step} singleBike={mode==='single'?bike:-1} showPast={showPast} playing={playing} speed={speed}/>{network.stations.map((station,index)=><ReplayStation key={station.dockID} station={station} count={snapshot.counts[index]} selected={inspector&&index===selected.id} onSelect={()=>inspect(index)}/>)}{network.stations.map((station,index)=>((highlight==='empty'&&snapshot.counts[index]===0)||(highlight==='full'&&snapshot.counts[index]===network.capacity))?<CircleMarker key={`highlight-${station.id}`} center={[station.lat,station.lon]} radius={17} interactive={false} className="fleet-outage-highlight" pathOptions={{color:highlight==='empty'?'#d85a4c':'#d8992e',weight:4,fillOpacity:0}}><Tooltip permanent direction="top">{highlight==='empty'?'EMPTY (0)':`FULL (${network.capacity})`}</Tooltip></CircleMarker>:null)}{single?.dock>=0&&<CircleMarker center={[network.stations[single.dock].lat,network.stations[single.dock].lon]} radius={17} interactive={false} pathOptions={{color:'#00b4d8',weight:3,fillOpacity:0}}/>}</MapContainer><p>Zone colors identify stations. Click one to inspect its inventory. Paths are inferred from station snapshots along bicycle-accessible OpenStreetMap streets, not GPS tracks.</p></div></div>
  <p className="maintenance-note">Simulated fleet replay from demo/fleet_viz. Inventory comes from recorded snapshots; moving positions between observations are illustrative. {day.observed_steps.length<288?'This date has partial coverage; controls show only available snapshots.':''}</p>
 </section>
}
function StationInventory({day,station,step,capacity}){
 const observed=new Set(day.observed_steps),width=340,height=150,left=27,right=12,top=12,bottom=25
 const x=index=>left+index*(width-left-right)/287,y=value=>height-bottom-value/capacity*(height-top-bottom)
 const paths=[];let part=[]
 for(let i=0;i<288;i++){if(observed.has(i+1))part.push(`${x(i)},${y(day.dock_mat[i][station])}`);else if(part.length){paths.push(part.join(' '));part=[]}}
 if(part.length)paths.push(part.join(' '))
 return <div className="fleet-station-chart"><h3>24-hour inventory</h3><svg viewBox={`0 0 ${width} ${height}`} role="img" aria-label="Station inventory across the selected day"><rect x={left} y={y(24)} width={width-left-right} height={y(6)-y(24)} fill="#edf5ee"/>{[0,15,capacity].map(value=><g key={value}><line x1={left} x2={width-right} y1={y(value)} y2={y(value)} stroke="#dde6d9"/><text x={left-6} y={y(value)+4} textAnchor="end">{value}</text></g>)}{paths.map((points,i)=><polyline key={i} points={points} fill="none" stroke="#00a8c5" strokeWidth="2"/>)}<line x1={x(step-1)} x2={x(step-1)} y1={top} y2={height-bottom} stroke="#d5aa28" strokeWidth="2"/>{[0,72,144,216].map(index=><text key={index} x={x(index)} y={height-5} textAnchor="middle">{String(index/12).padStart(2,'0')}:00</text>)}</svg></div>
}
