// Actual production bundle. Fixture HTTP only, no fake WebSocket or Remote shell.
const fs=require('node:fs'), path=require('node:path'), http=require('node:http');
const assert=require('node:assert/strict'), {spawn}=require('node:child_process');
const project=path.resolve(__dirname,'..'), out=path.join(project,'evidence',process.env.MEGAVGM_EVIDENCE||'viewport-contract');
const buildRoot=process.env.MEGAVGM_BUILD_ROOT||path.join(project,'frontend/build');
fs.mkdirSync(out,{recursive:true});
const port=5291, debug=9393, origin=`http://127.0.0.1:${port}`;
const entries=Array.from({length:40},(_,i)=>({path:`/media/fat/MegaVGMDrive/Music/${i+1} Track.vgm`,title:`${i+1} Track`,filename:`${i+1} Track.vgm`,directory:'Music',available:true}));
const status={mode:'MEGAVGM',main:'MODIFIED',supervisorController:'RUNNING',controllerRunning:true,state:'PLAYING',session:4,context:'PLAYLIST',playlist:'Favorites',path:entries[1].path,title:'Magical Sound Shower',index:2,count:10,repeat:'ALL',shuffle:true,soundChips:['YM2151','SegaPCM']};
const requests=[],errors=[];
const server=http.createServer((req,res)=>{
 const u=new URL(req.url,origin); requests.push(u.pathname);
 if(u.pathname.startsWith('/api/')) {
  assert(u.pathname.startsWith('/api/megavgm/'),'Remote request: '+u.pathname);
  let value;
  if(u.pathname.endsWith('/status')) value=status;
  else if(u.pathname.endsWith('/browse')) value={path:u.searchParams.get('path')||'',parent:'',entries:entries.map(e=>({name:e.filename,type:'file'}))};
  else if(u.pathname.endsWith('/playlists')) value={version:1,playlists:[{name:'Favorites',count:40,availableCount:40,reserved:true}]};
  else value={version:1,name:'Favorites',playlist:'Favorites',reserved:true,entries};
  res.setHeader('Content-Type','application/json'); res.end(JSON.stringify(value)); return;
 }
 const p=path.join(buildRoot,u.pathname==='/megavgm'?'megavgm.html':u.pathname);
 const types={'.html':'text/html','.js':'text/javascript','.css':'text/css','.png':'image/png','.json':'application/json'};
 if(!fs.existsSync(p)){res.writeHead(404);res.end();return;}
 res.setHeader('Content-Type',types[path.extname(p)]||'application/octet-stream');res.end(fs.readFileSync(p));
});
(async()=>{
 await new Promise(r=>server.listen(port,'127.0.0.1',r));
 const profile=fs.mkdtempSync('/private/tmp/megavgm-phase1-chrome-');
 const chrome=spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',[
  '--headless=new',`--remote-debugging-port=${debug}`,`--user-data-dir=${profile}`,
  '--no-first-run','--no-default-browser-check',`--app=${origin}/megavgm`
 ],{stdio:'ignore'});
 let ws;
 try {
  let pages;
  for(let i=0;i<100;i++){try {pages=await(await fetch(`http://127.0.0.1:${debug}/json/list`)).json();if(pages.some(x=>x.type==='page'))break;}catch{} await new Promise(r=>setTimeout(r,100));}
  ws=new WebSocket(pages.find(x=>x.type==='page').webSocketDebuggerUrl);
  await new Promise(r=>ws.addEventListener('open',r,{once:true}));
  let id=0;const pending=new Map();
  ws.addEventListener('message',e=>{const m=JSON.parse(e.data);if(m.method==='Runtime.exceptionThrown')errors.push(m.params);if(m.method==='Network.webSocketCreated')errors.push('WebSocket created');if(m.id){const p=pending.get(m.id);pending.delete(m.id);m.error?p.reject(m.error):p.resolve(m.result);}});
  const send=(method,params={})=>new Promise((resolve,reject)=>{pending.set(++id,{resolve,reject});ws.send(JSON.stringify({id,method,params}));});
  const evaluate=async expression=>{const r=await send('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true});if(r.exceptionDetails)throw Error(JSON.stringify(r.exceptionDetails));return r.result.value;};
  const wait=async expression=>{for(let i=0;i<100;i++){if(await evaluate(expression))return;await new Promise(r=>setTimeout(r,50));}throw Error('timeout '+expression);};
  await send('Runtime.enable');await send('Network.enable');await send('Page.enable');
  await send('Emulation.setSafeAreaInsetsOverride',{insets:{top:59,bottom:34,left:0,right:0}});
  const measurements=[];
  for(const width of (process.env.MEGAVGM_REDUCED_PERCENT_ROOT ? [393] : [320,393])) {
   await send('Emulation.setDeviceMetricsOverride',{width,height:852,deviceScaleFactor:1,mobile:true});
   await send('Page.navigate',{url:origin+'/megavgm'});
   await wait("document.querySelector('[data-testid=playback-engine-position]')?.textContent==='YM2151 + SegaPCM · 2/10'");
   assert(await evaluate("matchMedia('(display-mode: standalone)').matches"));
   await wait("document.querySelectorAll('[data-track-state]').length===40");
   if(process.env.MEGAVGM_REDUCED_PERCENT_ROOT) {
    // Controlled test-only reduced percentage-root basis. This is NOT an iOS
    // emulator or production viewport correction. New min/max constraints must
    // contain the independent lvh child despite a reduced preferred root height.
    await evaluate("document.documentElement.style.height='calc(100lvh - env(safe-area-inset-top))'");
   }
   const read=()=>evaluate(`(()=>{const box=s=>{const e=document.querySelector(s),r=e.getBoundingClientRect(),c=getComputedStyle(e);return {top:r.top,bottom:r.bottom,left:r.left,right:r.right,width:r.width,height:r.height,minHeight:c.minHeight,maxHeight:c.maxHeight,paddingTop:parseFloat(c.paddingTop),paddingBottom:parseFloat(c.paddingBottom),scrollTop:e.scrollTop,clientWidth:e.clientWidth,scrollWidth:e.scrollWidth,whiteSpace:c.whiteSpace,overflow:c.overflow,textOverflow:c.textOverflow,text:e.textContent};};return {html:box('html'),body:box('body'),root:box('#root'),shell:box('[data-standalone-shell]'),header:box('header'),content:box('[data-testid=music-content]'),player:box('[data-testid=mini-player]'),title:box('[data-testid=playback-title]'),enginePosition:box('[data-testid=playback-engine-position]'),favorite:box('[aria-label$="current favorite"]'),progress:box('[data-testid=playback-progress]'),nav:box('nav'),tabs:box('nav .MuiTabs-flexContainer'),docHeight:document.scrollingElement.scrollHeight,docWidth:document.scrollingElement.scrollWidth};})()`);
   const before=await read();
   fs.writeFileSync(path.join(out,`initial-${width}.json`),JSON.stringify(before,null,2));
   fs.writeFileSync(path.join(out,`initial-${width}.png`),Buffer.from((await send('Page.captureScreenshot',{format:'png'})).data,'base64'));
   assert.equal(before.shell.bottom,852);assert.equal(before.docHeight,852);assert.equal(before.docWidth,width);assert.equal(before.header.paddingTop,59);assert.equal(before.nav.paddingBottom,34);assert.equal(before.nav.bottom,852);
   for(const key of ['html','body','root']) {
    assert.equal(before[key].height,852);
    assert.equal(before[key].minHeight,'852px',`${key}: full root minimum missing`);
    assert.equal(before[key].maxHeight,'852px',`${key}: full root maximum missing`);
   }
   assert.equal(before.shell.maxHeight,'100%');
   assert.equal(before.enginePosition.text,'YM2151 + SegaPCM · 2/10');
   assert.equal(before.enginePosition.whiteSpace,'nowrap');
   assert.equal(before.title.textOverflow,'ellipsis');
   assert(before.title.right<=before.enginePosition.left+0.5,'title and engine/position overlap');
   assert(before.enginePosition.right<=before.favorite.left+0.5,'engine/position and favorite overlap');
   assert(before.player.left>=0&&before.player.right<=width,'fixed player exceeds viewport');
   assert.equal(before.nav.bottom-before.tabs.bottom,34,'safe bottom must be inside navigation');
   assert(await evaluate("[...document.querySelectorAll('nav [role=tab]')].every(e=>e.getBoundingClientRect().bottom<=818)"));
   await evaluate("document.querySelector('[data-testid=music-content]').scrollTo(0,420)");
   await wait("document.querySelector('[data-testid=music-content]').scrollTop===420");
   await new Promise(r=>setTimeout(r,100));
   await evaluate("[...document.querySelectorAll('[role=tab]')].find(e=>e.textContent==='Playlists').click()");
   await wait("document.querySelectorAll('[data-track-state]').length===40");
   await evaluate("document.querySelector('[data-testid=music-content]').scrollTo(0,210)");
   await new Promise(r=>setTimeout(r,100));
   await evaluate("[...document.querySelectorAll('[role=tab]')].find(e=>e.textContent==='Browse').click()");
   await wait("document.querySelector('[data-testid=music-content]').scrollTop===420");
   const after=await read();assert.equal(after.player.top,before.player.top);assert.equal(after.nav.top,before.nav.top);
   for(let i=0;i<10;i++){await evaluate("document.querySelector('[data-testid=music-content]').scrollTo(0,100000)");await evaluate("document.querySelector('[data-testid=music-content]').scrollTo(0,0)");}
   const final=await read();assert.equal(final.nav.top,before.nav.top);assert.equal(final.player.top,before.player.top);
   measurements.push({width,...final});
   for(const tab of ['Browse','Playlists']) {
    await evaluate(`[...document.querySelectorAll('[role=tab]')].find(e=>e.textContent==='${tab}').click()`);
    await new Promise(r=>setTimeout(r,100));await evaluate("document.querySelector('[data-testid=music-content]').scrollTo(0,0)");
    fs.writeFileSync(path.join(out,`standalone-${width}-${tab.toLowerCase()}.png`),Buffer.from((await send('Page.captureScreenshot',{format:'png'})).data,'base64'));
   }
  }
  assert.equal(errors.length,0,JSON.stringify(errors));
  assert(requests.filter(x=>x.startsWith('/api/')).every(x=>x.startsWith('/api/megavgm/')));
  fs.writeFileSync(path.join(out,'browser.json'),JSON.stringify({measurements,apiPaths:[...new Set(requests.filter(x=>x.startsWith('/api/')))],errors},null,2));
  console.log('PRODUCTION_BUNDLE_BROWSER PASS',JSON.stringify(measurements));
 } finally {if(ws)ws.close();chrome.kill('SIGTERM');server.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
