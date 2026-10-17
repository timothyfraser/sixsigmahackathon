// UI-only fixtures. All identities, inventories, predictions and times below
// are illustrative, including stations placed in real cities. No team data imported.
export const networks = [
 {id:'jersey',timeZone:'America/New_York',name:'Jersey City',subtitle:'New Jersey',center:[40.719,-74.043],places:[{name:'Grove Street plaza',lat:40.7196,lng:-74.0434},{name:'Waterfront promenade',lat:40.7145,lng:-74.033},{name:'Hamilton Park',lat:40.727,lng:-74.044}],stations:['Grove Street','Van Vorst Park','Newark Avenue','Exchange Place','Hamilton Park','Liberty Green','Canal Crossing','Journal Square']},
 {id:'milwaukee',timeZone:'America/Chicago',name:'Milwaukee',subtitle:'Wisconsin',center:[43.039,-87.909],places:[{name:'Public Market area',lat:43.035,lng:-87.908},{name:'Riverwalk area',lat:43.043,lng:-87.911},{name:'Lakeshore area',lat:43.038,lng:-87.898}],stations:['Market Square','Riverwalk','Third Ward','Lakeshore Park','Cathedral Square','Foundry Lane','Harbor Point','Westown Gardens']},
 {id:'tampa',timeZone:'America/New_York',name:'Tampa',subtitle:'Florida · simulated network',center:[27.953,-82.452],places:[{name:'Riverwalk area',lat:27.9486,lng:-82.4602},{name:'Water Street area',lat:27.9430,lng:-82.4508},{name:'Ybor City area',lat:27.9602,lng:-82.4414}],stations:['Riverwalk Plaza','Downtown Gardens','Marion Square','Channel District','Ybor Gateway','Water Street Corner','Tampa Heights Corner','Central Avenue Corner'],stationCoordinates:[[27.9489,-82.4597],[27.9505,-82.4575],[27.9530,-82.4564],[27.9494,-82.4472],[27.9602,-82.4421],[27.9443,-82.4495],[27.9660,-82.4600],[27.9601,-82.4520]]},
]
export const offsets=[[.001,-.001],[-.004,-.003],[.004,.003],[-.003,.009],[.008,-.002],[-.009,.006],[.011,.012],[.006,-.011]]
export const snapshots=[[8,4,12,0,2,7,6,9],[6,5,10,1,3,8,5,10],[5,3,11,2,4,9,7,8]]
export const predicted=[[7,5,10,1,3,8,7,8],[5,6,9,2,4,9,6,9],[4,4,10,3,5,10,8,7]]
