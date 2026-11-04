'use strict';
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const {chromium} = require('playwright');
const ui = path.resolve(__dirname, '..');
const wav = path.resolve(ui, '../board_test/profile_runs/20261102_205629/input.wav');
const fixture = path.join(__dirname, 'native_20261102_220810');
const expectation = JSON.parse(fs.readFileSync(path.join(fixture,'summary.json')));
const sha = x => crypto.createHash('sha256').update(x).digest('hex');
const sampleHash = '8a5f532db44f46bbcc1a139475c0f1c9850f2379bd82f59e5e91e71421ae9075';
const encoderHash = 'c18836aa2255963e5be655b1cf9baebebcb0654348989f3961ad07465e8a4ceb';
const mode = process.argv[2];
assert.ok(['--live','--fixture-only','--captured'].includes(mode) && process.argv[3], 'use --live|--fixture-only|--captured FRESH_OUTPUT_DIRECTORY [CAPTURED_NDJSON]');
const out = path.resolve(process.argv[3]);
fs.mkdirSync(out);
const save = (name, data) => fs.writeFileSync(path.join(out,name),JSON.stringify(data,null,2));

function wavePcm(bytes) {
  assert.equal(bytes.toString('ascii',0,4),'RIFF');
  assert.equal(bytes.toString('ascii',8,12),'WAVE');
  for (let i=12; i+8<=bytes.length;) {
    const n=bytes.readUInt32LE(i+4);
    if (bytes.toString('ascii',i,i+4)==='data') {assert.ok(i+8+n<=bytes.length);return bytes.subarray(i+8,i+8+n);}
    i+=8+n+(n%2);
  }
  throw Error('source WAV lacks PCM chunk');
}
function shortWav(count) {
  const b=Buffer.alloc(44+2*count);
  b.write('RIFF'); b.writeUInt32LE(b.length-8,4); b.write('WAVEfmt ',8); b.writeUInt32LE(16,16);
  b.writeUInt16LE(1,20); b.writeUInt16LE(1,22); b.writeUInt32LE(16000,24); b.writeUInt32LE(32000,28);
  b.writeUInt16LE(2,32); b.writeUInt16LE(16,34); b.write('data',36); b.writeUInt32LE(2*count,40);return b;
}
async function replayServer(body) {
  let posts=0;
  const staticPaths={'/':'index.html','/static/app.js':'app.js','/static/style.css':'style.css'};
  const server=http.createServer(async(req,res)=>{
    if(req.method==='GET' && staticPaths[req.url]) {
      const name=staticPaths[req.url], ext=path.extname(name);
      res.writeHead(200,{'Content-Type':({'.html':'text/html','.js':'text/javascript','.css':'text/css'})[ext]+'; charset=utf-8'});
      res.end(fs.readFileSync(path.join(ui,'static',name)));
    } else if(req.method==='GET' && req.url==='/api/status') {
      res.setHeader('Content-Type','application/json');res.end(JSON.stringify({hybrid:expectation.start_status}));
    } else if(req.method==='POST' && req.url==='/api/recognize?mode=hybrid') {
      posts++; const a=[];for await(const chunk of req)a.push(chunk);
      if(sha(wavePcm(Buffer.concat(a)))!==sampleHash){res.writeHead(422);res.end('PCM mismatch');return;}
      res.setHeader('Content-Type','application/x-ndjson');res.end(body);
    } else if(req.url==='/favicon.ico'){res.writeHead(204);res.end();}
    else {res.writeHead(404);res.end();}
  });
  await new Promise((ok,bad)=>server.once('error',bad).listen(0,'127.0.0.1',ok));
  return {url:'http://127.0.0.1:'+server.address().port,posts:()=>posts,close:()=>new Promise(ok=>server.close(ok))};
}
async function inspect(browser,url,width,name,checkInputs) {
  const page=await browser.newPage({viewport:{width,height:920},deviceScaleFactor:1});
  const logs=[],errors=[],posts=[];
  page.on('console',m=>logs.push({type:m.type(),text:m.text(),location:m.location()}));
  page.on('pageerror',e=>errors.push(String(e)));
  page.on('request',r=>{if(r.method()==='POST')posts.push({url:r.url(),bytes:r.postDataBuffer()?.length});});
  try {
    await page.goto(url);
    await page.waitForFunction(()=>!document.getElementById('warmup').disabled || /已就绪|正在初始化/.test(document.getElementById('warmup-title').textContent),null,{timeout:15000});
    if(await page.locator('#warmup').isEnabled())await page.locator('#warmup').click();
    await page.waitForFunction(()=>document.getElementById('warmup-title')?.textContent.includes('已就绪'),null,{timeout:240000});
    assert.equal(await page.getByRole('radio').count(),0);
    const file=page.locator('#file'), submit=page.locator('#submit');
    if(checkInputs) {
      await file.setInputFiles({name:'96ms.wav',mimeType:'audio/wav',buffer:shortWav(1536)});
      await page.waitForFunction(()=>!document.getElementById('submit').disabled);
      await file.setInputFiles({name:'invalid.wav',mimeType:'audio/wav',buffer:Buffer.from('not a wave file')});
      await page.waitForFunction(()=>document.getElementById('notice').classList.contains('error'));
      assert.ok(await submit.isDisabled()); assert.ok(await page.locator('#player').isHidden());
      assert.equal(await page.locator('#player').getAttribute('src'),null);
      await file.setInputFiles({name:'95ms.wav',mimeType:'audio/wav',buffer:shortWav(1520)});
      await page.waitForFunction(()=>document.getElementById('notice').textContent.includes('96 毫秒'));
      assert.ok(await submit.isDisabled()); assert.equal(posts.length,0);
    }
    await file.setInputFiles(wav);
    await page.waitForFunction(()=>!document.getElementById('submit').disabled);
    // Verify the exact PCM the browser will send before consuming the board slot.
    const actual=Buffer.from(await page.evaluate(async()=>Array.from(new Uint8Array(await (await fetch(document.getElementById('player').src)).arrayBuffer()))));
    assert.equal(sha(wavePcm(actual)),sampleHash,'browser changed source PCM');
    await page.evaluate(()=>{
      window.displayLog=[];
      const original=window.fetch;
      window.fetch=async function(...args){
        const response=await original.apply(this,args);
        if(new URL(response.url).pathname==='/api/recognize'){
          window.wireData=response.clone().arrayBuffer().then(b=>Array.from(new Uint8Array(b)));
        }
        return response;
      };
      const observer=new MutationObserver(records=>records.forEach(r=>r.addedNodes.forEach(n=>window.displayLog.push({id:r.target.id,text:n.textContent,at:performance.now()}))));
      for(const id of ['runtime','transcript','tokens','stage-label'])observer.observe(document.getElementById(id),{childList:true});
    });
    const next=page.waitForResponse(r=>new URL(r.url()).pathname==='/api/recognize'&&r.request().method()==='POST',{timeout:90000});
    await submit.click();
    const response=await next;
    await page.waitForFunction(()=>!!window.wireData);
    const data=Buffer.from(await page.evaluate(()=>window.wireData));
    fs.writeFileSync(path.join(out,name+'.ndjson'),data);
    assert.equal(response.status(),200);
    assert.ok(response.headers()['content-type'].includes('application/x-ndjson'));
    const events=data.toString('utf8').trim().split(/\r?\n/).map(line=>JSON.parse(line));
    const results=events.filter(e=>e.type==='result'), done=events.at(-1);
    assert.equal(events[0].type,'start');assert.equal(events[0].mode,'hybrid');
    assert.ok(events.some(e=>e.type==='progress' && e.stage>=100));
    assert.ok(!events.some(e=>e.type==='token'||e.type==='error'));assert.equal(results.length,1);assert.equal(done.type,'done');
    const result=results[0], total=done.seconds;
    assert.equal(result.encoder_output_sha256,encoderHash); assert.equal(result.text,expectation.result.text);
    assert.equal(result.pl_calls,485);assert.equal(result.encoder_frames,41);assert.equal(result.board_id,'0xA51A2493');
    assert.equal(result.gpu_used,false);assert.equal(result.pc_conformer_loaded,false);assert.equal(result.decoding,'ctc_greedy');
    await page.waitForFunction(n=>document.querySelectorAll('#tokens .piece').length===n && !document.getElementById('timings').hidden,result.tokens.length);
    assert.equal(await page.locator('#transcript').textContent(),result.text);
    assert.deepEqual(await page.locator('#tokens .piece').allTextContents(),result.tokens);
    assert.ok((await page.locator('#hardware').textContent()).includes('GPU 未使用'));
    assert.equal(await page.locator('#token-origin').textContent(),'CTC 整句解码结果');
    assert.equal(await page.locator('#runtime').textContent(),'服务用时 '+total.toFixed(2)+' s');
    const v=[result.board_seconds,result.board_roundtrip_seconds-result.board_seconds,result.frontend_seconds,result.ctc_and_readout_seconds,
      total-result.board_roundtrip_seconds-result.frontend_seconds-result.ctc_and_readout_seconds];
    assert.ok(v.every(x=>Number.isFinite(x)&&x>=-0.00051));
    assert.ok(Math.abs(v.reduce((a,b)=>a+b)-total)<1e-6);
    const shown=await page.locator('.timing-row dd').allTextContents();
    const timed=v.map((n,i)=>{
      const seconds=Math.max(n,0),percent=100*seconds/total;
      const label=!percent?'0%':percent<0.01?'<0.01%':percent.toFixed(percent<1?2:1)+'%';
      assert.equal(shown[i],seconds.toFixed(3)+' s · '+label);
      return {seconds,percent,display:shown[i]};
    });
    assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
    const trace=await page.evaluate(()=>window.displayLog);
    const finished=trace.find(x=>x.id==='runtime'&&x.text.includes('服务用时'));
    const tokens=trace.filter(x=>x.id==='tokens');
    const transcript=trace.find(x=>x.id==='transcript'&&x.text===result.text);
    assert.ok(finished && transcript && tokens.length===result.tokens.length && tokens.at(-1).at<=finished.at);
    assert.ok(tokens.at(-1).at-transcript.at<50,'transcript and chips were delayed');
    assert.deepEqual(errors,[]);assert.deepEqual(logs.filter(x=>x.type==='error'),[]);
    assert.deepEqual(posts.filter(x=>!x.url.endsWith('/api/warmup')).map(x=>x.url),[url+'/api/recognize?mode=hybrid']);
    await page.screenshot({path:path.join(out,name+'.png'),fullPage:true});
    return {body:data,summary:{width,posts,service_seconds:total,rows:timed,result,display:trace,
      transcript_to_final_chip_ms:tokens.at(-1).at-transcript.at,input_pcm_sha256:sampleHash,errors,logs}};
  } finally {
    save(name+'-console.json',{errors,logs,posts});await page.close();
  }
}
(async()=>{
  assert.equal(sha(wavePcm(fs.readFileSync(wav))),sampleHash);
  const browser=await chromium.launch({executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe',headless:true,args:['--no-proxy-server']});
  let source, phone;
  try {
    let url='http://127.0.0.1:8765';
    if(mode!=='--live'){
      const data=mode==='--captured'?fs.readFileSync(process.argv[4]):JSON.parse(fs.readFileSync(path.join(fixture,'events.json'))).map(e=>JSON.stringify(e)).join('\n')+'\n';
      source=await replayServer(data);url=source.url;
    }
    const label=mode==='--live'?'desktop-live':'desktop-replay';
    const first=await inspect(browser,url,1200,label,mode==='--fixture-only');
    save(label+'.json',first.summary);
    phone=await replayServer(first.body);
    const mobile=await inspect(browser,phone.url,360,'mobile-replay',true);
    save('mobile-replay.json',mobile.summary);assert.equal(phone.posts(),1);
    if(source)assert.equal(source.posts(),1);
    console.log(JSON.stringify({mode,output:out,live_board_submissions:mode==='--live'?1:0,seconds:first.summary.service_seconds,
      text:first.summary.result.text,rows:first.summary.rows,encoder_hash:first.summary.result.encoder_output_sha256}));
  } finally {
    await browser.close();if(source)await source.close();if(phone)await phone.close();
  }
})().catch(error=>{console.error(error);process.exitCode=1;});
