'use strict';
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const {chromium} = require('playwright');
const ui = path.resolve(__dirname, '..');
const example = JSON.parse(fs.readFileSync(path.join(__dirname,'native_20261102_220810','summary.json')));
const wav = path.join(__dirname,'segment_input','two_clips_20s.wav');
const [mode, directory] = process.argv.slice(2);
assert.ok(['--fixture','--collision','--live','--captured'].includes(mode) && directory, 'use --fixture|--collision|--live|--captured NEW_OUTPUT_DIR [SOURCE]');
const captured=mode==='--captured'?[1,2].map(i=>fs.readFileSync(path.join(process.argv[4],'full-response-'+i+'.ndjson'),'utf8')):null;
const capturedTexts=captured?.map(body=>body.trim().split(/\r?\n/).map(s=>JSON.parse(s)).find(e=>e.type==='result').text);
const out = path.resolve(directory);
fs.mkdirSync(out);
const save = (name,object) => fs.writeFileSync(path.join(out,name),JSON.stringify(object,null,2));
const hash = b => crypto.createHash('sha256').update(b).digest('hex');
const pause = ms => new Promise(ok=>setTimeout(ok,ms));
const tapSource = `class Tap extends AudioWorkletProcessor {
  process(inputs) {
    const samples=inputs[0][0];
    if(samples){
      const block=new Int16Array(samples.length);
      for(let i=0;i<samples.length;i++)block[i]=Math.max(-32768,Math.min(32767,Math.round(samples[i]*32768)));
      this.port.postMessage(block,[block.buffer]);
    }
    return true;
  }
}
registerProcessor('independent-input-tap',Tap);`;
function pcm(bytes) {
  assert.equal(bytes.toString('ascii',0,4),'RIFF');
  assert.equal(bytes.toString('ascii',8,12),'WAVE');
  for(let i=12;i+8<=bytes.length;){
    const n=bytes.readUInt32LE(i+4), kind=bytes.toString('ascii',i,i+4);
    if(kind==='fmt ')assert.deepEqual([bytes.readUInt16LE(i+8),bytes.readUInt16LE(i+10),bytes.readUInt32LE(i+12),bytes.readUInt16LE(i+22)],[1,1,16000,16]);
    if(kind==='data'){assert.ok(i+8+n<=bytes.length);return bytes.subarray(i+8,i+8+n);}
    i+=8+n+(n%2);
  }
  throw Error('missing WAV data');
}
function fixtureEvents(i) {
  const word=['FIRST','SECOND'][i-1];
  return [{type:'start',mode:'hybrid'},{type:'progress',stage:100},
    {...example.result,text:word,tokens:['▁'+word],token_ids:[i],request_seq:i},
    {type:'done',seconds:10.735}].map(x=>JSON.stringify(x)).join('\n')+'\n';
}
async function localEndpoint(name) {
  let active=0, peak=0;
  const traffic=[], statusPolls=[];
  const site={'/':'index.html','/static/app.js':'app.js','/static/style.css':'style.css'};
  const server=http.createServer(async(req,res)=>{
    if(req.method==='GET' && site[req.url]){
      const ext=path.extname(site[req.url]);
      res.setHeader('Content-Type',({'.html':'text/html','.js':'text/javascript','.css':'text/css'})[ext]+'; charset=utf-8');
      res.end(fs.readFileSync(path.join(ui,'static',site[req.url])));
    }else if(req.url==='/api/status'){
      res.setHeader('Content-Type','application/json');
      const busy=active>0 || (name==='collision' && traffic.length===1 && !statusPolls.includes(true));
      statusPolls.push(busy);res.end(JSON.stringify({hybrid:example.start_status,busy}));
    }else if(req.method==='POST' && req.url.startsWith('/api/recognize?')){
      const entry={begin:Date.now(),name:req.headers['x-audio-name']};
      traffic.push(entry);active++;peak=Math.max(peak,active);
      const data=[];for await(const chunk of req)data.push(chunk);
      entry.pcm=pcm(Buffer.concat(data));
      const i=traffic.length;
      if(name==='collision' && i===1){
        res.writeHead(409,{'Content-Type':'application/json'});res.end('{"message":"board busy"}');
        entry.status=409;active--;entry.end=Date.now();return;
      }
      entry.status=200;
      const ms=i===1?({full:11500,tail:4500,failure:180})[name]:150;
      await pause(ms);
      res.setHeader('Content-Type','application/x-ndjson');
      // A result without a final done marker must be rolled back on a subsequent error.
      const body=captured?captured[i-1]:i===2&&name==='failure'?fixtureEvents(i).split('\n').slice(0,-2).join('\n')+'\n{"type":"error","message":"TEST_SECOND_FAILED"}\n':fixtureEvents(name==='collision'?1:i);
      res.end(body);active--;entry.end=Date.now();
    }else{res.writeHead(404);res.end();}
  });
  await new Promise((ok,bad)=>server.once('error',bad).listen(0,'127.0.0.1',ok));
  return {url:'http://127.0.0.1:'+server.address().port,traffic,statusPolls,peak:()=>peak,close:()=>new Promise(ok=>server.close(ok))};
}
async function collision(browser){
  const server=await localEndpoint('collision'),ctx=await browser.newContext({permissions:['microphone']});
  const page=await ctx.newPage();
  try{
    await page.goto(server.url);await page.locator('#record').click();
    await page.waitForFunction(()=>document.getElementById('record-status').textContent.includes('录音中'));
    await page.waitForTimeout(800);await page.locator('#record').click();
    await page.waitForFunction(()=>document.getElementById('segment-list').textContent.includes('等待开发板空闲'));
    await page.waitForFunction(()=>document.getElementById('transcript').textContent==='FIRST');
    assert.deepEqual(server.traffic.map(t=>t.status),[409,200]);
    assert.ok(server.traffic[0].pcm.equals(server.traffic[1].pcm));
    assert.ok(server.statusPolls.includes(true)&&server.statusPolls.slice(server.statusPolls.indexOf(true)+1).includes(false));
    assert.equal(await page.locator('#count').textContent(),'1');
    const result={attempts:server.traffic.map(t=>({status:t.status,samples:t.pcm.length/2,sha:hash(t.pcm)})),accepted:1,status_busy:server.statusPolls};
    save('summary.json',result);console.log(JSON.stringify(result));
  }finally{await ctx.close();await server.close();}
}
// Capture the same microphone samples on an independent branch of the WebAudio graph.
async function observeInput(page) {
  await page.addInitScript(({moduleText})=>{
    const worklet=Object.getPrototypeOf(new OfflineAudioContext(1,1,16000).audioWorklet);
    const add=worklet.addModule, registered=new WeakSet();
    worklet.addModule=async function(...args){
      if(!registered.has(this)){
        const url=URL.createObjectURL(new Blob([moduleText],{type:'text/javascript'}));
        try{await add.call(this,url);}finally{URL.revokeObjectURL(url);}
        registered.add(this);
      }
      return add.apply(this,args);
    };
    const create=AudioContext.prototype.createMediaStreamSource;
    AudioContext.prototype.createMediaStreamSource=function(...args){
      const source=create.apply(this,args), connect=source.connect;
      source.connect=function(dest,...rest){
        if(dest instanceof AudioWorkletNode && !window.tapBlocks){
          window.tapRate=this.context.sampleRate;window.tapBlocks=[];
          const tap=new AudioWorkletNode(this.context,'independent-input-tap');
          tap.port.onmessage=e=>window.tapBlocks.push(e.data);
          const silent=this.context.createGain();silent.gain.value=0;
          connect.call(this,tap);tap.connect(silent).connect(this.context.destination);
        }
        return connect.call(this,dest,...rest);
      };
      return source;
    };
    window.originClick=0;document.addEventListener('click',e=>{
      if(e.target.closest('#record')&&!window.originClick)window.originClick=Date.now();
    },true);
  },{moduleText:tapSource});
}
async function tapPcm(page){
  const {encoded,rate}=await page.evaluate(()=>{
    const n=window.tapBlocks.reduce((sum,b)=>sum+b.length,0), bytes=new Int16Array(n);
    let i=0;for(const b of window.tapBlocks){bytes.set(b,i);i+=b.length;}
    const octets=new Uint8Array(bytes.buffer), parts=[];
    for(let j=0;j<octets.length;j+=8192)parts.push(String.fromCharCode(...octets.subarray(j,j+8192)));
    return {encoded:btoa(parts.join('')),rate:window.tapRate};
  });
  assert.equal(rate,16000);return Buffer.from(encoded,'base64');
}
async function recording(browser,name,width) {
  const live=mode==='--live',server=live?null:await localEndpoint(name);
  const ctx=await browser.newContext({viewport:{width,height:900},permissions:['microphone']});
  const page=await ctx.newPage(),url=server?.url||'http://127.0.0.1:8765';
  const logs=[], errors=[], submits=[],responses=[];
  if(live)await page.exposeFunction('saveNativeEvent',e=>{fs.appendFileSync(path.join(out,name+'-progress.jsonl'),JSON.stringify(e)+'\n');console.log(JSON.stringify(e));});
  page.on('pageerror',e=>errors.push(String(e)));page.on('console',m=>logs.push({type:m.type(),text:m.text(),location:m.location()}));
  page.on('request',r=>{
    if(new URL(r.url()).pathname==='/api/recognize' && r.method()==='POST'){
      const body=r.postDataBuffer();
      submits.push({ms:Date.now(),samples:body?pcm(body).length/2:null,sha:body?hash(pcm(body)):null});
      if(live&&body)fs.writeFileSync(path.join(out,name+'-input-'+submits.length+'.wav'),body);
    }
  });
  try{
    if(!live)await observeInput(page);
    await page.goto(url);
    // Chromium omits Blob POST bodies from some CDP request events. Capture passive copies in the page.
    await page.evaluate(()=>{
      const original=window.fetch;window.captured=[];window.sentBlobs=[];
      window.segmentTrace=[];window.originClick=0;
      document.getElementById('record').addEventListener('click',()=>{if(!window.originClick)window.originClick=Date.now();},{capture:true});
      const observer=new MutationObserver(records=>{
        const now=Date.now();
        for(const target of new Set(records.map(r=>r.target)))window.segmentTrace.push({id:target.id,ms:now,text:target.textContent});
      });
      for(const id of ['record-label','transcript','segment-list','segment-latency','segment-status']){
        const node=document.getElementById(id);if(node)observer.observe(node,{childList:true});
      }
      window.wireTimes=[];
      window.fetch=async function(...args){
        const asr=new URL(args[0],location.href).pathname==='/api/recognize';
        let span;
        if(asr){window.sentBlobs.push(args[1].body);span={begin:Date.now()};window.wireTimes.push(span);}
        const response=await original.apply(this,args);
        if(asr){
          span.header=Date.now();span.status=response.status;
          window.captured.push(response.clone().text().then(text=>{
            span.end=Date.now();
            if(window.saveNativeEvent){
              const events=text.trim().split(/\r?\n/).map(s=>JSON.parse(s));
              const result=events.find(e=>e.type==='result');
              window.saveNativeEvent({ms:Date.now(),status:span.status,text:result?.text,seconds:events.at(-1)?.seconds,board:result?.board_seconds});
            }
            return text;
          }));
        }
        return response;
      };
    });
    await page.waitForFunction(()=>!document.getElementById('warmup').disabled || /已就绪|正在初始化/.test(document.getElementById('warmup-title').textContent));
    if(live && await page.locator('#warmup').isEnabled())await page.locator('#warmup').click();
    await page.waitForFunction(()=>document.getElementById('warmup-title').textContent.includes('已就绪'),null,{timeout:120000});
    await page.locator('#record').click();
    const click=await page.evaluate(()=>window.originClick);
    const stop=page.locator('#record');
    await page.waitForTimeout(9000);
    assert.equal(submits.length,0,'first request before 9s');
    await page.waitForRequest(r=>new URL(r.url()).pathname==='/api/recognize',{timeout:15000});
    const firstArrival=submits[0].ms-click;
    assert.ok(firstArrival>=9900,'first request before recording 10 seconds: '+firstArrival);
    assert.equal(await page.evaluate(()=>window.sentBlobs[0].size),320044);
    const firstWhileRecording=await page.locator('#record-label').textContent();
    assert.ok(firstWhileRecording.includes('停止'));assert.ok(await stop.isEnabled());
    if(name!=='full'){
      await pause(1200);await stop.click();
    }
    if(name==='failure')await page.waitForFunction(()=>document.getElementById('notice').textContent.includes('TEST_SECOND_FAILED'),null,{timeout:30000});
    else if(live)await page.waitForFunction(()=>window.wireTimes.filter(r=>r.status===200).length===2||document.getElementById('notice').classList.contains('error'),null,{timeout:480000});
    else await page.waitForFunction(s=>document.getElementById('transcript').textContent.includes(s),capturedTexts?.[1]||'SECOND',{timeout:40000});
    if(live){
      const chunks=await page.evaluate(()=>Promise.all(window.captured));
      const statuses=await page.evaluate(()=>window.wireTimes.map(r=>r.status));
      for(const [idx,s] of chunks.entries()){
        fs.writeFileSync(path.join(out,name+'-response-'+(idx+1)+'.ndjson'),s);
        if(statuses[idx]===409)continue;
        const events=s.trim().split(/\r?\n/).map(v=>JSON.parse(v));
        const result=events.find(v=>v.type==='result');assert.equal(events.at(-1).type,'done');
        assert.equal(result.gpu_used,false);assert.equal(result.pc_conformer_loaded,false);
        assert.equal(result.board_id,'0xA51A2493');assert.ok(result.pl_calls>0);
        responses.push({text:result.text,seconds:events.at(-1).seconds,board:result.board_seconds,encoder_hash:result.encoder_output_sha256,pl_calls:result.pl_calls});
      }
      await page.waitForFunction(s=>document.getElementById('transcript').textContent.includes(s),responses[1].text);
    }
    await pause(500);
    const transcript=await page.locator('#transcript').textContent();
    if(name==='failure')assert.equal(transcript.trim(),'FIRST');
    else{
      const texts=live?responses.map(r=>r.text):capturedTexts||['FIRST','SECOND'];
      assert.ok(transcript.includes(texts[0])&&transcript.indexOf(texts[0])<transcript.lastIndexOf(texts[1]),JSON.stringify({texts,transcript}));
    }
    if(!live)assert.equal(submits.length,2);
    const bodies=await page.evaluate(async()=>Promise.all(window.sentBlobs.map(async b=>{
      const bytes=new Uint8Array(await b.arrayBuffer()), parts=[];
      for(let j=0;j<bytes.length;j+=8192)parts.push(String.fromCharCode(...bytes.subarray(j,j+8192)));
      return btoa(parts.join(''));
    })));
    for(const [i,s] of bodies.entries()){
      const body=Buffer.from(s,'base64'),data=pcm(body);submits[i].samples=data.length/2;submits[i].sha=hash(data);
      if(live)fs.writeFileSync(path.join(out,name+'-input-'+(i+1)+'.wav'),body);
    }
    if(name==='full')assert.ok(submits.every(r=>r.samples===160000));
    else assert.ok(submits[1].samples>1536 && submits[1].samples<160000);
    assert.ok((await page.locator('#record-label').textContent()).includes('开始'));
    assert.ok(await page.locator('#submit').isDisabled(),'old microphone recording remains eligible');
    assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
    if(!live){
      assert.equal(server.peak(),1);assert.ok(server.traffic[0].end<=server.traffic[1].begin);
      let stage;
      if(captured){
        stage=await page.evaluate(()=>({label:document.getElementById('stage-label').textContent,value:document.getElementById('stage-progress').value,max:document.getElementById('stage-progress').max}));
        assert.match(stage.label,/第 2 段.*编码.*解码完成/);assert.equal(stage.value,12);assert.equal(stage.max,12);
      }
      const reference=await tapPcm(page),batch=Buffer.concat(server.traffic.map(x=>x.pcm));
      const offset=reference.indexOf(batch);
      assert.ok(offset>=0 && offset%2===0,'submitted PCM is not a contiguous exact slice of independent microphone capture');
      return {name,mode,stage,click,firstArrival,firstWhileRecording,submits,transcript,peak:server.peak(),pcm_sha256:hash(batch),tap_sample_offset:offset/2,
        tap_samples:reference.length/2,traffic:server.traffic.map(({begin,end,pcm})=>({begin,end,samples:pcm.length/2})),logs,errors};
    }
    const observables=await page.evaluate(()=>({trace:window.segmentTrace,wire:window.wireTimes,latency:document.getElementById('segment-latency').textContent}));
    const firstShown=observables.trace.find(e=>e.id==='transcript'&&e.text===responses[0].text);
    const secondShown=observables.trace.find(e=>e.id==='transcript'&&e.text===transcript);
    const stopped=observables.trace.find(e=>e.id==='record-label'&&e.ms>=submits[0].ms&&e.text.includes('开始'));
    assert.ok(firstShown&&secondShown&&stopped);
    const accepted=observables.wire.filter(r=>r.status===200);assert.equal(accepted.length,2);
    assert.ok(accepted[1].begin>=firstShown.ms-20);
    assert.ok(accepted[0].end<=accepted[1].begin+30);
    let nextSha=null;
    for(const [idx,t] of observables.wire.entries()){
      if(nextSha)assert.equal(submits[idx].sha,nextSha);
      nextSha=t.status===409?submits[idx].sha:null;
    }
    return {name,click,firstArrival,firstWhileRecording,submits,responses,transcript,logs,errors,...observables,
      accepted:accepted.length,busy_409:observables.wire.filter(r=>r.status===409).length,
      peak_recognition_requests:1,stopped_ms:stopped.ms,first_shown_ms:firstShown.ms,final_shown_ms:secondShown.ms,
      first_visible_seconds:(firstShown.ms-click)/1000,after_stop_seconds:(secondShown.ms-stopped.ms)/1000};
  }finally{
    if(live){
      const raw=await page.evaluate(()=>Promise.all(window.captured)).catch(()=>[]);
      raw.forEach((s,i)=>fs.writeFileSync(path.join(out,name+'-response-'+(i+1)+'.ndjson'),s));
      const partial=await page.evaluate(()=>({click:window.originClick,wire:window.wireTimes,trace:window.segmentTrace})).catch(()=>null);
      save(name+'-timeline.json',partial);
    }
    await page.screenshot({path:path.join(out,name+'.png'),fullPage:true}).catch(()=>{});
    save(name+'-browser.json',{submits,responses,logs,errors,
      transcript:await page.locator('#transcript').textContent().catch(()=>null),
      notice:await page.locator('#notice').textContent().catch(()=>null)});
    await ctx.close();if(server)await server.close();
  }
}
(async()=>{
  const browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,
    args:['--no-proxy-server','--use-fake-ui-for-media-stream','--use-fake-device-for-media-stream','--disable-background-timer-throttling','--disable-renderer-backgrounding',
      '--use-file-for-fake-audio-capture='+wav]});
  try{
    if(mode==='--collision'){await collision(browser);return;}
    const cases=mode==='--live'||captured?[['full',1200]]:[['full',1200],['tail',360],['failure',1200]].filter(([id])=>!process.argv[4]||id===process.argv[4]);
    assert.ok(cases.length);
    const run=await Promise.allSettled(cases.map(([name,width])=>recording(browser,name,width)));
    const summary=run.map((r,i)=>r.status==='fulfilled'?r.value:{name:cases[i][0],error:String(r.reason?.stack||r.reason)});
    save('summary.json',summary);
    assert.ok(run.every(r=>r.status==='fulfilled'),JSON.stringify(summary.filter(x=>x.error)));
    for(const s of summary){assert.deepEqual(s.errors,[]);assert.deepEqual(s.logs.filter(m=>m.type==='error'&&!m.text.includes('409')),[]);}
    console.log(JSON.stringify(summary.map(({name,firstArrival,submits,transcript,tap_sample_offset})=>({name,firstArrival,submits,transcript,tap_sample_offset}))));
  }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
