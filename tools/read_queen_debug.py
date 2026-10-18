"""只提取 ShadowSelf 蜂后诊断；不复制账户/聊天/网络信息。"""
from pathlib import Path
from collections import Counter
import argparse,json,re,os
MARKER='[ShadowSelf][QueenDebug]'
FIELDS=re.compile(r'(\w+)=("(?:\\.|[^"\\])*"|[^\s]+)')
def default_log():
    documents=Path.home()/'Documents'
    if os.name=='nt':
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER,r'Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders') as key:
            documents=Path(os.path.expandvars(winreg.QueryValueEx(key,'Personal')[0]))
    return documents/'Klei'/'DoNotStarveTogether'/'client_log.txt'
def parse(text):
    rows=[];boot=0;loaded=None
    for number,line in enumerate(text.splitlines(),1):
        match=re.search(r'Loading mod: Cry for me .*Version:([^\s]+)',line)
        if match:loaded=match.group(1)
        if MARKER not in line:continue
        data={}
        for key,value in FIELDS.findall(line.split(MARKER,1)[1]):
            try:data[key]=json.loads(value)
            except (ValueError,TypeError):data[key]=value
        if data.get('event')=='boot':boot+=1
        data.update(_boot=boot,_line=number)
        rows.append((data,line))
    return rows,loaded

def latest_fight(rows):
    fights=[(d['_boot'],d['fight']) for d,_ in rows if d.get('fight')]
    if not fights:return []
    selected=fights[-1]
    return [(d,line) for d,line in rows if (d['_boot'],d.get('fight'))==selected]

def summarize(rows,loaded):
    counts=Counter(d.get('event','unknown') for d,_ in rows)
    warnings=[];timeline=[];requests=[];snapshots=[];hits=[]
    for d,_ in rows:
        event=d.get('event')
        if event in ('decision','dash_start','dash_end','dash_wait','dash_recenter','queen_solo','flute_request','flute_confirmed','flute_timeout','flute_cancel','flute_performed','flute_wait','guard_frozen','guard_ice_shot','guard_recycle','guard_replaced','queen_route_blocked','queen_route_plan','fight_end'):
            timeline.append(d)
        if event=='equip_request':requests.append(d)
        if event=='snapshot':snapshots.append(d)
        if event=='attacked':hits.append(d)
        if event in ('attack_dispatch','attack_performed') and d.get('phase',0)>=3 and str(d.get('target','')).startswith('beeguard#'):
            warnings.append(f"三阶段发出守卫攻击请求/执行：event={event} t={d.get('t')} target={d.get('target')}")
        if event=='logger_error':warnings.append('诊断器错误：'+str(d.get('message')))
    for i in range(2,len(requests)):
        a,b,c=requests[i-2:i+1];items=[str(x.get('item','')) for x in (a,b,c)]
        if items[0]==items[2]!=items[1] and len({x.split('#')[0] for x in items})==1 and c.get('t',0)-a.get('t',0)<5:
            warnings.append(f"相同prefab来回换实体：{items}，t={c.get('t')}")
    stalls=[d for d in snapshots if d.get('stalled')]
    if stalls:warnings.append(f"检测到{len(stalls)}次无忙碌状态下有移动目标但位置未推进的采样，需结合路线/受击记录检查。")
    if counts['equip_timeout']:warnings.append(f"换装确认超时{counts['equip_timeout']}次。")
    if counts['flute_timeout']:warnings.append(f"全员催眠确认超时{counts['flute_timeout']}次。")
    return dict(loaded_version=loaded,trace_version=rows[-1][0].get('version') if rows else None,
                fight=rows[-1][0].get('fight') if rows else None,events=dict(counts),warnings=warnings,
                timeline=timeline,equipment=requests,snapshots=snapshots,hits=hits)

def report_text(report):
    lines=['# 蜂后战调试报告','',f"客户端最近加载版本：{report['loaded_version'] or '未读到'}",
           f"诊断版本：{report['trace_version'] or '未读到'}；战斗：{report['fight'] or '尚无记录'}",'']
    if not report['events']:
        lines+=['尚未读到蜂后诊断战斗记录。请加载带QueenDebug的新版本，在调试日志开启时复现一轮蜂后战。','']
    else:
        lines+=['事件计数：'+json.dumps(report['events'],ensure_ascii=False),'', '## 检查结果','']
        lines += ['- '+w for w in report['warnings']] or ['未命中自动检查项；不代表实战行为正确，仍需查看下面的决策/路线。']
        lines+=['','## 决策时间线','']
        for d in report['timeline'][-100:]:
            details=' '.join(f'{key}={d[key]}' for key in ('phase','stage','mode','target','reason','direction','distance','elapsed','performed','hit_eta','window','guard','freezes','shots','estimated_resistance','coverage_missing','candidates','selected','remaining','nearest','home','goal_home') if key in d)
            lines.append(f"- {d.get('t','?')}s {d.get('event')} {details}")
        lines+=['','## 最近状态采样','']
        for d in report['snapshots'][-20:]:
            details=' '.join(f'{k}={d[k]}' for k in ('phase','stage','mode','queen_anim','queen_frame','distance','guards','boosted','target','busy','held','pending','goal','moved','stalled','dropped') if k in d)
            lines.append(f"- {d.get('t','?')}s {details}")
        lines+=['','## 逐次受击（事件瞬间）','']
        for d in report.get('hits',[]):
            details=' '.join(f'{k}={d[k]}' for k in ('attacker','damage','phase','stage','player_anim','queen_anim','queen_frame','attacker_anim','attacker_frame','distance','attacker_distance','flute_pending','flute_performed','flute_elapsed') if k in d)
            lines.append(f"- {d.get('t','?')}s {details}")
        lines+=['','说明：attack_dispatch是攻击入口调用，attack_performed是可观察到的原版执行事件；仅前者不能证明服务器命中。select_veto只是守卫被排除选敌的次数，属于正常策略。','']
    return '\n'.join(lines)

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--log',type=Path,default=default_log())
    parser.add_argument('--out',type=Path,default=Path(__file__).resolve().parents[1]/'reviews'/'queen-debug-latest')
    parser.add_argument('--all',action='store_true',help='提取全部诊断战斗；默认只提取最近一场')
    args=parser.parse_args();rows,loaded=parse(args.log.read_text(encoding='utf8',errors='replace'))
    selected=rows if args.all else latest_fight(rows);result=summarize(selected,loaded)
    boots=[d for d,_ in rows if d.get('event')=='boot']
    if boots:
        result['debug_enabled']=boots[-1].get('enabled')
        if not selected:result['trace_version']=boots[-1].get('version')
    args.out.mkdir(parents=True,exist_ok=True)
    (args.out/'queen-debug.log').write_text('\n'.join(line for _,line in selected)+'\n',encoding='utf8')
    (args.out/'queen-debug.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
    (args.out/'queen-debug.md').write_text(report_text(result),encoding='utf8')
    print(report_text(result));print('报告位置：',args.out)
if __name__=='__main__':main()
