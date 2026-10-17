import {useEffect,useRef,useState} from 'react'
import {Upload,Check,Wrench} from 'lucide-react'
import {maintenanceRequest} from '../services/maintenance'
import {localDateTime,formatNetworkTime} from '../services/networkTime'
import {parseServiceCsv,resolveServiceTime} from '../services/serviceLog'

export default function ServiceLogPanel({network,report,onReport,onExpired}){
 const [records,setRecords]=useState([]),[error,setError]=useState(''),[message,setMessage]=useState(''),[loading,setLoading]=useState(true),[busy,setBusy]=useState(false)
 const [bike,setBike]=useState(''),[completed,setCompleted]=useState(()=>localDateTime(report.reference_time,report.time_zone)),[occurrence,setOccurrence]=useState(''),[note,setNote]=useState('')
 const file=useRef(null)
 useEffect(()=>{
  let active=true;setLoading(true);setError('');setMessage('');setBike('');setCompleted(localDateTime(report.reference_time,report.time_zone));setNote('');setOccurrence('')
  maintenanceRequest(`service-log?city=${network.id}`).then(value=>{if(active)setRecords(value.records)}).catch(error=>{if(active){if(error.status===401)onExpired();else setError(error.message)}}).finally(()=>{if(active)setLoading(false)})
  return()=>{active=false}
 },[network.id])
 const resolved=resolveServiceTime(completed,report.time_zone,occurrence)
 async function save(incoming){
  setBusy(true);setError('');setMessage('')
  try{
   const result=await maintenanceRequest(`service-log?city=${network.id}`,{method:'POST',body:JSON.stringify({records:incoming})})
   setRecords(result.records);onReport(result.report);setMessage(`${result.added} service record${result.added===1?'':'s'} saved. Service queue and station priorities updated.`);setNote('')
  }catch(error){if(error.status===401)onExpired();else setError(error.message)}finally{setBusy(false)}
 }
 async function submit(event){event.preventDefault();if(resolved.status!=='ok'){setError(resolved.message);return}await save([{BIKEID:bike,service_time:resolved.targetTime,note}])}
 async function importCsv(event){const selected=event.target.files?.[0];event.target.value='';if(!selected)return;try{if(selected.size>128000)throw new Error('Import a CSV smaller than 128 KB.');await save(parseServiceCsv(await selected.text()))}catch(error){setError(error.message)}}
 const status=report.service_status??report.service_due
 const sorted=[...records].sort((a,b)=>Date.parse(b.service_time)-Date.parse(a.service_time))
 return <section className="maintenance-panel service-log-panel" aria-label="Service log">
  <div className="maintenance-panel-heading"><h2>Service log</h2><p>Record completed work or import existing service records. The BikeSmart package resets accumulated ride hours at the latest recorded service or assumed 70-hour service for each bike and recalculates due bikes and station priorities.</p></div>
  <div className="service-log-context"><span><strong>Report snapshot:</strong> {formatNetworkTime(report.reference_time,report.time_zone)}</span><span>{report.service_log_summary?.effective??0} records applied · {report.service_log_summary?.pending??0} after this snapshot</span><p>Records after the snapshot are saved but do not change historical status. Fleet playback and the quality chart retain their original historical observations.</p></div>
  <div className="service-log-actions"><section><h3><Wrench size={17}/>Record completed service</h3><form onSubmit={submit} className="service-log-form"><label>Bike ID<select aria-label="Serviced bike ID" required value={bike} onChange={e=>setBike(e.target.value)} disabled={busy}><option value="">Choose a bike</option>{status.map(row=><option key={row.BIKEID} value={row.BIKEID}>{row.BIKEID}</option>)}</select></label><label>Completed at · {report.time_zone}<input aria-label="Service completion time" type="datetime-local" required value={completed} onChange={e=>{setCompleted(e.target.value);setOccurrence('')}} disabled={busy}/></label>{resolved.status==='ambiguous'&&<label>Repeated clock time<select aria-label="Service time occurrence" value={occurrence} onChange={e=>setOccurrence(e.target.value)}><option value="">Choose occurrence</option><option value="earlier">First occurrence</option><option value="later">Second occurrence</option></select></label>}<label>Work completed / note<textarea aria-label="Service note" value={note} onChange={e=>setNote(e.target.value)} maxLength={240} rows={2} disabled={busy}/></label><button className="primary" disabled={busy||!bike}>{busy?'Updating maintenance…':'Record service'}<Check size={16}/></button></form></section><section className="service-log-import"><h3><Upload size={17}/>Import a service CSV</h3><p>Required columns: <code>BIKEID,service_time</code>. Optional: <code>note,city</code>.</p><p>Timestamps must include seconds and a timezone, for example <code>2026-10-16T03:55:00Z</code>. Import up to 500 rows. Exact duplicate events are saved only once.</p><input type="file" accept=".csv,text/csv" aria-label="Import service log CSV" ref={file} onChange={importCsv} disabled={busy}/><p>Records must belong to the selected city. Team-supplied simulated history is included where available. New records are saved separately.</p></section></div>
  {error&&<p role="alert" className="maintenance-error service-log-message">{error}</p>}{message&&<p role="status" className="service-log-success">{message}</p>}
  {loading?<p className="maintenance-empty" role="status">Loading service records…</p>:<div className="maintenance-table-scroll"><table><thead><tr><th>Bike</th><th>Completed at</th><th>Work / note</th><th>Snapshot status</th></tr></thead><tbody>{sorted.map(row=><tr key={row.id}><td><strong>{row.BIKEID}</strong></td><td>{formatNetworkTime(row.service_time,report.time_zone)}</td><td>{row.note||'—'}</td><td><span className="maintenance-tag">{Date.parse(row.service_time)<=Date.parse(report.reference_time)?'Applied':'After snapshot'}</span></td></tr>)}</tbody></table>{!records.length&&<p className="maintenance-empty">No service records yet. Add completed work or import your service log.</p>}</div>}
 </section>
}
