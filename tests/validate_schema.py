"""Basic validation of generated long-form CSVs; intentionally permits edge-case status conflicts."""
import csv, pathlib
root=pathlib.Path(__file__).resolve().parents[1]/'data'
for name in ('baseline','planted_shift','edge_case'):
    p=root/f'{name}.csv'
    with p.open(newline='') as f: rows=list(csv.DictReader(f))
    assert rows and all(r['data_source']=='simulated' for r in rows)
    stations={r['station_id']:int(r['capacity']) for r in rows if r['table']=='stations'}
    assert len(stations)==(2 if name=='edge_case' else 25)
    for r in rows:
        assert r['table'] in ('stations','status','attempts','tasks')
        if r['table']=='status':
            assert r['station_id'] in stations
            b=int(r['bikes_available']); d=int(r['docks_available'])
            assert b>=0 and d>=0 and b+d<=stations[r['station_id']]
        if r['table']=='attempts':
            assert r['attempt_type'] in ('rent','return')
            assert (r['failure_reason']=='') == (r['success']=='TRUE')
    print(name, len(rows),'rows validated')
