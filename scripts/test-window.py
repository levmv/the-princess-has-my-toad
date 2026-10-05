#!/usr/bin/env python3
"""Exercise an owned test window via XTEST; never attaches by title alone.
Run the game first with isolated --save-dir and --config-dir, then supply its
PID, the nested test display and those directories. Requires ffmpeg/libXtst.
"""
import argparse
import ctypes as C
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import time

p = argparse.ArgumentParser()
p.add_argument('--display', required=True)
p.add_argument('--pid', required=True, type=int)
p.add_argument('--data', required=True)
p.add_argument('--config', required=True)
p.add_argument('--output', default='build/window-check')
p.add_argument('--resume-check', action='store_true')
p.add_argument('--death-check', action='store_true')
p.add_argument('--cheat-check', action='store_true')
p.add_argument('--record-check', action='store_true')
p.add_argument('--replay-video', help='Capture the owned replay window to an MP4 until playback exits.')
a = p.parse_args()
root = Path(__file__).resolve().parents[1]
cmd = Path(f'/proc/{a.pid}/cmdline').read_bytes().split(b'\0')
assert f'--save-dir={a.data}'.encode() in cmd and f'--config-dir={a.config}'.encode() in cmd
assert b'--no-audio' in cmd, 'Use an isolated silent test launch.'
x = C.CDLL('libX11.so.6')
xt = C.CDLL('libXtst.so.6')
D = C.c_void_p
U = C.c_ulong
x.XOpenDisplay.argtypes = [C.c_char_p]; x.XOpenDisplay.restype = D
x.XDefaultRootWindow.argtypes = [D]; x.XDefaultRootWindow.restype = U
x.XQueryTree.argtypes = [D,U,C.POINTER(U),C.POINTER(U),C.POINTER(C.POINTER(U)),C.POINTER(C.c_uint)]
x.XInternAtom.argtypes = [D,C.c_char_p,C.c_int]; x.XInternAtom.restype = U
x.XGetWindowProperty.argtypes = [D,U,U,C.c_long,C.c_long,C.c_int,U,C.POINTER(U),C.POINTER(C.c_int),C.POINTER(U),C.POINTER(U),C.POINTER(C.POINTER(C.c_ubyte))]
x.XFree.argtypes = [D]
x.XSetInputFocus.argtypes = [D,U,C.c_int,U]
x.XStringToKeysym.argtypes = [C.c_char_p]; x.XStringToKeysym.restype = U
x.XKeysymToKeycode.argtypes = [D,U]; x.XKeysymToKeycode.restype = C.c_ubyte
x.XFlush.argtypes = [D]
x.XGetGeometry.argtypes = [D,U,C.POINTER(U),C.POINTER(C.c_int),C.POINTER(C.c_int),C.POINTER(C.c_uint),C.POINTER(C.c_uint),C.POINTER(C.c_uint),C.POINTER(C.c_uint)]
x.XTranslateCoordinates.argtypes = [D,U,U,C.c_int,C.c_int,C.POINTER(C.c_int),C.POINTER(C.c_int),C.POINTER(U)]
x.XMoveWindow.argtypes = [D,U,C.c_int,C.c_int]
x.XWarpPointer.argtypes = [D,U,U,C.c_int,C.c_int,C.c_uint,C.c_uint,C.c_int,C.c_int]
xt.XTestFakeButtonEvent.argtypes = [D,C.c_uint,C.c_int,U]
xt.XTestFakeKeyEvent.argtypes = [D,C.c_uint,C.c_int,U]
d = x.XOpenDisplay(a.display.encode())
assert d
r = x.XDefaultRootWindow(d)
parent, queried_root, children, count = U(), U(), C.POINTER(U)(), C.c_uint()
assert x.XQueryTree(d,r,C.byref(queried_root),C.byref(parent),C.byref(children),C.byref(count))
atom = x.XInternAtom(d,b'_NET_WM_PID',0)
window = None
for w in children[:count.value]:
    typ, form, n, left, data = U(), C.c_int(), U(), U(), C.POINTER(C.c_ubyte)()
    x.XGetWindowProperty(d,w,atom,0,1,0,0,C.byref(typ),C.byref(form),C.byref(n),C.byref(left),C.byref(data))
    if n.value and C.cast(data,C.POINTER(U))[0] == a.pid: window = w
    if data: x.XFree(data)
