"""用现有 Lua DLL 编译源码并运行离线模拟；仅用于开发机验证。"""
from pathlib import Path
import ctypes,os,re,sys,zipfile
ROOT=Path(__file__).resolve().parents[1]
GAME=Path(r"D:\Steam\steamapps\common\Don't Starve Together\data")
DLL=Path(sys.argv[1]) if len(sys.argv)>1 else Path(r'C:\Users\Robin\.codex\visualizations\2026\10\01\01a0f67a-6692-72d2-8d63-4fe042cf18e5\lua-check\lua55.dll')
lua=ctypes.CDLL(str(DLL));P=ctypes.c_void_p;I=ctypes.c_int;S=ctypes.c_char_p
lua.luaL_newstate.restype=P
lua.luaL_openselectedlibs.argtypes=[P,I,I];lua.lua_close.argtypes=[P]
lua.luaL_loadfilex.argtypes=[P,S,S];lua.luaL_loadfilex.restype=I
lua.lua_pcallk.argtypes=[P,I,I,I,ctypes.c_ssize_t,P];lua.lua_pcallk.restype=I
lua.lua_tolstring.argtypes=[P,I,P];lua.lua_tolstring.restype=S
lua.lua_settop.argtypes=[P,I]
state=lua.luaL_newstate();lua.luaL_openselectedlibs(state,-1,0)
def err():return lua.lua_tolstring(state,-1,None).decode('utf8',errors='replace')
os.chdir(ROOT)
files=sorted(ROOT.rglob('*.lua'))
for p in files:
 if lua.luaL_loadfilex(state,str(p).encode(),None):raise RuntimeError(str(p)+': '+err())
 lua.lua_settop(state,0)
print('Lua 5.5 syntax OK:',len(files),'files (DST uses Lua 5.1; live verification required)',flush=True)
for p in [ROOT/'modmain.lua',*list((ROOT/'scripts').rglob('*.lua'))]:
 text=p.read_text(encoding='utf8')
 for forbidden in ['SendModRPC','AddNetwork(', 'SpawnPrefab(', 'Networking_Say(', 'QueryServer(', 'TheNet:Say(']:
  assert forbidden not in text,(p,forbidden)
 if 'SendRPCToServer' in text:assert p.relative_to(ROOT).as_posix() in ['scripts/shadowself/control/actions.lua','scripts/shadowself/legacy/action_library.lua','scripts/shadowself/zom/ActionQueue.lua'],p
network=zipfile.ZipFile(GAME/'databundles/scripts.zip').read('scripts/networkclientrpc.lua').decode()
actions='\n'.join((ROOT/p).read_text(encoding='utf8') for p in ['scripts/shadowself/control/actions.lua','scripts/shadowself/legacy/action_library.lua','scripts/shadowself/zom/ActionQueue.lua'])
for name in re.findall(r'RPC\.([A-Za-z]+)',actions):assert re.search(r'\b'+name+r'\s*=\s*function',network),name
print('Native game RPCs restricted to three audited action modules; no custom RPC, API or server chat',flush=True)
for asset in re.findall(r'Asset\("ANIM", "([^"]+)"\)',(ROOT/'modmain.lua').read_text(encoding='utf8')):
 assert (ROOT/asset).is_file() or (GAME/asset).is_file(),asset
print('All referenced animation assets exist',flush=True)
if lua.luaL_loadfilex(state,b'tests/offline.lua',None) or lua.lua_pcallk(state,0,0,0,0,None):raise RuntimeError(err())
if lua.luaL_loadfilex(state,b'tests/render_lifecycle.lua',None) or lua.lua_pcallk(state,0,0,0,0,None):raise RuntimeError(err())
if lua.luaL_loadfilex(state,b'tests/conversation.lua',None) or lua.lua_pcallk(state,0,0,0,0,None):raise RuntimeError(err())
if lua.luaL_loadfilex(state,b'tests/speech.lua',None) or lua.lua_pcallk(state,0,0,0,0,None):raise RuntimeError(err())
if lua.luaL_loadfilex(state,b'tests/voice.lua',None) or lua.lua_pcallk(state,0,0,0,0,None):raise RuntimeError(err())
if lua.luaL_loadfilex(state,b'tests/control.lua',None) or lua.lua_pcallk(state,0,0,0,0,None):raise RuntimeError(err())
if lua.luaL_loadfilex(state,b'tests/actions_clock.lua',None) or lua.lua_pcallk(state,0,0,0,0,None):raise RuntimeError(err())
if lua.luaL_loadfilex(state,b'tests/merge.lua',None) or lua.lua_pcallk(state,0,0,0,0,None):raise RuntimeError(err())
if lua.luaL_loadfilex(state,b'tests/personality.lua',None) or lua.lua_pcallk(state,0,0,0,0,None):raise RuntimeError(err())
if lua.luaL_loadfilex(state,b'tests/chat_ui.lua',None) or lua.lua_pcallk(state,0,0,0,0,None):raise RuntimeError(err())
if lua.luaL_loadfilex(state,b'tests/batch_cooking.lua',None) or lua.lua_pcallk(state,0,0,0,0,None):raise RuntimeError(err())
lua.lua_close(state)
