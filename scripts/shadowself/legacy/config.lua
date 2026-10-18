local AIPLAYER=require("shadowself/legacy/registry")
-- 配置集中读取；断线接管选项已由联网闲置接管替代。
AIPLAYER.Config = Class(function(self, read)
    self.humanization_level = read("humanization_level") or 3
    self.reaction_delay_base = (read("reaction_delay_base") or 400) / 1000
    self.mistake_frequency = read("mistake_frequency") or 30
    self.task_priority = read("task_priority") or "survival"
    self.max_wander_radius = read("max_wander_radius") or 15
    self.enable_emotes = read("enable_emotes") ~= false
    self.combat_mode = read("combat_mode") or "character"
    self.personality = read("personality") or "character"
    self.idle_activate = read("idle_activate") or 0
    self.debug = read("debug") == true
    self.auto_combat = read("auto_combat") ~= false
    self.combat_margin = (read("combat_margin") or 250)/1000
    self.combat_style = read("combat_style") or "pressure"
    self.combat_abilities = read("combat_abilities") ~= false
    self.scan_interval = .4
    self.tick_interval = .05
    self.scan_radius = 22
    self.action_timeout = 14
    self.max_failures = 3
end)

return true
