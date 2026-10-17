"""Independent H-02 acceptance checks; run from any working directory."""
import csv
import math
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent

def p_limits(failed, totals):
    p = sum(failed) / sum(totals)
    return p, [(max(0, p-3*math.sqrt(p*(1-p)/n)), min(1, p+3*math.sqrt(p*(1-p)/n))) for n in totals] if 0 < p < 1 else None

def imr_limits(values):
    center = sum(values)/len(values)
    mr = sum(abs(b-a) for a,b in zip(values,values[1:]))/(len(values)-1)
    return (center, center-3*mr/1.128, center+3*mr/1.128) if mr else None

p, limits = p_limits([4,6,5,3,7], [100]*5)
assert abs(p-.05)<1e-12 and abs(limits[0][1]-.115383)<1e-6
assert p_limits([0,0,0],[100]*3)[1] is None
assert abs(imr_limits([30,34,28,36,32])[2]-46.62766)<.001
assert imr_limits([30]*5) is None
print('KA-2, KA-3 and zero-variation checks PASS')

for name in ('baseline','planted_shift','edge_case'):
    with (ROOT/f'{name}.csv').open(newline='',encoding='utf-8') as f:
        reader = csv.DictReader(f)
        columns = reader.fieldnames
        rows = list(reader)
    assert len(columns)==27 and len(set(columns))==27
    station_rows=[r for r in rows if r['table']=='stations']
    stations={r['station_id']:int(r['capacity']) for r in station_rows}
    assert len(station_rows)==len(stations)==(2 if name=='edge_case' else 25)
    status_keys=Counter(); attempts=set(); tasks=set(); vans=set(); dates=set()
    unusable=Counter(); status_n=Counter(); fail=Counter(); total=Counter()
    fields={
        'stations': {'station_id','station_name','latitude','longitude','capacity','region'},
        'status': {'station_id','timestamp','bikes_available','docks_available','is_renting','is_returning'},
        'attempts': {'station_id','timestamp','attempt_id','attempt_type','success','failure_reason'},
        'tasks': {'task_id','van_id','source_station_id','destination_station_id','planned_quantity','actual_quantity','assigned_at','arrived_at','completed_at','status'},
    }
    for r in rows:
        table=r['table']; assert table in fields
        assert r['data_source']=='simulated'
        assert all(v=='' for k,v in r.items() if k not in fields[table]|{'table','data_source'})
        if table=='stations':
            assert -90<=float(r['latitude'])<=90 and -180<=float(r['longitude'])<=180
            assert stations[r['station_id']]>0
        if table in ('status','attempts'):
            assert r['station_id'] in stations
            t=datetime.fromisoformat(r['timestamp']); assert t.utcoffset() is not None
            assert t.utcoffset().total_seconds()==-4*3600 and t.weekday()<5
            dates.add(t.date())
        if table=='status':
            key=(r['station_id'],r['timestamp']);status_keys[key]+=1
            b,d=int(r['bikes_available']),int(r['docks_available'])
            assert b>=0 and d>=0 and b+d<=stations[r['station_id']]
            assert r['is_renting'] in ('TRUE','FALSE') and r['is_returning'] in ('TRUE','FALSE')
            if 7<=t.hour<10:
                status_n[t.date()]+=1
                unusable[t.date()]+=int(b==0 or d==0 or r['is_renting']=='FALSE' or r['is_returning']=='FALSE')
        if table=='attempts':
            assert r['attempt_id'] not in attempts; attempts.add(r['attempt_id'])
            typ=r['attempt_type']; assert typ in ('rent','return')
            assert r['success'] in ('TRUE','FALSE')
            reasons={'rent':{'no_bike','bike_fault','dock_fault','station_closed','app_error'},'return':{'no_dock','dock_fault','station_closed','app_error'}}
            assert (r['success']=='TRUE' and r['failure_reason']=='') or (r['success']=='FALSE' and r['failure_reason'] in reasons[typ])
            if 7<=t.hour<10:
                total[t.date(),typ]+=1;fail[t.date(),typ]+=int(r['success']=='FALSE')
            if name=='edge_case' and r['station_id']=='S001': assert r['success']=='TRUE'
        if table=='tasks':
            assert r['task_id'] not in tasks;tasks.add(r['task_id']);vans.add(r['van_id'])
            assert r['source_station_id'] in stations and r['destination_station_id'] in stations
            assert r['source_station_id']!=r['destination_station_id']
            assert 0<=int(r['actual_quantity'])<=int(r['planned_quantity']) and int(r['planned_quantity'])>0
            ts=[datetime.fromisoformat(r[k]) for k in ('assigned_at','arrived_at','completed_at')]
            assert all(t.utcoffset() is not None for t in ts) and ts==sorted(ts)
            assert r['status']=='completed' and r['van_id']
    days=sorted(dates)
    assert len(days)==(1 if name=='edge_case' else 20)
    if name!='edge_case':
        assert all(n==1 for n in status_keys.values())
        assert all(status_n[d]==4500 for d in days)
        assert len(vans)==2 and len(tasks)==60
    else:
        assert sorted(n for n in status_keys.values() if n>1)==[3]
        stamp=lambda hm: f'{days[0]}T{hm}:00-0400'
        assert ('S002',stamp('07:05')) not in status_keys
        assert all(('S002',stamp(f'07:{m:02}')) not in status_keys for m in range(10,14))
    print(f'{name}: {len(rows)} rows; {len(stations)} stations; {len(days)} weekdays; schema and scenario structure PASS')
    if name=='planted_shift':
        base=days[:10]
        p=sum(fail[d,'return'] for d in base)/sum(total[d,'return'] for d in base)
        assert 0<p<1
        p_flags=[i+1 for i,d in enumerate(days) if fail[d,'return']/total[d,'return']>min(1,p+3*math.sqrt(p*(1-p)/total[d,'return']))]
        shares=[100*unusable[d]/status_n[d] for d in days]
        center,low,high=imr_limits(shares[:10])
        i_flags=[i+1 for i,x in enumerate(shares) if x<low or x>high]
        assert 11 in p_flags and 11 in i_flags
        assert all(i in p_flags and i in i_flags for i in range(11,21))
        print(f'  return p baseline={p:.6f}; upper-limit signals on weekdays {p_flags}')
        print(f'  I-MR baseline center={center:.3f}%, limits=[{low:.3f}, {high:.3f}]%; signals on weekdays {i_flags}')
print('All independent H-02 checks PASS (fixture checks, not app/sim.R integration).')
