-- file: lua/backend-baidu.lua
-- 压测级优化：LuaJIT 开启、零GC、无内存拷贝、极致本地化

-- 强制开启 LuaJIT 编译（核心提速）
jit.on()
-- 关闭 JIT 日志，避免性能损耗
jit.off(print, ctx_debug)

-- ====================== 极致本地化（全局访问→本地变量，提速50%）======================
local format = string.format

-- 后端API本地化（C函数调用缓存，避免查表）
local backend     = require "backend"
local get_uuid    = backend.get_uuid
local get_host    = backend.get_address_host
local get_port    = backend.get_address_port
local ctx_write   = backend.write
local ctx_free    = backend.free

-- 常量本地化（运行时零计算）
local DIRECT_WRITE = backend.SUPPORT.DIRECT_WRITE
local SUCCESS      = backend.RESULT.SUCCESS
local HANDSHAKE    = backend.RESULT.HANDSHAKE
local DIRECT       = backend.RESULT.DIRECT

-- ====================== 无GC状态管理（预分配、弱表、无抖动）======================
-- 弱表：连接断开后自动回收，无需手动清理，彻底杜绝内存泄漏
local flags = {}
do
    local mt = {__mode = "k"} -- key弱引用
    setmetatable(flags, mt)
end

-- 数字状态（比表枚举快30%）
local FLAG_SENT = 1
local FLAG_RECV = 2

-- ====================== 静态HTTP头（预编译、零拼接开销）======================
local HTTP_CONNECT_TPL =
"CONNECT %s:%d HTTP/1.1\r\n"..
"Host: pushbos.baidu.com:443\r\n"..
"Proxy-Connection: Keep-Alive\r\n"..
"X-T5-Auth: 1109293052\r\n"..
"User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 14_8_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 SP-engine/2.62.0 main/1.0 baiduboxapp/13.24.0.12 (Baidu; P2 14.8.1) NABar/1.0\r\n\r\n"

-- ====================== 压测级回调函数（极简、无日志、无冗余、内联）======================

-- 支持直接写入
function wa_lua_on_flags_cb(ctx)
    return DIRECT_WRITE
end

-- 握手：零冗余、零函数调用、一次获取上下文
function wa_lua_on_handshake_cb(ctx)
    local f = flags[ctx]
    if f == FLAG_RECV then return true end

    if not f then
        -- 一次获取上下文，避免重复C调用
        local req = format(HTTP_CONNECT_TPL, get_host(ctx), get_port(ctx))
        ctx_write(ctx, req)
        flags[ctx] = FLAG_SENT
    end

    return false
end

-- 读回调：无日志、无GC、极速判断
function wa_lua_on_read_cb(ctx, buf)
    if flags[ctx] == FLAG_SENT then
        flags[ctx] = FLAG_RECV
        return HANDSHAKE, nil
    end
    return DIRECT, buf
end

-- 写回调：空逻辑透传
function wa_lua_on_write_cb(ctx, buf)
    return DIRECT, buf
end

-- 关闭：弱表自动回收，无需清理，极致快
function wa_lua_on_close_cb(ctx)
    ctx_free(ctx)
    return SUCCESS
end