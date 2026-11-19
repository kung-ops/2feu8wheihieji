'use strict';
/* APK Sandbox PC Bridge. Node.js 18+. Local media bridge, not an Android emulator. */
const http = require('node:http');
const os = require('node:os');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const PORT = Number(process.env.BRIDGE_PORT || 8765);
const HOST = process.env.BRIDGE_HOST || '0.0.0.0';
const KEY = process.env.BRIDGE_KEY || crypto.randomBytes(9).toString('base64url');
const ROOT = __dirname;
const INBOX = path.join(ROOT, 'received');
const AUDIO = path.join(ROOT, 'pc-audio');
fs.mkdirSync(INBOX, {recursive:true});
fs.mkdirSync(AUDIO, {recursive:true});
const MAX_SIZE = 20*1024*1024;
const audioTypes = new Map([['.mp3','audio/mpeg'],['.m4a','audio/mp4'],['.wav','audio/wav'],['.caf','audio/x-caf']]);

function send(res,status,obj){
  const body=Buffer.from(JSON.stringify(obj));
  res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Content-Length':body.length,'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});
  res.end(body);
}
function authorized(req){
  const supplied=req.headers['x-bridge-key'];
  if(typeof supplied!=='string') return false;
  const a=Buffer.from(supplied), b=Buffer.from(KEY);
  return a.length===b.length && crypto.timingSafeEqual(a,b);
}
function readLimited(req){
  return new Promise((resolve,reject)=>{
    let length=0;const parts=[];
    req.on('data',part=>{
      length+=part.length;
      if(length>MAX_SIZE){const error=new Error('Media is larger than 20 MB');error.code='TOO_LARGE';reject(error);req.pause();return;}
      parts.push(part);
    });
    req.on('end',()=>resolve(Buffer.concat(parts)));
    req.on('aborted',()=>reject(new Error('Request interrupted')));
    req.on('error',reject);
  });
}
function audioList(){
  return fs.readdirSync(AUDIO,{withFileTypes:true})
    .filter(entry=>entry.isFile() && audioTypes.has(path.extname(entry.name).toLowerCase()))
    .map(entry=>entry.name).sort().slice(0,100);
}
const server=http.createServer(async(req,res)=>{
  res.setHeader('X-Content-Type-Options','nosniff');
  if(!authorized(req)) return send(res,401,{error:'Enter the pairing key from the PC server window.'});
  let url;
  try{url=new URL(req.url,'http://localhost');}catch{return send(res,400,{error:'Invalid URL'});}
  try{
    if(req.method==='GET' && url.pathname==='/health'){
      return send(res,200,{ok:true,name:'APK Sandbox PC Bridge',protocol:1,features:['photo-upload','audio-upload','pc-audio-playback']});
    }
    if(req.method==='POST' && (url.pathname==='/photo' || url.pathname==='/recording')){
      const photo=url.pathname==='/photo';
      const type=String(req.headers['content-type']||'').split(';')[0];
      if(type!==(photo?'image/jpeg':'audio/mp4')) return send(res,415,{error:'Wrong media type'});
      if(Number(req.headers['content-length']||0)>MAX_SIZE) return send(res,413,{error:'Media is larger than 20 MB'});
      const bytes=await readLimited(req);
      if(!bytes.length) return send(res,400,{error:'Empty media'});
      if(photo && !(bytes[0]===0xff && bytes[1]===0xd8)) return send(res,400,{error:'Invalid JPEG'});
      if(!photo && bytes.length<16) return send(res,400,{error:'Invalid audio recording'});
      const filename=new Date().toISOString().replace(/[:.]/g,'-')+'-'+crypto.randomBytes(4).toString('hex')+(photo?'.jpg':'.m4a');
      await fs.promises.writeFile(path.join(INBOX,filename),bytes,{flag:'wx'});
      console.log('Received '+(photo?'photo':'recording')+': '+filename+' ('+bytes.length+' bytes)');
      return send(res,201,{ok:true,file:filename,bytes:bytes.length});
    }
    if(req.method==='GET' && url.pathname==='/audio') return send(res,200,{files:audioList()});
    if(req.method==='GET' && url.pathname.startsWith('/audio/')){
      let name;
      try{name=decodeURIComponent(url.pathname.slice('/audio/'.length));}
      catch{return send(res,400,{error:'Invalid audio filename'});}
      if(!/^[a-zA-Z0-9 _().-]{1,128}$/.test(name) || !audioTypes.has(path.extname(name).toLowerCase())) return send(res,400,{error:'Invalid audio filename'});
      const file=path.join(AUDIO,name);
      let stat;
      try{stat=await fs.promises.stat(file);}catch{return send(res,404,{error:'Audio not found'});}
      if(!stat.isFile() || stat.size>MAX_SIZE) return send(res,413,{error:'Audio unavailable or too big'});
      res.writeHead(200,{'Content-Type':audioTypes.get(path.extname(name).toLowerCase()),'Content-Length':stat.size,'Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});
      return fs.createReadStream(file).pipe(res);
    }
    send(res,404,{error:'Unknown route'});
  }catch(error){
    if(!res.headersSent) send(res,error.code==='TOO_LARGE'?413:500,{error:error.code==='TOO_LARGE'?error.message:'Server error'});
    console.error('Bridge error:',error.message);
  }
});
server.requestTimeout=30000;
server.listen(PORT,HOST,()=>{
  console.log('\n=== APK Sandbox PC Bridge ===');
  console.log('Pairing key: '+KEY);
  for(const [iface,entries] of Object.entries(os.networkInterfaces())){
    for(const addr of entries||[]) if(addr.family==='IPv4' && !addr.internal) console.log('PC address ('+iface+'): http://'+addr.address+':'+PORT);
  }
  console.log('On iPhone: APK Sandbox > PC Bridge > enter address + key > Connect');
  console.log('Photos/recordings saved at: '+INBOX);
  console.log('Put MP3/M4A/WAV for iPhone playback in: '+AUDIO);
  console.log('Use only a private trusted Wi-Fi network. Close this window to stop.\n');
});
server.on('error',error=>{console.error('Cannot start bridge:',error.message);process.exitCode=1;});
