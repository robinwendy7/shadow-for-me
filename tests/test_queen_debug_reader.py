from pathlib import Path
import sys,unittest,json
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from read_queen_debug import parse,latest_fight,summarize,report_text
M='[ShadowSelf][QueenDebug] '
class ReaderTests(unittest.TestCase):
 def test_fields_and_private_lines(self):
  rows,version=parse('Loading mod: Cry for me (影子) Version:0.12.7\nPRIVATE_ACCOUNT_LINE\n'+M+'event="snapshot" fight="one" version="0.12.7" t=1.250 reason="蜂后 · 直线跑" busy=false phase=3')
  self.assertEqual(version,'0.12.7');self.assertEqual(len(rows),1)
  self.assertEqual(rows[0][0]['reason'],'蜂后 · 直线跑');self.assertEqual(rows[0][0]['t'],1.25)
  self.assertNotIn('PRIVATE',rows[0][1])
 def test_latest_reused_session_after_boot(self):
  text=M+'event="boot"\n'+M+'event="fight_start" fight="one" t=0\n'+M+'event="boot"\n'+M+'event="fight_start" fight="one" t=10'
  selected=latest_fight(parse(text)[0]);self.assertEqual(len(selected),1);self.assertEqual(selected[0][0]['t'],10)
 def test_empty_does_not_claim_live_validation(self):
  report=summarize([], '0.12.6');self.assertIn('尚未读到',report_text(report));self.assertEqual(report['events'],{})
 def test_blocked_attack_not_dispatched_attack(self):
  rows,_=parse(M+'event="attack_block" fight="one" phase=3 target="beeguard#8"\n'+M+'event="attack_dispatch" fight="one" phase=3 target="beeguard#8"')
  report=summarize(rows,None);self.assertEqual(len(report['warnings']),1);self.assertIn('发出守卫攻击',report['warnings'][0])
 def test_identical_prefab_aba(self):
  rows,_=parse('\n'.join(M+f'event="equip_request" fight="one" t={i} item="{item}"' for i,item in enumerate(['firestaff#1','firestaff#2','firestaff#1'])))
  self.assertTrue(any('来回换实体' in warning for warning in summarize(rows,None)['warnings']))
 def test_normal_cane_restore_no_false_warning(self):
  rows,_=parse('\n'.join(M+f'event="equip_request" fight="one" t={i} item="{item}"' for i,item in enumerate(['icestaff#1','cane#2','icestaff#1'])))
  self.assertEqual(summarize(rows,None)['warnings'],[])
 def test_actual_lua_fixture(self):
  path=Path(__file__).resolve().parents[1]/'reviews'/'queen-debug-offline-fixture.log'
  rows,version=parse(path.read_text(encoding='utf8'));selected=latest_fight(rows)
  self.assertEqual(version,'0.12.18');self.assertTrue(selected)
  report=summarize(selected,version)
  self.assertGreater(report['events'].get('snapshot',0),0)
  self.assertTrue(any('位置未推进' in warning for warning in report['warnings']))
  self.assertNotIn('logger_error',report['events'])
 def test_enabled_integration_fixture(self):
  path=Path(__file__).resolve().parents[1]/'reviews'/'queen-debug-offline-integration.log'
  rows,_=parse(path.read_text(encoding='utf8'));report=summarize(latest_fight(rows),None)
  self.assertGreater(report['events'].get('dash_start',0),0)
  self.assertGreater(report['events'].get('dash_end',0),0)
  self.assertGreater(report['events'].get('attack_block',0),0)
  self.assertNotIn('logger_error',report['events'])
 def test_cancel_and_exact_hit_fields(self):
  rows,_=parse(M+'event="flute_cancel" fight="one" t=0.7 reason="attacked:beeguard#1" performed=false\n'+M+'event="attacked" fight="one" t=0.7 attacker="beeguard#1" attacker_frame=13 queen_frame=14 flute_pending=true flute_elapsed=0.7')
  report=summarize(rows,None)
  self.assertEqual(report['timeline'][0]['event'],'flute_cancel')
  self.assertEqual(report['hits'][0]['attacker_frame'],13)
  self.assertIn('flute_elapsed=0.7',report_text(report))
if __name__=='__main__':unittest.main()
