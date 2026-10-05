#!/usr/bin/env python3
"""Owned Chromium integration test. Requires playwright; serve build/web first.
Uses a fresh isolated browser context, never an existing browser profile.
"""
import argparse, json
from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeout
p=argparse.ArgumentParser()
p.add_argument('--url',default='http://127.0.0.1:18765/?lang=ru')
p.add_argument('--browser',default='/usr/bin/google-chrome')
p.add_argument('--hardware',action='store_true')
a=p.parse_args()
errors=[]
with sync_playwright() as pw:
 args=['--no-sandbox','--mute-audio','--use-angle=gl' if a.hardware else '--use-angle=swiftshader']
 if not a.hardware: args += ['--enable-unsafe-swiftshader']
 b=pw.chromium.launch(executable_path=a.browser,headless=True,args=args)
 page=b.new_page(viewport={'width':1280,'height':900})
 def console(msg):
  print('CONSOLE',msg.type,msg.text[:2000],flush=True)
  if msg.type=='error' or ('WARNING: SHADER' in msg.text) or ('GL_INVALID' in msg.text):errors.append(msg.text)
 page.add_init_script("""
 window.toadAudioCheck={callbacks:0,peak:0,energy:0,frames:0};
 const AC=window.AudioContext||window.webkitAudioContext;
 const create=AC.prototype.createScriptProcessor;
 AC.prototype.createScriptProcessor=function(...args) {
  const node=create.apply(this,args);
  const descriptor=Object.getOwnPropertyDescriptor(ScriptProcessorNode.prototype,'onaudioprocess');
  Object.defineProperty(node,'onaudioprocess',{set(handler){descriptor.set.call(node,function(event){
   handler.call(this,event);
   const stats=window.toadAudioCheck; stats.callbacks++;
   for(let channel=0;channel<event.outputBuffer.numberOfChannels;channel++) {
    const data=event.outputBuffer.getChannelData(channel);
    for(const value of data) {stats.peak=Math.max(stats.peak,Math.abs(value));stats.energy+=value*value;stats.frames++;}
   }
  });},get(){return descriptor.get.call(node);}});
  return node;
 };
 """)
 page.on('console',console)
 page.on('pageerror',lambda error:errors.append(str(error)))
 page.goto(a.url)
 page.wait_for_function('typeof ready!=="undefined"&&ready',timeout=30000)
 page.locator('#start').click()
 page.wait_for_function('running && wasm.toad_metric(0)>4',timeout=30000)
 print('START',page.evaluate('({metrics:Array.from({length:23},(_,i)=>wasm.toad_metric(i)),memory:wasm.memory.buffer.byteLength})'),flush=True)
 page.screenshot(path='build/web-menu.png')
 def key(name):
  page.keyboard.down(name);page.wait_for_timeout(110);page.keyboard.up(name);page.wait_for_timeout(450)
 def metric(n):return page.evaluate('(n)=>wasm.toad_metric(n)',n)
 def capture_pointer():
  # Enter may acquire the pointer asynchronously and hide the capture button
  # between an is_visible check and a click. Accept either successful path.
  try:page.wait_for_function('document.pointerLockElement===canvas',timeout=300)
  except PlaywrightTimeout:
   try:page.locator('#capture').click(timeout=1500)
   except PlaywrightTimeout:
    if not page.evaluate('document.pointerLockElement===canvas'):raise
  page.wait_for_function('document.pointerLockElement===canvas')
 key('Enter') # new game settings
 key('Enter') # start intro (Begin is already selected)
 page.wait_for_function('wasm.toad_metric(8)===1')
 page.screenshot(path='build/web-intro.png')
 key('Escape') # character selection
 page.wait_for_function('wasm.toad_metric(8)===2')
 key('ArrowRight')
 page.screenshot(path='build/web-fighter.png')
 key('Enter')
 page.wait_for_function('wasm.toad_playing()')
 capture_pointer()
 assert metric(9)==1,'Lora was not selected'
 start=[metric(i) for i in (2,3,4)]
 page.keyboard.down('w');page.wait_for_function('(p)=>Math.hypot(wasm.toad_metric(2)-p[0],wasm.toad_metric(4)-p[2])>1.2',arg=start,timeout=10000);page.keyboard.up('w');page.wait_for_timeout(150)
 moved=[metric(i) for i in (2,3,4)]
 assert sum((x-y)**2 for x,y in zip(start,moved))>1,(start,moved)
 shots=metric(6)
 page.mouse.down();page.wait_for_function('(n)=>wasm.toad_metric(6)>n+4',arg=shots,timeout=10000);page.mouse.up();page.wait_for_timeout(150)
 assert metric(6)>shots+2,'Browser fire did not reach simulation'
 yaw=metric(10);page.mouse.move(850,360,steps=5);page.wait_for_timeout(160)
 assert abs(metric(10)-yaw)>0.01,'Pointer movement did not aim'
 key('Space')
 assert metric(18)>0,'Jump was not delivered'
 page.mouse.down(button='right');page.wait_for_timeout(400);page.screenshot(path='build/web-scope.png');page.mouse.up(button='right')
 key('F5')
 saved=[metric(i) for i in (2,3,4)]
 key('Escape');page.wait_for_function('wasm.toad_metric(7)===1')
 clock=metric(1);page.wait_for_timeout(500);assert metric(1)==clock,'Paused simulation advanced'
 page.screenshot(path='build/web-pause.png')
 audio=page.evaluate('window.toadAudioCheck')
 assert audio['energy']>0.01 and audio['peak']<1,audio
 print('AUDIO',json.dumps(audio),flush=True)
 page.reload();page.wait_for_function('ready');page.locator('#start').click();page.wait_for_function('running&&wasm.toad_metric(0)>4')
 key('Enter') # Continue selects newest valid slot
 page.wait_for_function('wasm.toad_playing()')
 capture_pointer()
 restored=[metric(i) for i in (2,3,4)]
 assert sum((x-y)**2 for x,y in zip(saved,restored))<1,(saved,restored)
 assert metric(9)==1,'Selected hero lost across reload'
 page.screenshot(path='build/web-gameplay.png')
 status=page.evaluate('({metrics:Array.from({length:23},(_,i)=>wasm.toad_metric(i)),memory:wasm.memory.buffer.byteLength,renderer:Module.ctx.getParameter(Module.ctx.getExtension("WEBGL_debug_renderer_info").UNMASKED_RENDERER_WEBGL)})')
 key('Escape');page.wait_for_function('document.pointerLockElement===null')
 # Leaving a live run parks the app. Re-entry preserves it without another boot.
 parked_position=[metric(i) for i in (2,3,4)]
 prepared=page.evaluate('[...bootTimings.steps]')
 for _ in range(5):key('ArrowDown')
 key('Enter');page.wait_for_function('!running&&parked')
 assert page.locator('#start').is_enabled()
 page.locator('#start').click();page.wait_for_function('running')
 assert [metric(i) for i in (2,3,4)]==parked_position
 assert page.evaluate('bootTimings.steps')==prepared
 key('Enter');page.wait_for_function('wasm.toad_playing()')
 capture_pointer()
 key('Escape');page.wait_for_function('document.pointerLockElement===null')
 page.set_viewport_size({'width':1100,'height':780});page.wait_for_timeout(600)
 assert page.evaluate('canvas.width>=960 && canvas.height>=600')
 page.locator('#fullscreen').click();page.wait_for_function('document.fullscreenElement!==null')
 key('Escape')
 print('WEB CHECK OK',json.dumps({'before':start,'moved':moved,'saved':saved,'restored':restored,**status}),flush=True)
 b.close()
 assert not errors,errors