x.XFree(children)
assert window, 'No window belongs to that PID on the specified display.'
x.XSetInputFocus(d,window,2,0)
if not a.resume_check: x.XWarpPointer(d,0,r,0,0,0,0,1850,1000)
x.XFlush(d)
time.sleep(.5)

def key(name, hold=.18):
    # Xephyr has no window manager to restore focus after a borderless resize.
    # Send each test action to the window whose PID we explicitly verified.
    x.XSetInputFocus(d,window,2,0); x.XFlush(d)
    code = x.XKeysymToKeycode(d,x.XStringToKeysym(name.encode()))
    assert code
    xt.XTestFakeKeyEvent(d,code,1,0); x.XFlush(d)
    time.sleep(hold)
    xt.XTestFakeKeyEvent(d,code,0,0); x.XFlush(d)
    time.sleep(.9)

def click(px, py):
    # This test's logical and physical dimensions are 1280x800 until F11.
    x.XSetInputFocus(d,window,2,0)
    x.XWarpPointer(d,0,window,0,0,0,0,px,py);x.XFlush(d);time.sleep(.2)
    xt.XTestFakeButtonEvent(d,1,1,0);x.XFlush(d);time.sleep(.2)
    xt.XTestFakeButtonEvent(d,1,0,0);x.XFlush(d);time.sleep(.9)

def save():
    target = Path(a.data, 'quick.nvs')
    before = target.stat().st_mtime_ns if target.exists() else 0
    key('F5')
    deadline = time.monotonic()+8
    while not target.exists() or target.stat().st_mtime_ns == before:
        assert time.monotonic() < deadline, 'The quick-save action was not processed.'
        time.sleep(.1)
    return json.loads(subprocess.check_output([str(root/'build/persistence-test'),'inspect',a.data],cwd=root))

def distance(first, second):
    return math.dist(first['position'],second['position'])

def screenshot(suffix):
    # A bare Xephyr has no WM to remove the former window border offset on
    # borderless resize. Keep the explicitly owned window inside its root.
    x.XMoveWindow(d,window,0,0);x.XFlush(d);time.sleep(.15)
    rr, xx, yy, ww, hh, border, depth = U(), C.c_int(), C.c_int(), C.c_uint(), C.c_uint(), C.c_uint(), C.c_uint()
    assert x.XGetGeometry(d,window,C.byref(rr),C.byref(xx),C.byref(yy),C.byref(ww),C.byref(hh),C.byref(border),C.byref(depth))
    child = U()
    x.XTranslateCoordinates(d,window,r,0,0,C.byref(xx),C.byref(yy),C.byref(child))
    subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-f','x11grab','-draw_mouse','0','-video_size',f'{ww.value}x{hh.value}','-i',f'{a.display}+{xx.value},{yy.value}','-frames:v','1','-y',f'{a.output}-{suffix}.png'],check=True)
    return ww.value, hh.value

def is_bsod(suffix):
    pixel = subprocess.check_output(['ffmpeg','-v','error','-i',f'{a.output}-{suffix}.png','-vf','crop=1:1:iw/2:ih/2','-frames:v','1','-pix_fmt','rgb24','-f','rawvideo','-'])
    return pixel == bytes((13,27,155))

def quit_running_game():
    # The input test can finish at a live doorway. Pause with focus loss before
    # navigating menus: a fatal hit just after the last save may show BSOD.
    def pause():
        x.XSetInputFocus(d,r,2,0);x.XFlush(d);time.sleep(.5)
        x.XSetInputFocus(d,window,2,0);x.XFlush(d);time.sleep(.8)
    pause(); screenshot('before-quit')
    if is_bsod('before-quit'):
        key('Return'); pause(); screenshot('before-quit')
        assert not is_bsod('before-quit')
    click(200,654)

