from pathlib import Path
import json, sys, zipfile, os

root=Path(__file__).resolve().parents[2]
spec=Path(__file__).resolve().parent
if os.environ.get('SCD_LUA_DEPS'):
    sys.path.insert(0,os.environ['SCD_LUA_DEPS'])
from lupa.lua51 import LuaRuntime, lua_type
lua=LuaRuntime(unpack_returned_tuples=True)
loader=lua.eval('function(text,name) return assert(loadstring(text,name)) end')
for p in (root/'shadow_combat_diary/scripts').glob('*.lua'):
    lua.globals().package.preload[p.stem]=loader(p.read_text(encoding='utf8'),p.name)
def plain(value):
    if lua_type(value)=='table':
        keys=list(value.keys())
        if keys and set(keys)==set(range(1,len(keys)+1)):return [plain(value[i]) for i in range(1,len(keys)+1)]
        return {str(k):plain(v) for k,v in value.items()}
    return value
def encode(value):return json.dumps(plain(value),ensure_ascii=False,separators=(',',':'))
records=[];reports=[]
lua.globals().encode_json=encode
lua.globals().capture_log=lambda s:records.append(str(s))
lua.globals().capture_report=lambda r:reports.append(plain(r))
parse=lua.eval('function(s,n) local f,e=loadstring(s,n);return f~=nil,e end')
for p in (root/'shadow_combat_diary').rglob('*.lua'):
    ok,error=parse(p.read_text(encoding='utf8'),str(p));assert ok,(p,error)
lua.execute((spec/'recorder_spec.lua').read_text(encoding='utf8'))
lua.execute((spec/'scd_analysis_spec.lua').read_text(encoding='utf8'))
lua.globals().modmain_source=(root/'shadow_combat_diary/modmain.lua').read_text(encoding='utf8')
lua.execute((spec/'modmain_spec.lua').read_text(encoding='utf8'))
game=Path(os.environ['DST_SCRIPTS_ZIP'])
with zipfile.ZipFile(game) as z:
    replica=z.read('scripts/components/health_replica.lua').decode()
    classified=z.read('scripts/prefabs/player_classified.lua').decode()
    assert all('function Health:'+m in replica for m in ['Max()','GetCurrent()','GetPercent()','IsTakingFireDamage()'])
    assert 'PushEvent("attacked", { isattackedbydanger' in classified
    assert 'PushEvent("healthdelta", data)' in classified
    inventory=z.read('scripts/prefabs/inventoryitem_classified.lua').decode()
    assert 'inst.percentused = net_byte' in inventory and 'inst.percentused:set(255)' in inventory
out=root/'outputs/shadow_combat_diary';out.mkdir(parents=True,exist_ok=True)
fixture=out/'test-client-log.txt'
fixture.write_text('\n'.join('[00:00:00]: '+line for line in records)+'\n[00:00:00]: [SCD] {broken\n',encoding='utf8')
sys.path.insert(0,str(root/'shadow_combat_diary/tools'))
from scd_transport import iter_records
transport_stats={}
decoded=list(iter_records(fixture,transport_stats))
deaths=[e for e in decoded if e.get('kind')=='death_report']
assert len(deaths)==4  # two deaths, plus two deliberate manual re-exports of the first
assert any(e['report']==reports[0] for e in deaths)
assert max(len(line.encode('utf8')) for line in records)<3000, 'every physical log record must fit engine print limits'
assert transport_stats['invalid']==1
chunks=[json.loads(line.split('[SCD] ',1)[1]) for line in records if line.startswith('[SCD] ') and '"kind":"record_chunk"' in line]
group=[e for e in chunks if e['session']==chunks[0]['session'] and e['seq']==chunks[0]['seq']]
assert len(group)>1
shuffled=out/'transport-reordered.jsonl'
shuffled.write_text('\n'.join(json.dumps(e,ensure_ascii=False) for e in reversed(group)),encoding='utf8')
assert len(list(iter_records(shuffled)))==1
shuffled.write_text('\n'.join(json.dumps(e,ensure_ascii=False) for e in group[:-1]),encoding='utf8')
stats={};assert not list(iter_records(shuffled,stats)) and stats['incomplete']==1
group[-1]['data']=('00' if group[-1]['data'][:2]!='00' else '01')+group[-1]['data'][2:]
shuffled.write_text('\n'.join(json.dumps(e,ensure_ascii=False) for e in group),encoding='utf8')
stats={};assert not list(iter_records(shuffled,stats)) and stats['invalid']==1
print('PASS chunked JSON round-trip, print-size bound, out-of-order, missing and corrupted chunks')
(out/'示例死亡反馈.md').write_text('> 此文件为离线模拟示例，不是真实对战。\n\n'+reports[0]['summary_text'],encoding='utf8')
print('PASS Lua 5.1 source compilation and installed build event/API contracts')
print(f'Fixture: {fixture}; {len(records)} structured records')
