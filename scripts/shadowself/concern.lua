-- 只累计实际掉血/受击动画边沿，不因血量百分比低擅自接管或逃跑。
local Concern=Class(function(self,r) self.r=r;self.hits={};self.next=0;self.offer=0 end)
function Concern:Hit()
    local r=self.r;local now=GetTime()
    if r.control.phase or r.control.pending and r.control.pending.plan and r.control.pending.plan.defensive then self.hits={};return end
    if r.dead or now-(self.last or -100)<.65 then return end
    self.last=now
    local hits={};for _,t in ipairs(self.hits) do if now-t<10 then hits[#hits+1]=t end end
    hits[#hits+1]=now;self.hits=hits
    if #hits<3 or now<self.next then return end
    self.next=now+5
    if now>=self.offer and not r.control.phase and not r.control.pending then
        if r.control:OfferCombat() then self.offer=now+30;return end
    end
    local code=r.dialogue:GetPersonality().code
    local lines={
        original={"又挨了一下……别这么对自己。","看见你一直受伤，我没法当没看见。"},
        INTJ={"受击还在持续。先看它出招的间隔。","再硬接下去，余地会越来越少。"},
        INTP={"这个受击频率不对，得换一种距离。","它出手有间隔。别把自己留在那里面。"},
        ENTJ={"别再拿血换机会了，先把节奏拿回来。","又中了。换站位，别硬扛。"},
        ENTP={"它可没打算跟你讲公平……别再硬接了。","嘴上想损你一句，看见伤口又说不出来了。"},
        INFJ={"你又受伤了。我看着会难受。","先别逼自己，把这一波避开。"},
        INFP={"又碰到伤处了……别再硬撑。","每一下我都看见了，心里很疼。"},
        ENFJ={"你不用靠硬扛证明什么，先避开。","又被打中了。把自己照顾好一点。"},
        ENFP={"又挨了！先换个位置，别留在那里。","看到你这样受伤，我真没法装镇定。"},
        ISTJ={"连续受击。先退半步看清动作。","伤在叠加，注意出招间隔。"},
        ISFJ={"伤口又添了一处……先顾好自己。","这样一直挨打，我看着心疼。"},
        ESTJ={"别站着换血，调整距离。","又受伤了。先把这次攻击躲开。"},
        ESFJ={"又伤到了，别总这么硬撑。","你疼不疼？我看着都揪心。"},
        ISTP={"又中了。换位置。","别硬吃这一下。"},
        ISFP={"又添了一道伤……我看着难受。","别让它再碰到你了。"},
        ESTP={"这一下没必要吃，换个角度。","别跟它站着换血，看着疼。"},
        ESFP={"又打中了！你先避一下。","别再挨了，我看得心都揪起来了。"},
    }
    local pool=lines[code] or lines.original
    self.index=(self.index or 0)%#pool+1;r.control:Say(pool[self.index])
end
return Concern
