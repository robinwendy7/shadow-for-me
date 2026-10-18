-- 本地头顶说话颜色；默认红色，独立于角色贴图和输入框。
local M={colors={red={1,.15,.15,1},orange={1,.5,.1,1},yellow={1,.9,.15,1},green={.2,1,.3,1},cyan={.1,1,1,1},blue={.25,.5,1,1},purple={.83,.45,1,1}}}
function M.Color(options) return M.colors[options and options.speech_color] or M.colors.red end
return M
