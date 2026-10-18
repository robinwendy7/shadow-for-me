-- 接管功能语言按人格分别编写，参数保留任务名与真实结果。
local T={
    original={permission="让我接管，去{task}？",transition="我过去了。",enter="现在开始{task}。",done="{detail}",stop="停了，操作还你。",care="别再硬接了。让我接手战斗？",cook_ask="想吃什么？"},
    INTJ={permission="这件事需要接管：{task}。你同意吗？",transition="正在完成覆盖。",enter="覆盖完成，执行{task}。",done="{detail}。下一项你定。",stop="已停止，控制权归你。",care="连续受击了。换我接手，调整打法？",cook_ask="先定菜名。想做哪道？"},
    INTP={permission="我可以试着处理{task}。允许接管吗？",transition="先完成交接。",enter="现在验证一下这套办法：{task}。",done="{detail}。结果已经确认。",stop="停了，不继续试。",care="这个受击节奏不对。让我接过来试一下？",cook_ask="你想吃哪道？我先核对配方。"},
    ENTJ={permission="目标是{task}。把操作交给我吗？",transition="开始交接。",enter="接管完成，开始{task}。",done="{detail}。这项完成。",stop="停止，操作交还。",care="别继续硬扛。让我接管这场战斗。你同意吗？",cook_ask="说个菜名，我们按配方准备。"},
    ENTP={permission="{task}，要不要换我来一局？",transition="先借个位置。",enter="好了，开始{task}，看看这招管不管用。",done="{detail}。这回不是嘴上说说。",stop="停，方向盘还你。",care="它都快把你当练习目标了。换我来，好吗？",cook_ask="菜单别只写“饭”。想吃哪道？"},
    INFJ={permission="你愿意让我接手{task}吗？",transition="等我完成覆盖。",enter="交接好了，我来{task}。",done="{detail}。这件事可以放下了。",stop="已经停下，决定交回你。",care="看到你一直挨打，我有点受不了。让我来，好吗？",cook_ask="你现在最想吃什么？"},
    INFP={permission="这次{task}，可以让我替你做吗？",transition="我靠近你了。",enter="覆盖好了，接下来我来{task}。",done="{detail}。总算有一件事落稳了。",stop="好，交还给你。",care="别再让它碰你了。让我替你挡一回，好吗？",cook_ask="想吃哪一种？给我一个名字就好。"},
    ENFJ={permission="这件{task}交给我，你同意吗？",transition="先把交接完成。",enter="准备好了，我来{task}。",done="{detail}。你可以安排下一件了。",stop="停下了，你来决定。",care="你已经被打中好几次了。把操作交给我，我们换个节奏？",cook_ask="想做什么吃的？先选一道吧。"},
    ENFP={permission="让我来{task}，怎么样？",transition="等我一下，正在覆盖！",enter="好了，这回由我来{task}！",done="{detail}！终于拿到结果了。",stop="好，停在这里！你接着来。",care="别再挨了，我看着都疼。换我接手好吗？",cook_ask="选一道想吃的！你报菜名。"},
    ISTJ={permission="申请接管，处理{task}。是否同意？",transition="开始交接，先不执行。",enter="覆盖完成，按顺序{task}。",done="{detail}，已检查结果。",stop="已停，操作交回。",care="短时间连续受伤。让我接管战斗，可以吗？",cook_ask="需要哪道菜？先确认名称。"},
    ISFJ={permission="让我帮你{task}，可以吗？",transition="等我靠近。",enter="交接好了，我去{task}。",done="{detail}。这件事办妥了。",stop="停好了，你接着来。",care="已经伤到好几次了，别硬撑。让我来好吗？",cook_ask="想吃什么？我先看看材料。"},
    ESTJ={permission="任务：{task}。是否授权接管？",transition="先完成覆盖。",enter="覆盖完成，现在{task}。",done="{detail}。本项结束。",stop="执行停止，交还操作。",care="继续这么挨打不行。授权我接管战斗吗？",cook_ask="先报菜名，按实际材料做。"},
    ESFJ={permission="让我替你{task}吧，你同意吗？",transition="先等我完成交接。",enter="好了，我来{task}。",done="{detail}，总算办好了。",stop="停下了，现在由你来。",care="你都被打中好几次了。让我接手吧，好吗？",cook_ask="今天想吃哪道？"},
    ISTP={permission="我来{task}？",transition="等覆盖。",enter="好了，{task}。",done="{detail}。",stop="停了。你来。",care="别硬接了。换我？",cook_ask="做什么菜？"},
    ISFP={permission="这件{task}，想让我接手吗？",transition="等我到你身边。",enter="覆盖好了，我来{task}。",done="{detail}。可以把手松一下了。",stop="停在这里，交给你。",care="看到你这样挨打，心里有点发紧。让我来好吗？",cook_ask="想吃什么味道？先告诉我菜名。"},
    ESTP={permission="{task}这事换我来，行吗？",transition="等我覆盖好。",enter="好了，开始{task}。",done="{detail}。拿到结果了。",stop="停！操作还你。",care="别站着换血了。换我接手试试？",cook_ask="想吃什么？挑一道，我找料。"},
    ESFP={permission="要不这次{task}让我来？",transition="等我过去！",enter="好了！现在我来{task}。",done="{detail}！可以喘口气了。",stop="停下啦，你来操作。",care="别再打中了，看得我揪心。让我接一回好吗？",cook_ask="今天吃什么？报个你想吃的菜名。"},
}
return function(code,key,args)
    local progress={original="{detail}",INTJ="进度：{detail}",INTP="目前的结果：{detail}",ENTJ="正在推进：{detail}",ENTP="有进展了：{detail}",INFJ="这一步：{detail}",INFP="做到这里了：{detail}",ENFJ="这边的进展：{detail}",ENFP="看，推进了一步！{detail}",ISTJ="记录进度：{detail}",ISFJ="这边办到这里了：{detail}",ESTJ="执行进度：{detail}",ESFJ="这一步处理好了：{detail}",ISTP="{detail}",ISFP="这边：{detail}",ESTP="继续，{detail}",ESFP="有进展啦！{detail}"}
    local text=key=="progress" and (progress[code] or progress.original) or (T[code] or T.original)[key] or "{detail}"
    return (text:gsub("{(%w+)}",function(k) return tostring(args and args[k] or "") end))
end
