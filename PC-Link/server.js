'use strict';
// No npm packages. PC Link runs on a trusted local Wi-Fi network only.
const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const dir = __dirname, port = Number(process.env.PORT || 8765);
const uploads = path.join(dir, 'uploads');
fs.mkdirSync(uploads, {recursive: true});
const tokenFile = path.join(dir, 'pairing-token.txt');
const token = fs.existsSync(tokenFile) ? fs.readFileSync(tokenFile, 'utf8').trim() : crypto.randomBytes(18).toString('hex');
if (!/^[a-f0-9]{36}$/.test(token)) throw Error('Invalid pairing token');
if (!fs.existsSync(tokenFile)) fs.writeFileSync(tokenFile, token + '\n', {mode: 0o600});
function json(res, code, value) {
 const data = Buffer.from(JSON.stringify(value));
 res.writeHead(code, {'Content-Type':'application/json','Content-Length':data.length,'Cache-Control':'no-store'}); res.end(data);
}
const audioOptions = ['pc-audio.mp3','pc-audio.m4a','pc-audio.wav'];
function audioPath() { return audioOptions.map(x=>path.join(dir,x)).find(fs.existsSync); }
http.createServer((req,res)=>{
 let u;
 try { u = new URL(req.url, 'http://localhost'); } catch { return json(res,400,{error:'Bad URL'}); }
 const given = req.headers.authorization?.startsWith('Bearer ') ?
   req.headers.authorization.slice(7) : (u.pathname==='/audio' ? u.searchParams.get('token') || '' : '');
 const a=Buffer.from(given), b=Buffer.from(token);
 if (a.length !== b.length || !crypto.timingSafeEqual(a,b)) return json(res,401,{error:'Invalid token'});
 if (req.method==='GET' && u.pathname==='/status')
   return json(res,200,{ok:true,service:'APK Sandbox PC Link',audioAvailable:!!audioPath()});
 if (req.method==='GET' && u.pathname==='/audio') {
   const filename=audioPath();
   if (!filename) return json(res,404,{error:'Put pc-audio.mp3, .m4a or .wav next to server.js'});
   const size=fs.statSync(filename).size;
   let start=0,end=size-1,code=200;
   if (req.headers.range) {
     const m=/^bytes=(\d*)-(\d*)$/.exec(req.headers.range);
     if(!m || !size) {res.writeHead(416,{'Content-Range':'bytes */'+size}); return res.end();}
     if (!m[1] && m[2]) start=Math.max(0,size-Number(m[2]));
     else {start=Number(m[1] || 0); if(m[2]) end=Math.min(end,Number(m[2]));}
     if (!Number.isSafeInteger(start)||!Number.isSafeInteger(end)||start>=size||end<start)
       {res.writeHead(416,{'Content-Range':'bytes */'+size});return res.end();}
     code=206;
   }
   const mime=filename.endsWith('.mp3')?'audio/mpeg':filename.endsWith('.m4a')?'audio/mp4':'audio/wav';
   const h={'Content-Type':mime,'Content-Length':end-start+1,'Accept-Ranges':'bytes','Cache-Control':'no-store'};
   if(code===206) h['Content-Range']='bytes '+start+'-'+end+'/'+size;
   res.writeHead(code,h);return fs.createReadStream(filename,{start,end}).pipe(res);
 }
 if(req.method==='POST' && (u.pathname==='/upload/photo'||u.pathname==='/upload/microphone')) {
   const photo=u.pathname.endsWith('photo'), expected=photo?'image/jpeg':'audio/mp4';
   if(req.headers['content-type']!==expected) return json(res,415,{error:'Wrong media type'});
   const limit=photo?12*1024*1024:30*1024*1024;
   const filename=(photo?'photo':'microphone')+'-'+Date.now()+'-'+crypto.randomBytes(4).toString('hex')+(photo?'.jpg':'.m4a');
   const target=path.join(uploads,filename), out=fs.createWriteStream(target,{flags:'wx'});
   let size=0,done=false;
   function fail(code,message){ if(done)return;done=true;req.unpipe(out);out.destroy();fs.rm(target,{force:true},()=>{});json(res,code,{error:message});req.resume();}
   req.on('data',b=>{size+=b.length;if(size>limit)fail(413,'Upload too large');});
   req.on('error',()=>{done=true;out.destroy();fs.rm(target,{force:true},()=>{});});
   out.on('error',()=>fail(500,'Write failed'));
   out.on('finish',()=>{if(!done)json(res,201,{ok:true,file:filename,bytes:size});});
   return req.pipe(out);
 }
 return json(res,404,{error:'Not found'});
}).listen(port,'0.0.0.0',()=>{
 console.log('APK Sandbox PC Link on port',port,'\nPairing token:',token);
 for(const [name,addresses] of Object.entries(os.networkInterfaces()))
   for(const a of addresses||[])if(a.family==='IPv4'&&!a.internal)console.log(name+': http://'+a.address+':'+port);
 console.log('Same private Wi-Fi only; LAN HTTP is not encrypted.');
 console.log('PC audio: put pc-audio.mp3/.m4a/.wav beside server.js.');
 console.log('Photos and microphone clips go to uploads/.');
});
