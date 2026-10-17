import {formatNetworkTime,localDateTime} from '../services/networkTime'
export default function TimeSelector({kind='departure',choice,onChoice,value,onValue,occurrence,onOccurrence,result,timeZone,referenceTime,proposedTime}) {
 const rentalReturn=kind==='journeyReturn',returning=kind!=='departure'
 const nowLabel=rentalReturn?'Estimated arrival':returning?'Return now':'Leave now'
 const laterLabel=rentalReturn?'Adjust return time':returning?'Return later':'Leave later'
 return <fieldset className="time-selector"><legend>{returning?'When will you return?':'When are you heading out?'}</legend>
 <div className="time-choices"><button type="button" aria-pressed={choice==='now'} onClick={()=>onChoice('now')}>{nowLabel}</button><button type="button" aria-pressed={choice==='later'} onClick={()=>onChoice('later')}>{laterLabel}</button></div>
 <p className="time-zone">{timeZone} · network local time</p>
 {choice==='later'?<><label className="time-input">{returning?'Expected return date and time':'Departure date and time'}<input aria-label={returning?'Expected return date and time':'Departure date and time'} type="datetime-local" value={value} min={`${localDateTime(referenceTime,timeZone).slice(0,10)}T00:00`} onChange={e=>onValue(e.target.value)}/></label>
 {result?.candidates?.length>1&&<label className="time-input">Repeated clock time<select aria-label="Repeated clock time" value={occurrence} onChange={e=>onOccurrence(e.target.value)}><option value="">Choose an occurrence</option><option value="earlier">First — {formatNetworkTime(result.candidates[0],timeZone)}</option><option value="later">Second — {formatNetworkTime(result.candidates[1],timeZone)}</option></select></label>}
 {result?.status!=='ok'&&<p className="time-error" role="alert">{result?.message}</p>}
 {result?.status==='ok'&&<p className="time-confirmed">{formatNetworkTime(result.targetTime,timeZone)}</p>}</>:<p className="time-confirmed">{rentalReturn?`Selected dock arrival: ${proposedTime?formatNetworkTime(proposedTime,timeZone):'choose a pickup first'}`:`Simulated planning clock: ${formatNetworkTime(referenceTime,timeZone)}`}</p>}
 <small>DEMO PREDICTION · times and availability are illustrative.</small>
 </fieldset>
}
