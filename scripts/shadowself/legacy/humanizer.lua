local AIPLAYER=require("shadowself/legacy/registry")
-- 拟人化只影响节奏与安全移动；急救不会故意选错食物、目标或逃跑方向。
local Humanizer = Class(function(self, config, profile)
    self.config = config
    self.profile = profile
    self.operations = 0
    self.burst_count = 0
    self.next_emote = GetTime() + 90 + math.random()*90
    local personalities={careful={tempo=1.2,burst=3},diligent={tempo=.8,burst=6},casual={tempo=1.3,burst=2}}
    self.style = personalities[config.personality] or (profile and profile.data) or {tempo=1,burst=4}
end)

-- Box-Muller 产生高斯分布，再限制在实际人类反应时间范围内。
function Humanizer:Gaussian(mean, sigma, low, high)
    local u = math.max(.000001, math.random())
    local value = mean + sigma * math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * math.random())
    return math.max(low, math.min(high, value))
end

-- 紧急动作和普通采集使用不同的延迟范围。
function Humanizer:Delay(emergency)
    local level = self.config.humanization_level
    if emergency then return self:Gaussian(self.config.reaction_delay_base, .12, .2, .8) end
    return self:Gaussian((.25 + level * .12)*(self.style.tempo or 1), .18, .3, 1.2)
end

-- 两个日常选项接近时允许犹豫；紧急节点始终保留优先级。
function Humanizer:Choose(candidates)
    table.sort(candidates, function(a, b) return a.priority > b.priority end)
    if #candidates > 1 and candidates[1].priority < 80 and candidates[1].priority - candidates[2].priority < 10
        and math.random() < .08 * self.config.humanization_level then return candidates[2] end
    return candidates[1]
end

-- 偶尔多停顿一次，避免通过故意挨打模拟失误。
function Humanizer:AfterAction(emergency)
    self.operations = self.operations + 1
    self.burst_count = self.burst_count + 1
    if emergency then return .15 end
    local n = self.config.mistake_frequency
    if n > 0 and math.random(n) == 1 then return self:Gaussian(1.8, .5, 1, 3) end
    if self.burst_count >= (self.style.burst or 4) then
        self.burst_count=0
        return self:Gaussian(.7*self.config.humanization_level/3, .3, .3, 2)
    end
    return .2
end

-- 仅对巡逻点产生偏移，交互目标保持准确，并由执行器验证地形。
function Humanizer:Offset(point)
    local angle = math.random() * 2 * math.pi
    local distance = .5 + math.random() * 1.5
    return Vector3(point.x + math.cos(angle)*distance, 0, point.z + math.sin(angle)*distance)
end

AIPLAYER.Humanizer = Humanizer

return true
