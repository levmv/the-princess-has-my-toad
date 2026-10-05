/* Browser hosting only: loading, sizing and activation. Gameplay stays in Odin. */
const canvas = document.getElementById('canvas');
const cover = document.getElementById('cover');
const startButton = document.getElementById('start');
const captureButton = document.getElementById('capture');
const statusLine = document.getElementById('status');
const meter = document.getElementById('boot-meter');
const bootNumber = document.getElementById('boot-number');
const bootDetail = document.getElementById('boot-detail');
const text = {
 ru: {
  glideTip:'Планер: в воздухе отпусти пробел, нажми снова и удерживай.',
  kickTip:'F — пинок.',
  premise:'Принцесса похитила жабу.\nБашня ждёт.',start:'Начать',resume:'Вернуться в башню',retry:'Повторить',ready:'Башня на связи.',loading:'Устанавливаем связь…',requirements:'Клавиатура и мышь · WebGL 2',keys:'WASD — движение · мышь — взгляд · Esc — пауза',fullscreen:'Полный экран',capture:'Нажми, чтобы управлять мышью',ended:'Башня всё ещё ждёт.',failed:'Не удалось запустить игру.',unsupported:'Нужен браузер с WebGL 2.',bootLabel:'Связь с башней',download:'Принимаем сигнал',compile:'Запускаем башню',phases:['Проверяем память','Включаем свет','Восстанавливаем надписи','Проявляем поверхности','Собираем обитателей','Готовим героев','Прокладываем тени','Открываем башню','Настраиваем звук','Последний штрих'],complete:'Жаба на месте. Пока.',paused:'Можно вернуться без загрузки.'},
 en: {
  glideTip:'Glide: release Space in mid-air, then press and hold it again.',
  kickTip:'F — kick.',
  premise:'The princess has stolen the toad.\nThe tower awaits.',start:'Enter',resume:'Return to the tower',retry:'Try again',ready:'Tower online.',loading:'Establishing contact…',requirements:'Keyboard & mouse · WebGL 2',keys:'WASD — move · mouse — look · Esc — pause',fullscreen:'Fullscreen',capture:'Click to capture the mouse',ended:'The tower is still waiting.',failed:'Could not start the game.',unsupported:'A browser with WebGL 2 is required.',bootLabel:'Tower connection',download:'Receiving signal',compile:'Starting the tower',phases:['Checking memory','Turning on the lights','Restoring the lettering','Revealing the surfaces','Assembling the inhabitants','Preparing the heroes','Tracing the shadows','Opening the tower','Tuning the sound','Finishing touches'],complete:'Toad accounted for. For now.',paused:'Ready to return. No reload needed.'}
};
let language = new URLSearchParams(location.search).get('lang') || (navigator.language.startsWith('ru') ? 'ru' : 'en');
if (!text[language]) language = 'en';
let ready = false, running = false, wasm = null, wasLocked = false;
let phase = 'download', bootStage = 0, progress = 0, transferred = 0, totalBytes = 0;
let parked = false, failed = false, bootStarted = 0, lastWidth = 0, lastHeight = 0;
const bootTimings = {download:0,compile:0,total:0,steps:[],maxStep:0};
function updateProgress(value) {
 progress = Math.max(progress,Math.min(1,value));
 const percent = Math.floor(progress*100);
 cover.style.setProperty('--boot',String(progress));
 meter.setAttribute('aria-valuenow',String(percent));
 bootNumber.textContent = String(percent).padStart(3,'0')+'%';
 const stageText = phase==='prepare' ? text[language].phases[Math.min(9,bootStage)] : text[language][phase];
 document.getElementById('boot-phase').textContent = failed ? text[language].failed : (ready ? text[language].ready : stageText);
 bootDetail.textContent = failed ? '' : (ready ? text[language][parked?'paused':'complete'] : (phase==='download' && transferred ? `${(transferred/1048576).toFixed(1)}${totalBytes?' / '+(totalBytes/1048576).toFixed(1):''} MB` : ''));
 cover.dataset.state = failed ? 'error' : (ready ? 'ready' : 'loading');
}
function localize() {
 document.documentElement.lang = language;
 for (const id of ['premise','requirements','glideTip','kickTip','keys','fullscreen','capture']) document.getElementById(id).innerText = text[language][id];
 startButton.textContent = text[language][failed?'retry':(parked?'resume':'start')];
 statusLine.textContent = text[language][failed?'failed':(parked?'ended':(ready?'ready':'loading'))];
 meter.setAttribute('aria-label',text[language].bootLabel);
 for (const lang of ['ru','en']) document.getElementById(lang).setAttribute('aria-pressed',String(lang===language));
 updateProgress(progress);
}
for (const lang of ['ru','en']) document.getElementById(lang).onclick = () => {language=lang;localize();};
localize();
function fail(error) {
 failed=true;running=false;cover.hidden=false;captureButton.hidden=true;startButton.disabled=false;
 localize();
 console.error('THE PRINCESS HAS MY TOAD:',error);
 if (document.pointerLockElement) document.exitPointerLock();
}
window.addEventListener('error',event=>{
 if (event.target instanceof HTMLScriptElement && event.target.id==='game-runtime') fail(new Error('Runtime download failed'));
},true);
const odinMemoryInterface = new odin.WasmMemoryInterface();
odinMemoryInterface.setIntSize(4);
const odinImports = odin.setupDefaultImports(odinMemoryInterface);
var Module = {
 canvas,
 print: (...args) => console.log(...args),
 printErr: (...args) => console.error(...args),
 onAbort: fail,
 instantiateWasm(imports, success) {
  const started=performance.now();
  // Every runtime file uses the same build query, avoiding stale JS/wasm pairs.
  const revision=new URL(document.getElementById('game-runtime').src).search;
  fetch('game.wasm'+revision).then(async response => {
   if (!response.ok) throw new Error('HTTP '+response.status);
   totalBytes=response.headers.get('Content-Encoding')?0:Number(response.headers.get('Content-Length')||0);
   const allImports={...odinImports,...imports};
   if (WebAssembly.instantiateStreaming && response.body) {
    const reader=response.body.getReader();
    const stream=new ReadableStream({async pull(controller) {
     const {done,value}=await reader.read();
     if (done) {
      bootTimings.download=performance.now()-started;
      phase='compile';updateProgress(.18);controller.close();return;
     }
     transferred+=value.length;
     updateProgress(totalBytes?Math.min(.18,transferred/totalBytes*.18):0);
     controller.enqueue(value);
    },cancel(reason){return reader.cancel(reason);}});
    return WebAssembly.instantiateStreaming(new Response(stream,{headers:{'Content-Type':'application/wasm'}}),allImports);
   }
   const bytes=await response.arrayBuffer();
   transferred=bytes.byteLength;bootTimings.download=performance.now()-started;
   phase='compile';updateProgress(.18);
   return WebAssembly.instantiate(bytes,allImports);
  }).then(result => {
   bootTimings.compile=performance.now()-started-bootTimings.download;
   wasm=result.instance.exports;
   odinMemoryInterface.setExports(wasm);odinMemoryInterface.setMemory(wasm.memory);
   success(result.instance);
  }).catch(fail);
  return {};
 },
 onRuntimeInitialized() {
  try {
   wasm._start();
   const probe=document.createElement('canvas');
   const gl=probe.getContext('webgl2');
   if (!gl) throw new Error(text[language].unsupported);
   gl.getExtension('WEBGL_lose_context')?.loseContext();
   phase='prepare';bootStarted=performance.now();updateProgress(.2);
   wasm.toad_prepare(language==='ru'?1:0);
   requestAnimationFrame(prepare);
  } catch(error) { fail(error); }
 }
};
function prepare() {
 if (failed) return;
 try {
  // Show the current work unit before entering wasm; no synchronous five-second boot.
  bootStage=wasm.toad_metric(23);updateProgress(progress);
  const t=performance.now(), fraction=wasm.toad_boot_step();
  bootTimings.maxStep=Math.max(bootTimings.maxStep,performance.now()-t);
  if (fraction<0) throw new Error('Preparation failed');
  resize();
  updateProgress(.2+fraction*.8);
  if (fraction>=1) {
   ready=true;startButton.disabled=false;
   bootTimings.total=performance.now()-bootStarted;
   bootTimings.steps=Array.from({length:10},(_,i)=>wasm.toad_metric(30+i));
   localize();return;
  }
  requestAnimationFrame(prepare);
 } catch(error) { fail(error); }
}
function resize() {
 if (!wasm || wasm.toad_metric(23)<1) return;
 const rect=canvas.getBoundingClientRect();
 // Backing pixels match physical display pixels; 3D scaling stays an explicit setting.
 const dpr=window.devicePixelRatio||1;
 const width=Math.max(1,Math.round(rect.width*dpr)), height=Math.max(1,Math.round(rect.height*dpr));
 if (width!==lastWidth || height!==lastHeight || canvas.width!==width || canvas.height!==height) {
  wasm.toad_resize(width,height);lastWidth=width;lastHeight=height;
  // Emscripten's fullscreen helper assumes screen-sized CSS. The stage owns
  // layout, including zoom/fractional scaling and embedded/fullscreen sizing.
  canvas.style.removeProperty('width');canvas.style.removeProperty('height');
 }
}
function frame() {
 if (!running) return;
 try {
  resize(); // Also catches moving a window between monitors with different DPI.
  if (!wasm.toad_frame()) {
   running=false;wasm.toad_suspend();parked=true;ready=true;
   language=wasm.toad_metric(29)===1?'ru':'en';
   cover.hidden=false;captureButton.hidden=true;startButton.disabled=false;
   localize();return;
  }
  captureButton.hidden=!wasm.toad_playing() || document.pointerLockElement===canvas;
  requestAnimationFrame(frame);
 } catch(error) { fail(error); }
}
startButton.onclick = () => {
 if (failed) {location.reload();return;}
 if (!ready || running) return;
 try {
  // miniaudio's pinned WebAudio backend unlocks suspended contexts on this gesture.
  window.miniaudio?.unlock();
  if (!wasm.toad_start(language==='ru'?1:0)) throw new Error('Activation failed');
  cover.hidden=true;canvas.focus();running=true;resize();requestAnimationFrame(frame);
 } catch(error) { fail(error); }
};
captureButton.onclick=()=>{canvas.focus();canvas.requestPointerLock();};
canvas.addEventListener('contextmenu',event=>event.preventDefault());
canvas.addEventListener('keydown',event=>{if(!event.ctrlKey&&!event.metaKey&&event.code!=='F11')event.preventDefault();});
canvas.addEventListener('wheel',event=>event.preventDefault(),{passive:false});
canvas.addEventListener('mousedown',()=>canvas.focus());
document.addEventListener('pointerlockchange',()=>{
 const locked=document.pointerLockElement===canvas;
 if (running && wasLocked && !locked) wasm.toad_pointer_lost();
 wasLocked=locked;
});
window.addEventListener('blur',()=>{if(running)wasm.toad_pointer_lost();});
document.addEventListener('visibilitychange',()=>{if(document.hidden&&running)wasm.toad_pointer_lost();});
window.addEventListener('resize',resize);
document.addEventListener('fullscreenchange',resize);
new ResizeObserver(resize).observe(document.getElementById('stage'));
document.getElementById('fullscreen').onclick=()=>{
 const request=document.fullscreenElement?document.exitFullscreen():document.getElementById('stage').requestFullscreen();
 request?.catch(error=>console.warn('Fullscreen:',error));
};
