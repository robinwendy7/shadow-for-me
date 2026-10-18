# 0.11.9 晶鹿原始走位、亮茄中段与蘑菇临爆窗口（2026-10-18）

- 晶鹿眼睛被引燃：明确识别 SGdeerclops 的 struggle_pre、struggle_loop、struggle_pst。从 struggle_pre 起即释放强制火杖/火把，结束重复点燃，交给普通追击、换战斗武器及攻击流程；不必等待 stagger。引燃挣扎与眼冰已经被打碎分别记录。
- 无冰形态：撤掉此前自写的同半径绕圈/站后等待，直接返回内置原版普通巨鹿 targetanimtable.deerclops 的同一个 atk 表项。使用其第14～35帧、point=player、update=false、-80度、dist=6；位置锁定、移动及补刀执行均交给原3014 DoDodge。第13帧以前和第36帧以后不强行延长该表项。
- 亮茄：虚弱只认 tired_pre/loop/hit/shock 等实际疲倦动画，排除 tired_wakeup 和 tired_pst；不再仅以缺少 retaliates 标签判断虚弱。恢复后立即清掉旧本体锁定，允许中段攻击。中段增加实际 lunarthrall_plant_vine_big build 识别，并纳入感知，避免只依赖后加的 weakvine/segment 标签；真正虚弱时仍优先本体，保留实际藤鞭威胁。
- 蛤蟆：彻底取消地面蘑菇 land/grow1/grow2 的爆炸危险区，它们存在时正常攻击蛤蟆。只在 explode_pre 按源码最早可能爆炸时刻（动画长度一半）减去逃离时间、延迟和少量余量决定何时避让；爆炸动作结束后不保留危险区，交回攻击。mushroombomb 和 mushroombomb_dark 均处理，空中投射物、头顶毒云计时和地面孢子云仍各自分开。

核对依据：内置3014 Dodge.lua 的普通 deerclops 表项，本机 SGdeerclops、SGlunarthrall_plant、lunarthrall_plant 和 mushroombomb.lua。

验证：Lua 5.1 全文件编译与完整离线回归通过。新增 combat121 从实际内置源码抽取普通巨鹿表项，检查对象直接复用、14～35帧边界；验证 struggle_pre 即释放点燃武器、活动本体恢复中段选择、实际粗藤蔓build，以及真实监督流程在蘑菇 land/grow1/grow2、早期爆炸前摇维持攻击，临爆暂停闪避，爆炸后重新启动攻击。网络/实体仍为离线模拟，本版未进行游戏实战。
