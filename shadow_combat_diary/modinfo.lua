name = "如影随形 · 战斗反馈日志"
description = "独立客户端调试日志：受击时间、生命下降、关卡与死亡前30秒回放。死亡自动输出中文反馈；附带Windows导出工具。不接管战斗。"
author = "Shadow Self debugging tools"
version = "1.2.0"
api_version = 10
dst_compatible = true
client_only_mod = true
all_clients_require_mod = false
server_only_mod = false
configuration_options = {
    {name="auto_record",label="进世界自动记录",options={{description="开启",data=true},{description="关闭",data=false}},default=true},
    {name="sample_interval",label="死亡回放采样间隔",options={{description="0.25秒",data=.25},{description="0.5秒",data=.5},{description="1秒",data=1}},default=.25},
    {name="show_buttons",label="显示日志按钮",options={{description="显示",data=true},{description="隐藏",data=false}},default=true},
}
