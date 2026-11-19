'use strict';
const assert=require('node:assert/strict');
const {spawn}=require('node:child_process');
const {writeFileSync,unlinkSync}=require('node:fs');
const {join}=require('node:path');
const crypto=require('node:crypto');
const key=crypto.randomBytes(8).toString('hex');
const port=18000+Math.floor(Math.random()*2000);
const base='http://127.0.0.1:'+port;
const child=spawn(process.execPath,[join(__dirname,'server.js')],{
  env:{...process.env,BRIDGE_HOST:'127.0.0.1',BRIDGE_PORT:String(port),BRIDGE_KEY:key},
  cwd:__dirname,stdio:['ignore','pipe','pipe']
});
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const headers={'X-Bridge-Key':key};
(async()=>{
  let ready=false;
  for(let i=0;i<80;i++){
    if(child.exitCode!==null) throw Error('Server exited');
    try{if((await fetch(base+'/health',{headers})).ok){ready=true;break;}}catch{}
    await sleep(50);
  }
  assert.ok(ready,'server starts');
  assert.equal((await fetch(base+'/health')).status,401);
  assert.equal((await fetch(base+'/health',{headers:{'X-Bridge-Key':'wrong'}})).status,401);
  const health=await fetch(base+'/health',{headers});
  assert.equal(health.status,200);assert.equal((await health.json()).protocol,1);
  const photo=await fetch(base+'/photo',{method:'POST',headers:{...headers,'Content-Type':'image/jpeg'},body:Buffer.from([0xff,0xd8,0xff])});
  assert.equal(photo.status,201);
  const recording=await fetch(base+'/recording',{method:'POST',headers:{...headers,'Content-Type':'audio/mp4'},body:Buffer.from('0000000000000000000')});
  assert.equal(recording.status,201);
  assert.equal((await fetch(base+'/photo',{method:'POST',headers:{...headers,'Content-Type':'image/jpeg'},body:'invalid'})).status,400);
  const list=await fetch(base+'/audio',{headers});assert.ok(Array.isArray((await list.json()).files));
  const file='test '+crypto.randomBytes(3).toString('hex')+'.wav';
  writeFileSync(join(__dirname,'pc-audio',file),Buffer.from('RIFFtest'));
  const response=await fetch(base+'/audio/'+encodeURIComponent(file),{headers});
  assert.equal(response.status,200);
  assert.equal(Buffer.from(await response.arrayBuffer()).toString(),'RIFFtest');
  unlinkSync(join(__dirname,'pc-audio',file));
  assert.ok((await fetch(base+'/audio/%2e%2e%2fserver.js',{headers})).status>=400);
  assert.equal((await fetch(base+'/photo',{method:'POST',headers:{...headers,'Content-Type':'image/jpeg'},body:Buffer.alloc(20*1024*1024+1,0xff)})).status,413);
  console.log('PASS: pairing, uploads, playback, path checks, 20 MB limit');
})().catch(e=>{console.error(e);process.exitCode=1}).finally(()=>child.kill());
