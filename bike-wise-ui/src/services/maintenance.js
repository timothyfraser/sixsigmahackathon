export async function maintenanceRequest(endpoint,options={}){
 const response=await fetch(`/api/maintenance/${endpoint}`,{
  credentials:'same-origin',...options,
  headers:{...(options.body?{'Content-Type':'application/json'}:{}),...options.headers},
 })
 let result
 try{result=await response.json()}catch{throw new Error('The maintenance service is unavailable. Please try again.')}
 if(!response.ok){const error=new Error(result.error??'The request failed.');error.status=response.status;throw error}
 return result
}
