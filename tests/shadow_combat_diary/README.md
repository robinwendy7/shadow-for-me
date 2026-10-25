# 战斗日志 Mod 离线验证

依赖 Python、Lupa（含 `lupa.lua51`）以及本机合法安装的 DST `data/databundles/scripts.zip`。

在仓库根目录运行：

```powershell
$env:DST_SCRIPTS_ZIP = "E:/STEAM/steamapps/common/Don't Starve Together/data/databundles/scripts.zip"
python tests/shadow_combat_diary/verify.py
```

如 Lupa 安装在自定义目录，设置 `SCD_LUA_DEPS`。测试产物写入 `outputs/shadow_combat_diary`，不要上传真实玩家日志。覆盖事件顺序、伤害归因边界、复活与重复死亡、HUD 生命周期、分块重组及完整性校验。仅为静态检查和离线模拟，不代表服务器实测。
