# 蜂后战调试（0.12.7）

Mod设置新增“蜂后战调试日志”，默认开启。只在本地原版 client_log 中记录，不发聊天、不联网、不增加战斗动作。

## 复现

1. 重启游戏，加载0.12.7。日志应出现 `[ShadowSelf][QueenDebug] ... event="boot" ... version="0.12.7" enabled=true`。
2. 接管打一轮蜂后，在卡住、乱切杖、带蜂/返身不对等问题发生后，再等数秒并停止接管。停止会记录fight_end。
3. 告诉Codex“已经复现，读蜂后日志”，可直接读取这台电脑的 `D:\Documents\Klei\DoNotStarveTogether\client_log.txt`，无需上传。

## 记录内容

- `decision`：阶段、策略子状态、当前目标、是否暂停攻击及中文原因。
- `guards`：每只已感知守卫的实体标识、普通/冲刺/睡眠/冻结、build、动画、距玩家距离。
- `snapshot`：每两秒的角色/蜂后位置、蜂后动画帧与距离、扫描里有无蜂后、守卫统计、目标、忙碌状态、实际手持、强制武器、在途换装、走A线程、移动落点与进度。
- `dash_start / dash_end / dash_route / queen_solo`：冲刺拉扯与返身触发依据、固定方向、直线/避障/受阻及距离边界。
- `guard_dodge_start / guard_dodge_end`：冻蜂期间躲蜂后攻击的开始/结束帧。
- `equip_request / equip_ack / equip_timeout / equip_cancel_role`：具体物品prefab#GUID、角色、实际手持和确认耗时，便于定位双法杖交替或两套控制争抢。
- `flute_request / flute_confirmed / flute_timeout / flute_rejected`：排箫请求、全员睡眠确认或失败。
- `attack_dispatch` 只是原生攻击入口调用，不代表服务器已执行/命中；`attack_performed` 是客户端可观察到的原版执行事件（不同客户端/主机可能可见性不同）。`attack_block` 是被禁止的旧目标补刀；正常的选敌排除只累计到select_veto，不逐只刷屏。
- `hurt` 记录观察到的血量下降；能接收到原版attacked事件时，另记攻击者与伤害。

状态按变化记录，采样间隔0.2秒、快照2秒；每场战斗普通事件每秒最多24条，超过计入dropped，快照和结束记录仍保留。stalled只是“有远处移动目标、位置未推进且不忙”的线索，不自动改动AI，不能单独证明死锁。调试本身不选择目标、不换装备、不移动人物。

## 提取与分析

`tools/read_queen_debug.py` 自动从Windows实际文档目录找日志，默认提取最近一场蜂后战，输出到 `reviews/queen-debug-latest/`：

- queen-debug.log：仅蜂后诊断行。
- queen-debug.json：事件统计、决策时间线、换装、快照与检查项。
- queen-debug.md：中文可读报告。

运行：`python -X utf8 tools/read_queen_debug.py`。可用 `--log 路径` 指定日志、`--out 路径` 指定报告位置，`--all` 提取全部诊断场次。自动检查三阶段守卫攻击请求、同类物品A→B→A、换装/催眠超时、移动无进度和诊断器错误。未命中检查项不等于实战正确，仍应看具体时间线。

## 现有证据与验证

安装前实际客户端日志最后加载0.12.6，只有旧启动提示和普通事件，没有QueenDebug决策轨迹；因此不能用它倒推出此前战斗问题的具体原因。启动提示原来固定写0.11.9，现已与诊断版本统一为0.12.7。

完整Lua 5.1回归、日志开启时真实原生走位/监督/扫描联动回归，以及8项Python解析测试通过。`queen-debug-offline-*.log` 明确为离线测试样本，不是实机战斗记录。需要按上面的步骤生成新版实机日志后，才能对具体战斗失败作出日志结论。
