--- HSUtil.internal.task
--- 后台进程封装。基于 hs.task，长任务不阻塞主线程。
---
--- 两种用法：
---   1. 一次性执行完拿结果：task.run(cmd, args, onDone, timeout)
---   2. 完整控制（流式/输入/工作目录/环境变量/pid/暂停恢复）：
---        local t = task.spawn("/usr/bin/tail", {"-f", "/var/log/system.log"})
---          :onStream(function(task, out, err) ... end)   -- 边跑边收
---          :onDone(function(code, out, err) ... end)
---          :cwd("/tmp")
---          :env({ PATH = "/usr/bin:/bin" })
---          :start()
---        t:pause()  t:resume()  t:kill()  t:pid()
---
--- 关键事实（来自源码）：
---   * launchPath 必须是完整路径（/bin/ls 不是 ls），不经 shell，参数无需转义，天然防注入。
---   * 不支持管道 |、重定向 >、通配符 *（这些是 shell 特性）。要管道得起两个 task 用 onStream+write 串。
---   * 所有回调在主线程执行（dispatch_sync main queue），回调里别跑重活。
local task = {}

local hstask = require("hs.task")

-- =====================================================================
-- 便捷：一次性执行
-- =====================================================================

--- 后台执行命令，完成后回调。
--- @param cmd string 可执行文件完整路径
--- @param args table 参数数组（字符串）
--- @param onDone function(stdout, stderr, exitCode) 回调
--- @param timeoutSec number|nil 超时秒数，超时则 SIGTERM，默认无
--- @return hs.task object
function task.run(cmd, args, onDone, timeoutSec)
    onDone = onDone or function() end
    local t = hstask.new(cmd, function(exitCode, stdout, stderr)
        onDone(stdout or "", stderr or "", exitCode)
    end, args)
    if timeoutSec then
        hs.timer.doAfter(timeoutSec, function()
            if t:isRunning() then
                pcall(function() t:terminate() end)
                onDone("", "timeout", -1)
            end
        end)
    end
    t:start()
    return t
end

-- =====================================================================
-- 完整控制：spawn 构造器（链式配置）
-- =====================================================================

local _log = hs.logger.new("HSUtil.task", "info")

local Task = {}
Task.__index = Task

--- 创建一个可控任务（未启动）。
--- @param cmd string 完整路径
--- @param args table|nil 参数数组
--- @return Task 包装对象
function task.spawn(cmd, args)
    return setmetatable({
        _cmd = cmd,
        _args = args or {},
        _onDone = nil,
        _onStream = nil,
        _cwd = nil,
        _env = nil,
        _input = nil,
        _timeout = nil,
        _timer = nil,
        _hs = nil,       -- 底层 hs.task 对象（start 后才有）
        _started = false,
    }, Task)
end

--- 结束回调。function(exitCode, stdout, stderr)
function Task:onDone(fn)    self._onDone = fn; return self end

--- 流式回调。function(stdout, stderr) -> boolean
--- 返回 true 继续，false 停止接收。注意：进程结束后会最后一次以 nil task 调用（last gasp）。
--- 出错自动记日志并停止，不把异常泄漏给 hs.task（否则会误报"未返回 boolean"）。
function Task:onStream(fn)
    self._onStream = function(taskObj, out, err)
        local ok, cont = pcall(fn, out or "", err or "")
        if not ok then
            _log.e("task.onStream error: " .. tostring(cont))
            return false
        end
        if cont == nil then cont = true end
        return cont and true or false
    end
    return self
end

--- 设置工作目录（启动前）
function Task:cwd(dir)       self._cwd = dir; return self end

--- 设置环境变量（启动前，覆盖继承的环境）。传 {} 表示清空。
function Task:env(vars)     self._env = vars or {}; return self end

--- 给 stdin 喂数据（启动前或启动后均可；多次调会丢弃未消费的旧数据）
function Task:write(data)   self._input = data; return self end

--- 超时秒数，到点 SIGTERM。默认无超时。
function Task:timeout(sec)  self._timeout = sec; return self end

--- 启动任务。
--- @return Task self（启动失败返回 nil + err）
function Task:start()
    if self._started then return self end

    -- hs.task.new 第 3 参（streamCallback）不能传 nil，须按情况选传
    local t, err
    local function doneCb(exitCode, stdout, stderr)
        self:_finish(exitCode, stdout, stderr)
    end
    if self._onStream then
        t, err = hstask.new(self._cmd, doneCb, self._onStream, self._args)
    else
        t, err = hstask.new(self._cmd, doneCb, self._args)
    end
    if not t then return nil, err end

    if self._cwd then t:setWorkingDirectory(self._cwd) end
    if self._env then
        local ok = t:setEnvironment(self._env)
        if ok == false then return nil, "setEnvironment failed (task already running?)" end
    end
    if self._input then t:setInput(self._input) end

    t:start()
    self._hs = t
    self._started = true

    if self._closeInputPending then t:closeInput() end

    if self._timeout then
        self._timer = hs.timer.doAfter(self._timeout, function()
            if self._hs and self._hs:isRunning() then
                pcall(function() self._hs:terminate() end)
                self:_finish(-1, "", "timeout")
            end
        end)
    end
    return self
end

--- 内部：进程结束统一处理（去重，防 timeout 重复触发）
function Task:_finish(exitCode, stdout, stderr)
    if self._timer then self._timer:stop(); self._timer = nil end
    if self._finished then return end
    self._finished = true
    if self._onDone then
        local ok, e = pcall(self._onDone, exitCode, stdout or "", stderr or "")
        if not ok then _log.e("task.onDone error: " .. tostring(e)) end
    end
end

--- 关闭 stdin（给长任务发 EOF，通常配合 onStream 用）
--- 启动前调用：记录意图，start 后立即关。
--- 启动后调用：立即关。
function Task:closeInput()
    if self._hs then
        self._hs:closeInput()
    else
        self._closeInputPending = true
    end
    return self
end

--- 发 SIGTERM（优雅终止）
function Task:kill()
    if self._hs then pcall(function() self._hs:terminate() end) end
    return self
end

--- 发 SIGINT（Ctrl-C）
function Task:interrupt()
    if self._hs then pcall(function() self._hs:interrupt() end) end
    return self
end

--- 挂起（可多次调，需对应次数 resume 才能继续）
function Task:pause()
    if self._hs then self._hs:pause() end
    return self
end

--- 恢复
function Task:resume()
    if self._hs then self._hs:resume() end
    return self
end

--- 是否在跑
function Task:isRunning()
    return self._hs and self._hs:isRunning() or false
end

--- 进程号（启动后才有）
function Task:pid()
    if self._hs then return self._hs:pid() end
    return nil
end

--- 退出码
function Task:exitCode()
    if self._hs then return self._hs:terminationStatus() end
    return nil
end

--- 退出原因："exit"（正常退出）/ "signal"（被信号杀）
function Task:exitReason()
    if self._hs then return self._hs:terminationReason() end
    return nil
end

--- 底层 hs.task 对象（需要调未暴露的方法时用）
function Task:raw()
    return self._hs
end

return task
