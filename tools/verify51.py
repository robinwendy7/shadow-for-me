"""Lua 5.1 回归，使用本机已有 lupa；网络仍是模拟。"""
from pathlib import Path
import sys,os,zipfile
ROOT=Path(__file__).resolve().parents[1]
deps=sys.argv[1] if len(sys.argv)>1 else os.environ.get('LUA51_DEPS')
if deps: sys.path.insert(0,str(Path(deps)))
from lupa.lua51 import LuaRuntime
runtime=LuaRuntime(unpack_returned_tuples=True);os.chdir(ROOT)
# Match DST's undeclared-global read error for actual Weaver modules, including nested callbacks.
# Fixture globals remain live; known game globals may be deliberately nil before world setup.
runtime.execute("""
local gameglobals={TheWorld=true,TheSim=true,TUNING=true,EQUIPSLOTS=true,ACTIONS=true,Class=true,Vector3=true,GetTime=true}
local fileloader=package.loaders[2]
table.insert(package.loaders,2,function(name)
    if not name:match('^shadowself/control/weaver/') then return fileloader(name) end
    local loader=fileloader(name)
    if type(loader)~='function' then return loader end
    setfenv(loader,setmetatable({},{__index=function(_,key)
        local value=rawget(_G,key)
        if value~=nil or gameglobals[key] then return value end
        error("variable '"..tostring(key).."' is not declared",2)
    end,__newindex=function(_,key)error("unexpected Weaver global write: "..tostring(key),2)end}))
    return loader
end)
""")
parse=runtime.eval('function(s,n) local f,e=loadstring(s,n); return f~=nil,e end')
for p in ROOT.rglob('*.lua'):
    ok,error=parse(p.read_text(encoding='utf8'),str(p))
    assert ok,(p,error)
print('PASS: all Lua source compiles with Lua 5.1',flush=True)
steamapps=Path(os.environ['DST_STEAMAPPS']) if os.environ.get('DST_STEAMAPPS') else next(
    (p for p in [Path('D:/Steam/steamapps'),Path('E:/STEAM/steamapps'),Path('C:/Program Files (x86)/Steam/steamapps')]
     if (p/"common/Don't Starve Together/data/databundles/scripts.zip").is_file()), None)
if steamapps is None: raise SystemExit('Set DST_STEAMAPPS to your Steam steamapps directory')
with zipfile.ZipFile(steamapps/"common/Don't Starve Together/data/databundles/scripts.zip") as archive:
    runtime.globals().write_debug_integration_fixture=lambda text:(ROOT/'reviews/queen-debug-offline-integration.log').write_text(text,encoding='utf8')
    runtime.globals().write_debug_fixture=lambda text:(ROOT/'reviews/queen-debug-offline-fixture.log').write_text(text,encoding='utf8')
    runtime.globals().write_weaver_sim=lambda text:(ROOT/'reviews/weaver-source-timeline-simulation.csv').write_text(text,encoding='utf8')
    runtime.globals().read_source=lambda path:archive.read('scripts/'+path).decode('utf8')
    runtime.globals().read_3014_dodge=lambda:(ROOT/'scripts/shadowself/native/engine/Dodge.lua').read_text(encoding='utf8')
    suites=['offline','render_lifecycle','conversation','daily','speech','voice','control','actions_clock','merge','native_merge','coordinator','maxwell','personality','thought_cooking','batch_cooking','navigation','fishing_queen','battlemusic','secondary_travel','dodge_cane','combat103','native_food','grinding','chat_ui','knowledge','combat112','combat114','combat115','combat116','combat117','combat118','combat119','combat120','combat121','combat122','combat123','combat124','combat125','combat126','combat128','queen_debug_removed','queen_flute_recovery','queen_phase1','queen_phase3','server_combat','boss140','boss141','boss142','network_movement','network_combat','combat144','native_embedded','walka_original','swing146','combat147']
    runtime.globals().read_astra_source=lambda path:(steamapps/'workshop/content/322330/3816458126/scripts'/path).read_text(encoding='utf8')
    suites.extend(['arena_protocol','arena_lifecycle','arena_planning','arena_healing','arena_runtime','arena_opening_fire','arena159','arena160','arena161','arena162','arena163','arena164','arena165'])
    suites.append('arena_completion')
    suites.append('arena_clockwork')
    suites.append('arena_whip')
    suites.append('arena_pirates')
    suites.append('arena_supply')
    suites.append('arena_disarm')
    suites.append('arena_walrus')
    suites.append('antlion_routes')
    suites.append('arena_pirate_prep')
    suites.append('arena_round036')
    suites.append('arena_snail_rook038')
    suites.append('arena_moose042')
    suites.append('arena_shark_guardian043')
    suites.append('arena_salamanders044')
    suites.append('arena_worms045')
    suites.append('arena_rowing046')
    suites.append('arena_deploy048')
    suites.append('arena_pickup051')
    suites.append('arena_swamp051')
    suites.append('arena_stage051')
    suites.append('arena_slurper061')
    suites.append('arena_stage11062')
    suites.append('arena_late063')
    suites.append('arena_stage11064')
    suites.append('arena_late065')
    suites.append('arena_exceptions065')
    suites.append('arena_moose067')
    suites.append('arena_return068')
    suites.append('arena_rabbit069')
    suites.append('arena_supply070')
    suites.append('arena_health071')
    suites.append('arena_objectives072')
    suites.append('arena_rabbit073')
    suites.append('arena_guardian074')
    suites.append('arena_late_move078')
    suites.append('arena_hats078')
    suites.append('arena_routes079')
    suites.append('arena_traps080')
    suites.append('arena_spiders081')
    suites.append('arena_guardian081')
    suites.append('arena_bone083')
    suites.append('arena_bat_snails084')
    suites.append('arena_late_roster085')
    suites.append('arena_shadow13_086')
    suites.append('arena_shark_guardian_sword087')
    suites.append('arena_control088')
    suites.append('arena_routes089')
    suites.append('arena_slurper090')
    suites.append('arena_residual091')
    suites.append('arena_reward_route093')
    suites.append('arena_pig_rabbit095')
    suites.append('arena_staff_finish098')
    suites.append('arena_slurper_routes099')
    suites.append('arena_frogloot100')
    suites.append('arena_prepare101')
    suites.append('rpc_throttle102')
    suites.append('arena_partner_isolation')
    suites.extend(['adventureworld', 'newbosses', 'newboss_debug', 'weaver', 'weaver_cycle', 'weaver_phase1', 'weaver_timeline', 'weaver_projectile', 'weaver_route_perf', 'weaver_owner', 'weaver_staff', 'weaver_stabilize', 'weaver_pillars', 'weaver_corner_exit', 'weaver_lap', 'weaver_output', 'weaver_rebait', 'weaver_food_edge', 'weaver_hurt_replay', 'weaver_retreat', 'weaver_perf_hurts', 'weaver_audit', 'weaver_architecture'])
    for name in (sys.argv[2].split(',') if len(sys.argv)>2 else suites):
        runtime.execute((ROOT/'tests'/f'{name}.lua').read_text(encoding='utf8'))
print('PASS: Lua 5.1 regression complete; gameplay remains untested')
