---Minimal stand-ins for the FiveM/CFX globals kora_lib's modules call directly
---(RegisterNetEvent, TriggerServerEvent, CreateThread, promise, ...), so module
---files can be `dofile`'d and smoke-tested under plain Lua. Native functions
---specific to a single module (e.g. CreatePed, glm.vec3) are mocked in that
---module's own smoke test instead of here.
local M = {}

-- The one simulated player every smoke test triggers server events as.
M.SOURCE = 1

---Scans a recorded event list (triggeredServerEvents/triggeredClientEvents)
---backwards for the most recent entry with `name` -- the lookup several smoke
---tests need after driving a request through the mock network.
---@param entries table[]
---@param name string
---@return table | nil entry
function M.lastEntry(entries, name)
    for i = #entries, 1, -1 do
        if entries[i].name == name then return entries[i] end
    end
    return nil
end

---Installs the mocked globals into _G. Returns handles into the mock network
---state so tests can inspect what was sent/registered or fire an event directly.
function M.install()
    local mockClock = 0
    local FRAME_MS = 16 -- nominal ms per Wait(), so timers/timeouts still progress without a real sleep

    local netHandlers = {}
    local eventHandlers = {}
    local triggeredServerEvents = {}
    local triggeredClientEvents = {}
    local threads = {}

    _G.source = nil

    -- Minimal kora_lib Kora stand-in -- only what a bridge adapter touches
    -- directly (client/bridge/stub.lua and client/bridge/qbcore.lua both call
    -- Kora.status.getActive() for the snapshot's `status` field).
    _G.Kora = { status = { getActive = function() return {} end } }

    function _G.RegisterNetEvent(name, cb)
        netHandlers[name] = netHandlers[name] or {}
        table.insert(netHandlers[name], cb)
    end

    function _G.AddEventHandler(name, cb)
        eventHandlers[name] = eventHandlers[name] or {}
        table.insert(eventHandlers[name], cb)
    end

    function _G.TriggerEvent(name, ...)
        for _, fn in ipairs(eventHandlers[name] or {}) do fn(...) end
        for _, fn in ipairs(netHandlers[name] or {}) do fn(...) end
    end

    -- Client -> server. Sets `source` the way FiveM sets it for the receiving
    -- server-side handler, then dispatches straight into any server.lua loaded
    -- into this same process -- which is what makes an in-process round trip work.
    function _G.TriggerServerEvent(name, ...)
        table.insert(triggeredServerEvents, { name = name, ... })

        local previousSource = _G.source
        _G.source = M.SOURCE

        for _, fn in ipairs(netHandlers[name] or {}) do fn(...) end

        _G.source = previousSource
    end

    -- Server -> client. `target` is recorded but not used to filter delivery --
    -- these tests only ever simulate a single connected client.
    function _G.TriggerClientEvent(name, target, ...)
        table.insert(triggeredClientEvents, { name = name, target = target, ... })

        for _, fn in ipairs(netHandlers[name] or {}) do fn(...) end
    end

    -- Runs the thread body in a coroutine and resumes it exactly once. One-shot
    -- threads (no Wait/yield) run to completion, same as in FiveM. Threads with
    -- a `while true ... Wait() end` loop run one iteration and then sit
    -- suspended, which is enough to smoke-test the loop body without hanging
    -- the test process on an infinite loop. Every thread is retained so a test
    -- can drive further iterations on demand -- see `step` in the returned handle.
    function _G.CreateThread(fn)
        local co = coroutine.create(fn)
        table.insert(threads, co)

        local ok, err = coroutine.resume(co)
        if not ok then
            error(("CreateThread body errored: %s"):format(tostring(err)), 0)
        end
    end

    function _G.Wait(ms)
        mockClock = mockClock + math.max(ms or 0, FRAME_MS)
        if coroutine.isyieldable() then
            coroutine.yield()
        end
    end

    function _G.GetGameTimer()
        return mockClock
    end

    -- Every smoke test drives success/failure paths synchronously (the mock
    -- network resolves/rejects before a real timeout would ever matter), so
    -- SetTimeout callbacks are simply never fired.
    function _G.SetTimeout(_, _) end

    function _G.GetInvokingResource()
        return nil
    end

    function _G.GetCurrentResourceName()
        return "kora_lib_test"
    end

    -- Not a real joaat -- just deterministic, so the same string always hashes
    -- the same way within a test run.
    function _G.joaat(str)
        local hash = 0
        for i = 1, #str do
            hash = (hash * 31 + str:byte(i)) % 4294967296
        end
        return hash
    end

    local promiseMt = {}
    promiseMt.__index = promiseMt

    function promiseMt:resolve(value)
        if self.state ~= "pending" then return end
        self.state = "resolved"
        self.value = value
        for _, cb in ipairs(self.onResolved) do cb(value) end
    end

    function promiseMt:reject(err)
        if self.state ~= "pending" then return end
        self.state = "rejected"
        self.value = err
        for _, cb in ipairs(self.onRejected) do cb(err) end
    end

    -- Mirrors CfxLua's deferred-library signature, next(onResolved, onRejected),
    -- including callbacks registered while still pending firing on settlement --
    -- code under test attaches settle handlers before the answer arrives.
    function promiseMt:next(onResolved, onRejected)
        if self.state == "resolved" then
            if onResolved then onResolved(self.value) end
        elseif self.state == "rejected" then
            if onRejected then onRejected(self.value) end
        else
            if onResolved then table.insert(self.onResolved, onResolved) end
            if onRejected then table.insert(self.onRejected, onRejected) end
        end

        return self
    end

    function promiseMt:catch(fn)
        return self:next(nil, fn)
    end

    _G.promise = {
        new = function()
            return setmetatable({ state = "pending", onResolved = {}, onRejected = {} }, promiseMt)
        end,
    }

    _G.Citizen = {
        Await = function(p)
            if p.state == "resolved" then return p.value end
            if p.state == "rejected" then error(p.value, 0) end
            error("mock Citizen.Await: promise never settled synchronously", 0)
        end,
    }

    return {
        netHandlers = netHandlers,
        eventHandlers = eventHandlers,
        triggeredServerEvents = triggeredServerEvents,
        triggeredClientEvents = triggeredClientEvents,
        -- Fires both AddEventHandler and RegisterNetEvent handlers for `name`,
        -- for tests that need to simulate lifecycle events directly
        -- (playerDropped, onResourceStop, onClientResourceStop).
        fire = function(name, ...)
            _G.TriggerEvent(name, ...)
        end,
        -- Resumes every still-suspended CreateThread coroutine once, i.e.
        -- advances each `while true ... Wait() end` loop by one iteration.
        -- Needed to test anything driven by a tick rather than by a direct
        -- call (zone enter/exit tracking, the cache refresh loop), since
        -- CreateThread above only resumes each thread once on its own.
        step = function()
            for _, co in ipairs(threads) do
                if coroutine.status(co) == "suspended" then
                    local ok, err = coroutine.resume(co)
                    if not ok then
                        error(("stepped thread errored: %s"):format(tostring(err)), 0)
                    end
                end
            end
        end,
    }
end

return M
