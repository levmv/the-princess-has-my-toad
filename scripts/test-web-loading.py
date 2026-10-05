#!/usr/bin/env python3
"""Loading/re-entry and physical pixel regression in an owned Chromium context."""
import argparse, json, time
from playwright.sync_api import sync_playwright
p=argparse.ArgumentParser()
p.add_argument('--url',default='http://127.0.0.1:18765/?lang=ru')
p.add_argument('--browser',default='/usr/bin/google-chrome')
p.add_argument('--hardware',action='store_true')
a=p.parse_args()
with sync_playwright() as pw:
 args=['--no-sandbox','--mute-audio','--use-angle=gl' if a.hardware else '--use-angle=swiftshader']
 if not a.hardware:args+=['--enable-unsafe-swiftshader']
 browser=pw.chromium.launch(executable_path=a.browser,headless=True,args=args)
 for dpr,width,height in [(1,1280,900),(1.5,1280,680),(2,1280,900),(1,900,700)]:
  page=browser.new_page(viewport={'width':width,'height':height},device_scale_factor=dpr)
  errors=[]
  page.on('pageerror',lambda e:errors.append(str(e)))
  page.on('console',lambda m:print('CONSOLE',m.type,m.text[:500],flush=True))
  page.add_init_script('''window.bootProbe={frames:0,maxGap:0,progress:[]};
   let previous=0;
   function sample(now){if(previous)bootProbe.maxGap=Math.max(bootProbe.maxGap,now-previous);previous=now;bootProbe.frames++;
    const meter=document.getElementById('boot-meter');if(meter){const value=Number(meter.getAttribute('aria-valuenow'));if(bootProbe.progress.at(-1)!==value)bootProbe.progress.push(value);}
    if(typeof ready==='undefined'||!ready)requestAnimationFrame(sample);
   }requestAnimationFrame(sample);''')
  t=time.perf_counter();page.goto(a.url)
  page.wait_for_function('typeof wasm!=="undefined"&&wasm&&wasm.toad_metric(23)>=6',timeout=30000)
  if dpr==1:page.screenshot(path='build/web-boot-loading.png')
  page.wait_for_function('ready',timeout=30000)
  elapsed=(time.perf_counter()-t)*1000
  page.screenshot(path=f'build/web-boot-ready-{width}-{dpr}.png')
  assert page.locator('#start').is_enabled()
  assert page.evaluate('progress===1 && bootProbe.progress.length>8 && bootProbe.frames>8')
  page.locator('#start').click();page.wait_for_function('running&&wasm.toad_metric(0)>3')
  def size():
   return page.evaluate('({canvas:[canvas.width,canvas.height],css:[canvas.getBoundingClientRect().width,canvas.getBoundingClientRect().height],render:[wasm.toad_metric(24),wasm.toad_metric(25)],scene:[wasm.toad_metric(26),wasm.toad_metric(27)],dpr:devicePixelRatio})')
  def check_size(s):
   assert all(abs(s['canvas'][i]-s['css'][i]*dpr)<=.51 for i in range(2)),s
   assert s['canvas']==s['render']==s['scene'],s
  initial=size();check_size(initial)
  # Browser backing pixels must never replace the native window preferences:
  # a short canvas used to make *all* settings writes fail validation.
  def saved_settings():
   return page.evaluate('JSON.parse(atob(localStorage.getItem("the-princess-has-my-toad/config/settings.json")))')
  page.keyboard.press('m')
  page.wait_for_function('JSON.parse(atob(localStorage.getItem("the-princess-has-my-toad/config/settings.json")))?.muted===true')
  preferences=saved_settings()
  assert [preferences['width'],preferences['height']]==[1280,800],preferences
  # Menu mouse hit testing also needs the correct backing-pixel transform.
  rect=page.locator('#canvas').bounding_box();scale=min(initial['render'][0]/1280,initial['render'][1]/800)
  page.mouse.click(rect['x']+rect['width']/2,rect['y']+526*scale/dpr,delay=85)
  page.wait_for_timeout(150)
  # Fresh root has Quit last; select it from a known top using Home is unsupported.
  # Escape leaves the submenu entered by the above click, then click root Quit.
  page.keyboard.press('Escape');page.wait_for_timeout(150)
  page.mouse.click(rect['x']+rect['width']/2,rect['y']+652*scale/dpr,delay=85)
  page.wait_for_function('!running&&parked',timeout=10000)
  assert page.locator('#start').is_enabled()
  before=page.evaluate('({memory:wasm.memory.buffer.byteLength,steps:[...bootTimings.steps],resources:performance.getEntriesByType("resource").filter(e=>e.name.includes("game.wasm")).length})')
  t=time.perf_counter();page.locator('#start').click();page.wait_for_function('running')
  reentry=(time.perf_counter()-t)*1000
  assert page.evaluate('performance.getEntriesByType("resource").filter(e=>e.name.includes("game.wasm")).length')==before['resources']
  assert page.evaluate('bootTimings.steps')==before['steps']
  page.set_viewport_size({'width':1093,'height':747});page.wait_for_timeout(250);resized=size();check_size(resized)
  page.locator('#fullscreen').click();page.wait_for_function('document.fullscreenElement!==null');page.wait_for_timeout(250);fullscreen=size();check_size(fullscreen)
  page.evaluate('document.exitFullscreen()');page.wait_for_timeout(250);check_size(size())
  page.keyboard.press('m')
  page.wait_for_function('JSON.parse(atob(localStorage.getItem("the-princess-has-my-toad/config/settings.json")))?.muted===false')
  assert saved_settings()=={**preferences,'muted':False}
  if width==900:
   assert initial['canvas'][0]<960 and initial['canvas'][1]<600,initial
   page.keyboard.press('m')
   page.wait_for_function('JSON.parse(atob(localStorage.getItem("the-princess-has-my-toad/config/settings.json")))?.muted===true')
   page.reload();page.wait_for_function('ready');page.locator('#start').click();page.wait_for_function('running&&wasm.toad_metric(0)>3')
   page.keyboard.press('m')
   page.wait_for_function('JSON.parse(atob(localStorage.getItem("the-princess-has-my-toad/config/settings.json")))?.muted===false')
   assert saved_settings()=={**preferences,'muted':False},'Settings did not survive a browser reload'
  print('LOADING CHECK OK',json.dumps({'ready_ms':elapsed,'reentry_ms':reentry,'initial':initial,'resized':resized,'fullscreen':fullscreen,'boot':page.evaluate('bootTimings'),'probe':page.evaluate('bootProbe'),'memory':before['memory']}),flush=True)
  assert not errors,errors
  page.close()
 browser.close()
