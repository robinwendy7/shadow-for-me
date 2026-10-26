# 合伙人角斗场分支为主体：0.13.103-merge

日期：2026-10-26。用户要求角斗场战斗、拾取以仓库合伙人的版本为准，删除本地冲突重复实现，保留独立 Boss 战合并。

## 更正基线

此前0.13.81/82只取了 main b16aba6，漏查真正持续开发角斗场的分支，本次纠正。

仓库：git@github.com:robinwendy7/shadow-for-me.git
采用分支：dev/arena-completion-01317
采用提交：9e4ca625f96768837d6da62c27b7bc3c878b5c5f
合伙人原版：0.13.102-dev
合并版本：0.13.103-merge

本次从该分支独立副本重建，逐点加入场外 Boss 接口，未整份复制本地旧公共战斗代码。

## 角斗场归属和清理

- Arena的关卡状态、拾取/丢弃/装备确认、恢复、开场、关卡策略、怪物名单、15关数据，全部采用合伙人版本。
- combat/coordinator/bosses/mechanisms/secondary/legacy/combat_equipment采用合伙人主体：保留其排箫/猫鞭/主教/海象/吸食者/鸟/骨甲/后期策略优先级、拾取实际确认、手持与动作窗口、原生底层RPC限流等；不拿我们旧版覆盖这些改动。
- Coordinator在plan.arena时不加载、不创建weaver/newbosses。场内不会发生独立Boss的扫描、移动、目标过滤、换装或Stop回收；本地Boss钩子只在场外实例存在时有效。
- 本地0.13.82的整套mode/route识别替换和初始关卡改动移除；arena.lua完整还原合伙人版本。arena_adapter.lua只将原标题判断扩展兼容“场地测试”，其RemainingObjectives等逻辑原样保留。
- 删除已被新分支取代的本地tests/arena_entry.lua；原文件备份。用arena_partner_isolation验证场内/场外真实Coordinator构造归属、停止归属及两种标题。
- 场外保留四个新Boss、织影者、冒险自动寻猎既有独立目录及必要调用入口，不新增并行战斗执行器。
- 原有独立战斗日志子模组与历史交接记录保留，不接入或抢占角斗场行为。

## 验证及边界

- 合伙人原始分支123组离线回归通过，合并版147组通过，未改写合伙人原有测试。
- arena_lifecycle仍在原分支直接运行时因本机ASTRA15关数据对照不同失败，未放宽断言、未计为通过。
- 74个角斗场/原生战斗Lua文件逐字节等同分支；适配器仅一处标题条件不同。全部原有分支测试文件保持原文。
- 新测试证明plan.arena不会加载或创建独立Boss控制器，也不会在停止时发出其移动重置；普通战斗创建并各释放一次。
- 这是离线验证，没有实际关卡通关日志；不能将回归通过称为已经实战通关。

证据：当前任务目录partner-arena-base-regression.log、partner-arena-merged-103-regression.log、partner-base-regression.log（保留原始表对照失败）。部署前分别备份源项目和实际客户端被替换文件并记录SHA256。

后续以本文件指定分支为角斗场基线，不能再把main或0.13.82的旧合并副本称为合伙人角斗场实现。本提交在合伙人的9e4ca62提交之后追加，保留其历史。
