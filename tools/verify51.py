"""Lua 5.1 回归，使用本机已有 lupa；网络仍是模拟。"""
from pathlib import Path
import sys,os,zipfile
ROOT=Path(__file__).resolve().parents[1]
deps=Path(sys.argv[1]) if len(sys.argv)>1 else Path(r'C:\Users\Robin\.codex\visualizations\2026\10\07\01a1176a-14fa-7351-a6c1-8db6d4add694\autopilot-build\testdeps')
sys.path.insert(0,str(deps))
from lupa.lua51 import LuaRuntime
runtime=LuaRuntime(unpack_returned_tuples=True);os.chdir(ROOT)
parse=runtime.eval('function(s,n) local f,e=loadstring(s,n); return f~=nil,e end')
for p in ROOT.rglob('*.lua'):
    ok,error=parse(p.read_text(encoding='utf8'),str(p))
    assert ok,(p,error)
print('PASS: all Lua source compiles with Lua 5.1',flush=True)
with zipfile.ZipFile(Path("D:/Steam/steamapps/common/Don't Starve Together/data/databundles/scripts.zip")) as archive:
    runtime.globals().write_debug_integration_fixture=lambda text:(ROOT/'reviews/queen-debug-offline-integration.log').write_text(text,encoding='utf8')
    runtime.globals().write_debug_fixture=lambda text:(ROOT/'reviews/queen-debug-offline-fixture.log').write_text(text,encoding='utf8')
    runtime.globals().read_source=lambda path:archive.read('scripts/'+path).decode('utf8')
    runtime.globals().read_3014_dodge=lambda:(ROOT/'scripts/shadowself/native/engine/Dodge.lua').read_text(encoding='utf8')
    suites=['offline','render_lifecycle','conversation','daily','speech','voice','control','actions_clock','merge','native_merge','coordinator','maxwell','personality','thought_cooking','batch_cooking','navigation','fishing_queen','battlemusic','secondary_travel','dodge_cane','combat103','native_food','grinding','chat_ui','knowledge','combat112','combat114','combat115','combat116','combat117','combat118','combat119','combat120','combat121','combat122','combat123','combat124','combat125','combat126','combat128','queen_debug_removed','queen_flute_recovery','queen_phase1','queen_phase3','server_combat','boss140','boss141','boss142','network_movement','network_combat','combat144','native_embedded','walka_original','swing146','combat147']
    runtime.globals().read_astra_source=lambda path:(Path('D:/Steam/steamapps/workshop/content/322330/3816458126/scripts')/path).read_text(encoding='utf8')
    suites.extend(['arena_protocol','arena_lifecycle','arena_planning','arena_healing','arena_runtime'])
    for name in (sys.argv[2].split(',') if len(sys.argv)>2 else suites):
        runtime.execute((ROOT/'tests'/f'{name}.lua').read_text(encoding='utf8'))
print('PASS: Lua 5.1 regression complete; gameplay remains untested')
