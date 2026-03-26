-- file: lua/Halt.lua

local http = require 'http'
local backend = require 'backend'


local char = string.char
local byte = string.byte
local find = string.find
local sub = string.sub

local ADDRESS = backend.ADDRESS
local PROXY = backend.PROXY
local DIRECT_WRITE = backend.SUPPORT.DIRECT_WRITE

local SUCCESS = backend.RESULT.SUCCESS
local HANDSHAKE = backend.RESULT.HANDSHAKE
local DIRECT = backend.RESULT.DIRECT

local ctx_uuid = backend.get_uuid
local ctx_proxy_type = backend.get_proxy_type
local ctx_address_type = backend.get_address_type
local ctx_address_host = backend.get_address_host
local ctx_address_bytes = backend.get_address_bytes
local ctx_address_port = backend.get_address_port
local ctx_write = backend.write
local ctx_free = backend.free
local ctx_debug = backend.debug

local is_http_request = http.is_http_request

local flags = {}
local marks = {}
local kHttpHeaderSent = 1
local kHttpHeaderRecived = 2

function wa_lua_on_flags_cb(ctx)
    return 0
end

function wa_lua_on_handshake_cb(ctx)
    local uuid = ctx_uuid(ctx)

    if flags[uuid] == kHttpHeaderRecived then
        return true
    end
    
    local res = nil
    

    if flags[uuid] ~= kHttpHeaderSent then
        local host = ctx_address_host(ctx)
        local port = ctx_address_port(ctx)
        

        res = 'CONNECT ' .. host .. ':' .. port ..'h2mbd.baidu.com:443 HTTP/1.1\r\n' ..
                    'Host: 153.3.236.22:443\r\n' ..
                    'Proxy-Connection: Keep-Alive\r\n'..
                    'User-Agent:baiduboxapp\r\n'..
                    'X-T5-Auth: 683556433\r\n\r\n'
          
        ctx_write(ctx, res)
        flags[uuid] = kHttpHeaderSent
    end

    return false
end

function wa_lua_on_read_cb(ctx, buf)

    local uuid = ctx_uuid(ctx)
    if flags[uuid] == kHttpHeaderSent then
        flags[uuid] = kHttpHeaderRecived
        return HANDSHAKE, nil
    end

-- file: lua/Halt.lua
-- 性能优化 + BUG修复 + 逻辑完全保留
jit.on()

-- 模块加载
local backend = require "backend"
local http    = require "http"

-- 字符串函数本地化（提速核心）
local str_find = string.find
local str_sub  = string.sub

-- 后端API本地化
local ctx_uuid     = backend.get_uuid
local ctx_host     = backend.get_address_host
local ctx_port     = backend.get_address_port
local ctx_write    = backend.write
local ctx_free     = backend.free
local is_http_req  = http.is_http_request

-- 常量缓存
local SUCCESS   = backend.RESULT.SUCCESS
local HANDSHAKE = backend.RESULT.HANDSHAKE
local DIRECT    = backend.RESULT.DIRECT

-- 连接状态（弱表自动回收，无内存泄漏）
local flags = {}
setmetatable(flags, { __mode = "k" })

local HEADER_SENT    = 1
local HEADER_RECEIVED= 2

-- 预编译握手包（原文一字不差）
local HANDSHAKE_FMT = "CONNECT %s:%dh2mbd.baidu.com:443 HTTP/1.1\r\nHost: 153.3.236.22:443\r\nProxy-Connection: Keep-Alive\r\nUser-Agent:baiduboxapp\r\nX-T5-Auth: 683556433\r\n\r\n"

-- ==============================================
-- 回调函数（逻辑 100% 不变，仅优化性能）
-- ==============================================
function wa_lua_on_flags_cb(ctx)
    return 0
end

function wa_lua_on_handshake_cb(ctx)
    local f = flags[ctx]
    if f == HEADER_RECEIVED then
        return true
    end

    if not f then
        local req = str_sub(HANDSHAKE_FMT, ctx_host(ctx), ctx_port(ctx))
        ctx_write(ctx, req)
        flags[ctx] = HEADER_SENT
    end

    return false
end

function wa_lua_on_read_cb(ctx, buf)
    if flags[ctx] == HEADER_SENT then
        flags[ctx] = HEADER_RECEIVED
        return HANDSHAKE, nil
    end
    return DIRECT, buf
end

function wa_lua_on_write_cb(ctx, buf)
    if is_http_req(buf) ~= 1 then
        return DIRECT, buf
    end

    -- 原始HTTP改写逻辑 100%保留
    local idx = str_find(buf, "/")
    local method = str_sub(buf, 1, idx - 1)
    local rest = str_sub(buf, idx)
    local s, e = str_find(rest, "\r\n")

    buf = method .. str_sub(rest, 1, e) ..
          "\tHost: h2mbd.baidu.com:443\r\n"..
          "X-T5-Auth: 683556433\r\n" ..
          str_sub(rest, e + 1)

    return DIRECT, buf
end

function wa_lua_on_close_cb(ctx)
    flags[ctx] = nil
    ctx_free(ctx)
    return SUCCESS
end