if a.replay_video:
    assert any(v.startswith(b'--replay=') for v in cmd)
    with open(a.replay_video+'.log','w') as log:
        video=subprocess.Popen(['ffmpeg','-hide_banner','-loglevel','warning','-f','x11grab','-framerate','30','-draw_mouse','0','-window_id',str(window),'-i',a.display,'-an','-c:v','libx264','-preset','veryfast','-crf','22','-pix_fmt','yuv420p','-y',a.replay_video],stdin=subprocess.PIPE,stdout=subprocess.DEVNULL,stderr=log)
        deadline=time.monotonic()+120
        while time.monotonic()<deadline:
            status=Path(f'/proc/{a.pid}/stat')
            if not status.exists() or status.read_text().rsplit(')',1)[1].split()[0]=='Z': break
            time.sleep(.1)
        else:
            video.terminate()
            raise AssertionError('Replay did not exit within the capture limit.')
        if video.poll() is None:
            try: video.communicate(b'q\n',timeout=15)
            except BrokenPipeError: video.wait(timeout=15)
        assert Path(a.replay_video).stat().st_size>1000
    print('REPLAY VIDEO CAPTURED:',a.replay_video,'(nested software display; not a performance measurement)')
    sys.exit(0)

if a.death_check:
    # The dedicated fixture is loaded with --continue. Read two saves to see
    # whether initial focus loss paused it; don't assume a window manager.
    first = save(); second = save()
    if first['time'] == second['time']: key('Escape')
    xt.XTestFakeButtonEvent(d,1,1,0); x.XFlush(d)
    target = Path(a.data, 'quick.nvs')
    deadline = time.monotonic()+90
    while True:
        time.sleep(2)
        screenshot('bsod')
        blue = is_bsod('bsod')
        if blue: break
        assert time.monotonic() < deadline, 'The fatal projectile did not show BSOD.'
    stamp = target.stat().st_mtime_ns
    key('F5')
    assert target.stat().st_mtime_ns == stamp, 'Held fire allowed a retry/save behind the BSOD.'
    screenshot('held-fire-bsod')
    assert is_bsod('held-fire-bsod')
    # Keep fire held so display shortcuts cannot acknowledge the death panel.
    key('F11'); large = screenshot('bsod-borderless')
    assert is_bsod('bsod-borderless')
    key('F11'); small = screenshot('bsod-window')
    assert is_bsod('bsod-window') and large[0] > small[0] and small == (1280,800)
    # Regaining focus with fire still down also must not restart the game.
    x.XSetInputFocus(d,r,2,0);x.XFlush(d);time.sleep(.4)
    x.XSetInputFocus(d,window,2,0);x.XFlush(d);time.sleep(.4)
    xt.XTestFakeButtonEvent(d,1,0,0);x.XFlush(d);time.sleep(.8)
    key('Return')
    after = save()
    assert after['deaths'] == 1 and after['health'] >= 65, after
    assert after['shots'] == 0, 'Held fire leaked across checkpoint retry.'
    screenshot('retry')
    quit_running_game()
    print(json.dumps({'status':'DEATH WINDOW CHECK OK','restored':after},indent=2))
    sys.exit(0)

if a.record_check:
    assert any(v.startswith(b'--record=') for v in cmd), 'Launch the owned game with --record and --start.'
    key('w',1.0); key('space',.25); key('d',.5); key('f')
    # Pause/resume preserves recording; released input cannot leak across it.
    key('Escape'); time.sleep(.4); key('Escape'); key('a',.5)
    for letter in 'iddqd': key(letter, .04)
    screenshot('recording')
    key('Escape')
    for _ in range(5): key('Down')
    key('Return')
    target=Path(next(v[9:].decode() for v in cmd if v.startswith(b'--record=')))
    deadline=time.monotonic()+10
    while not target.exists():
        assert time.monotonic()<deadline, 'Recording was not written on normal exit.'
        time.sleep(.1)
    print(json.dumps({'status':'RECORD WINDOW CHECK OK','file':str(target),'bytes':target.stat().st_size}))
    sys.exit(0)

if a.resume_check:
    before = json.loads(subprocess.check_output([str(root/'build/persistence-test'),'inspect',a.data],cwd=root))
    key('Escape')
    after = save()
    assert distance(before,after)<.04 and before['shots']==after['shots'], (before,after)
    screenshot('continued')
    for _ in range(5): key('Down')
    key('Return')
    print(json.dumps({'status':'CONTINUE CHECK OK','before':before,'after':after},indent=2))
    sys.exit(0)

