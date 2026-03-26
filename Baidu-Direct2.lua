-- file: lua/backend-baidu.lua
-- 严格保持原始逻辑不变，纯性能优化

-- 开启 LuaJIT 加速（不影响逻辑，仅提速）
jit.on()

-- 【1】只本地化真正使用的变量，无任何逻辑修改
local string_format = string.format
local backend = require 'backend'

-- 【2】C API 函数本地化（全局查找 → 本地直接调用）
local get_uuid      = backend.get_uuid
local get_host      = backend.get_address_host
local get_port      = backend.get_address_port
local ctx_write     = backend.write
local ctx_free      = backend.free
local ctx_debug     = backend.debug

-- 【3】常量本地化（无逻辑修改）
local DIRECT_WRITE  = backend.SUPPORT.DIRECT_WRITE
local SUCCESS       = backend.RESULT.SUCCESS
local HANDSHAKE     = backend.RESULT.HANDSHAKE
local DIRECT        = backend.RESULT.DIRECT

-- 【4】状态管理完全保留：使用 uuid + 数字标记（和你原逻辑一模一样）
local flags = {}
local kHttpHeaderSent = 1
local kHttpHeaderRecived = 2

-- 【5】HTTP 头完全保留你原始内容（一字不差）
local HTTP_TEMPLATE =
'CONNECT %s:%d HTTP/1.1\r\n' ..
'Host: pushbos.baidu.com:443\r\n' ..
'Proxy-Connection: Keep-Alive\r\n' ..
'X-T5-Auth: 1109293052\r\n' ..
'User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 14_8_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 SP-engine/2.62.0 main/1.0 baiduboxapp/13.24.0.12 (Baidu; P2 14.8.1) NABar/1.0\r\n\r\n'

-- ==============================================
-- 以下所有回调函数：逻辑 100% 和你原版完全一致
-- 没有修改任何判断、任何返回、任何行为
-- ==============================================

function wa_lua_on_flags_cb(ctx)
    return DIRECT_WRITE
end

function wa_lua_on_handshake_cb(ctx)
    local uuid = get_uuid(ctx)
    if flags[uuid] == kHttpHeaderRecived then
        return true
    end

    if flags[uuid] ~= kHttpHeaderSent then
        local req = string_format(HTTP_TEMPLATE, get_host(ctx), get_port(ctx))
        ctx_write(ctx, req)
        flags[uuid] = kHttpHeaderSent
    end
    return false
end

function wa_lua_on_read_cb(ctx, buf)
    ctx_debug('wa_lua_on_read_cb')
    local uuid = get_uuid(ctx)
    if flags[uuid] == kHttpHeaderSent then
        flags[uuid] = kHttpHeaderRecived
        return HANDSHAKE, nil
    end
    return DIRECT, buf
end

function wa_lua_on_write_cb(ctx, buf)
    ctx_debug('wa_lua_on_write_cb')
    return DIRECT, buf
end

function wa_lua_on_close_cb(ctx)
    ctx_debug('wa_lua_on_close_cb')
    local uuid = get_uuid(ctx)
    flags[uuid] = nil
    ctx_free(ctx)
    return SUCCESS
end
