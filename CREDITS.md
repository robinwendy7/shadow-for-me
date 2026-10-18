# 实现参考与客户端依赖

本项目的工作动作桥接、目标名称表和命令组织参考用户自己的：

- `D:/Steam/steamapps/common/Don't Starve Together/mods/zombie-maxwell-client/scripts/ActionQueue.lua`
- `D:/Steam/steamapps/common/Don't Starve Together/mods/zombie-maxwell-client/scripts/AliasTable.lua`
- `D:/Steam/steamapps/common/Don't Starve Together/mods/zombie-maxwell-client/scripts/CommandParser.lua`

`control/aliases.lua` 由用户自有名称表适配；`control/actions.lua` 按其已核对原版调用流程实现。未接入该项目的外部聊天 API、代理、世界切换或自动重连功能。

战斗依赖以下已启用的客户端 Workshop 模组，未复制或修改它们的源文件：

- **3014188454 / cheating**：本机版本 3.31；原作者署名 **萌萌的新，白狼vvk**。实际调用 `HitAndRun:StartHitAndRun()`、`StopHitAndRun()`、`IsAttackPre()`、`DoDodge()`，使用其攻击时机、怪物动作表和走位实现。
- **3750329397 / 基础运行库**：本机版本 1.28；原作者署名 **萌萌的新**。由 3014 依赖的 `MOD_util`、`POS_util`、`ENT_util` 等实现提供运行支持。

原版作祟、玩家复活及阿比盖尔托抱动画与格式来自用户本机 DST 游戏资源和 Klei Mod Tools。灵魂托抱轨道复用原版 `ghost_abigail_resurrect` 的符号变换，改为玩家自己的灵魂 build 与暗影颜色，并调整标准玩家不支持的眼睛帧索引。

以上记录是实现来源与当前本机核对信息；不代表第三方模组为本项目背书。未上传或发布这些资源。


0.5 还实际合并了用户自有 `E:/My mods/AI Player/scripts/` 中的 config、world_model、humanizer、perception、action_library、combat_equipment、character_profiles、decision_brain、autopilot_main；使用独立本地注册表和存档键、外层接管调度，替换旧战斗控制器并禁用旧全局输入/UI挂钩。未修改原项目。

zom 的 CommandParser、ActionQueue、Config、StateReporter、WorldInfo、AdventureTools 已复制并改为 shadowself/zom 命名空间；原服务端聊天播报改成本地回调，队列取消加入代际校验。没有迁入 ChatAI 的外部API、自动重连、换角色、服务器自定义RPC迁移、麦斯威尔专属控制。原作者资料沿用用户提供的自有项目；第三方3014与37503署名和运行依赖保持上文所列。


0.6 进一步合并用户旧 AI Player 的 `combat_tactics.lua`，实际复用群怪 Pack、转火 Choose 与联合窗口检查；`combat_equipment.lua` 复用于手杖/武器切换与服务器装备同步。新适配器仅协调3014线程，没有迁回旧AI的出刀、逐帧走位或攻击帧库。音效替换为原版shadowwaxwell消散事件并从客户端音频焦点播放。


0.6.2 的秘典禁锢流程适配自用户 zom/modmain.lua 的 HasPillars、TrackControl、PredictedPoint、CastPillars，并核对当前游戏 waxwelljournal.lua、spellbook.lua、playercontroller.lua 和 networkclientrpc.lua。未调用服务端组件、未注册Mod RPC。外观过滤与基础图层参照当前 shadowwaxwell.lua、player_common_extensions.lua。


0.7 的16型人格只作为用户选择的虚构对话风格。类型中文名称沿用用户提供的图示；448句新增回应为本项目编写，没有采用图中的娱乐比例作为心理测量或行为规则。


0.8 内置料理参考 Workshop **2033458869 / Auto Cooking 2.2.5**，作者 **Tony**，MIT License。原授权全文附于 `LICENSE-Auto-Cooking.txt`。参考其原生开容器、转移食材和调用烹饪按钮流程，重新实现可取消的状态机，不启用或加载其 `ac_thread`。料理条件和调味粉配方读取用户本机游戏的 cooking、preparedfoods_warly、spicedfoods 和 recipes 数据。新增情境评估、授权关心与人格接管文案为本项目实现。


## 0.11.0 内置战斗来源

- `scripts/shadowself/native/engine/`：来自用户指定的3014188454（cheating，作者萌萌的新）本地副本；保留原走A、DoDodge及怪物/人物招式数据，修改初始化入口、线程名与事件标记，停用热键注册和服务器远程代码。
- `scripts/shadowself/native/utils/`：来自3750329397（基础运行库，作者萌萌的新）本地副本；支持函数使用私有环境，移除来源Mod的全局初始化与账号惩罚/安装逻辑。保留文件内原注释。未修改两个来源目录。
- 特殊招式时序核对来源：当前安装游戏scripts.zip内SGbeequeen、beequeen、honey_trail、beeguard、SGrook、SGmoonspore、mushtree_moonspore、SGsharkboi、SGantlion_angry、sand_spike、SGwagboss_robot、wagboss_missile、armor_snurtleshell、SGklaus、armor_skeleton。未把原版服务器状态机载入运行。


0.11.2专项核对：当前游戏networkclientrpc.lua、components/playercontroller.lua、SGwalrus/walrusbrain/walrus、SGpenguin/penguin、SGlightninggoat/lightninggoat、inventory:IsInsulated、raincoat/hats/armor_wagpunk、preparedfoods_warly、foodbuffs。只读取原版机制，未修改或载入服务器状态机。