if a.cheat_check:
    key('Return'); key('Return'); key('Escape'); key('Return')
    for letter in 'idd': key(letter)
    key('Escape')
    for letter in 'qdiddqd': key(letter)
    paused = save()
    assert paused['anvil']==0, 'Menu text incorrectly triggered a gameplay cheat.'
    key('Escape')
    for letter in 'qd': key(letter)
    partial = save()
    assert partial['anvil']==0, 'A sequence incorrectly crossed the pause boundary.'
    for letter in 'iddqd': key(letter)
    active = save()
    assert active['anvil'] in (1,2), active
    screenshot('anvil')
    key('F9')
    restored = save()
    assert restored['anvil'] in (1,2,3) and restored['anvil_target']==active['anvil_target'], (active,restored)
    key('Escape')
    for _ in range(5): key('Down')
    key('Return')
    print(json.dumps({'status':'IDDQD WINDOW CHECK OK','menu':paused,'partial':partial,'active':active,'restored':restored},indent=2))
    sys.exit(0)

# Replay intro returns to the front menu without creating a save.
key('Down'); key('Down'); key('Return')
screenshot('intro-replay')
key('Escape')
assert not Path(a.data,'checkpoint.nvs').exists()
# Root -> new game -> intro -> fighter. Back leaves the existing run alone.
key('Up'); key('Up'); key('Return'); key('Return')
screenshot('intro')
key('Escape'); key('Escape')
assert not Path(a.data,'checkpoint.nvs').exists()
key('Return'); key('Escape'); key('Right'); key('Tab')
click(200,367); click(200,429)
screenshot('fighter-lora-ru')
click(250,650); time.sleep(.8)
first = save()
screenshot('lora-game')
assert first['hero']==1, first
assert json.loads(Path(a.config,'settings.json').read_text())['language']==1

key('w',1.2)
key('Escape')
paused = save()
assert distance(first,paused)>2, (first,paused)
time.sleep(.8)
again = save()
assert paused['time']==again['time'] and paused['position']==again['position'], 'Pause changed the simulation.'
screenshot('pause')
# Cancelling a new-game intro from pause must leave the live run and hero intact.
for _ in range(3): key('Down')
key('Return'); key('Return'); key('Escape'); key('Escape'); key('Escape')
cancelled = save()
assert cancelled['time']==paused['time'] and cancelled['position']==paused['position'] and cancelled['hero']==1, cancelled
key('Escape'); key('w',1.2)
key('F9'); key('Escape')
restored = save()
assert distance(restored,paused)<.04 and restored['shots']==paused['shots'] and restored['hero']==1, (restored,paused)
# Focus loss must pause and clear pending input.
key('Escape')
x.XSetInputFocus(d,r,2,0); x.XFlush(d); time.sleep(.9)
x.XSetInputFocus(d,window,2,0); x.XFlush(d); time.sleep(.4)
unfocused = save(); time.sleep(.6); refocused = save()
assert unfocused['time']==refocused['time'], 'Focus loss failed to pause.'
# Window and borderless transitions remain paused and preserve their size.
key('F11'); time.sleep(.5)
large = screenshot('borderless')
key('F11'); time.sleep(.5)
small = screenshot('window')
assert large[0]>small[0] and small==(1280,800), (large,small)
# Settings: mouse, inversion, effects, 3D scale, then Forward -> T.
for _ in range(4): key('Down')
key('Return'); key('Right'); key('Down'); key('Return'); key('Down'); key('Left')
for _ in range(3): key('Down')
key('Left')  # Music has its own persisted volume.
for _ in range(3): key('Down')
key('Left'); key('Down')
key('Return'); key('Return'); key('t')
screenshot('bindings')
key('Escape'); key('Escape')
cfg=json.loads(Path(a.config,'settings.json').read_text())
assert cfg['sensitivity']>.0023 and cfg['invert_y'] and cfg['effects']<1 and cfg['render_scale']==.75 and cfg['music']<.55 and cfg['bindings']['Forward']==84, cfg
key('Escape')
base=save(); key('w',.4); old_key=save()
assert distance(base,old_key)<.04, 'Old binding remained active.'
key('t',1.2); new_key=save()
assert distance(new_key,old_key)>2, 'The new binding was not applied.'
quit_running_game()
print(json.dumps({'status':'WINDOW CHECK OK','initial':first,'paused':paused,'restored':restored,'borderless':large,'window':small,'rebound':new_key},indent=2))
