local Device = require("device")
local ffi = require("ffi")
local C = ffi.C
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
require("ffi/posix_h")

-- We need to be root to be able to set the time (CAP_SYS_TIME)
if C.getuid() ~= 0 then
    return { disabled = true, }
end

local ntp_cmd
-- Check if we have access to ntpd or ntpdate
local ntpd = util.which("ntpd")
if ntpd then
    -- Make sure it's actually busybox's implementation, as the syntax may otherwise differ...
    -- (Of particular note, Kobo ships busybox ntpd, but not ntpdate; and Kindle ships ntpdate and !busybox ntpd).
    local sym = lfs.symlinkattributes(ntpd)
    if sym and sym.mode == "link" and string.sub(sym.target, -7) == "busybox" then
        ntp_cmd = "ntpd -q -n -p pool.ntp.org"
    end
end
if not ntp_cmd and util.which("ntpdate") then
    ntp_cmd = "ntpdate pool.ntp.org"
end
if not ntp_cmd then
    return { disabled = true, }
end

local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T = require("ffi/util").template
local _ = require("gettext")
local NetworkMgr = require("ui/network/manager")

local TimeSync = WidgetContainer:extend{
    name = "timesync",
}

local function currentTime()
    local std_out = io.popen("date")
    if std_out then
        local result = std_out:read("*line")
        std_out:close()
        if result ~= nil then
            return T(_("New time is %1."), result)
        end
    end
    return _("Time synchronized.")
end

-- Bound the NTP client's runtime ourselves.
-- Both busybox's ntpd and ntpdate implement their timeouts with alarm()/SIGALRM, so neither can
-- give up if SIGALRM happens to be blocked in our signal mask -- and a signal mask is inherited
-- across fork() and preserved across execve(). That is not hypothetical: third-party Kindle
-- hotkey launchers exist that run the launched program from inside their own SIGALRM handler,
-- which leaves the signal blocked for KOReader and for everything KOReader spawns in turn. The
-- client then waits forever, os.execute() never returns, and the UI is wedged until the user
-- power-cycles the device. sleep (nanosleep) and SIGTERM are unaffected, so an external watchdog
-- still works. Same reasoning as the ping CLI fall-back in Device:ping4.
local NTP_TIMEOUT = 30 -- seconds; deliberately generous, a sync legitimately takes a few

local function runNTPClient()
    -- The watchdog counts in one-second steps instead of sleeping through the whole timeout, so
    -- it stops on its own as soon as the client is gone. That keeps a late kill from landing on a
    -- recycled pid, and bounds what we leak when cancelling it: $watchdog is the subshell, and
    -- killing that does not reach a `sleep` child of it.
    -- `wait` yields the client's own exit status; `exit` carries it past the watchdog cleanup.
    return os.execute(string.format([[%s &
                                      pid=$!
                                      (i=%d
                                       while [ $i -gt 0 ] && kill -0 $pid 2>/dev/null; do
                                           sleep 1
                                           i=$((i-1))
                                       done
                                       [ $i -eq 0 ] && kill $pid 2>/dev/null) &
                                      watchdog=$!
                                      wait $pid 2>/dev/null
                                      rc=$?
                                      kill $watchdog 2>/dev/null
                                      exit $rc
                                      ]], ntp_cmd, NTP_TIMEOUT))
end

local function syncNTP()
    local info = InfoMessage:new{
        text = _("Synchronizing time. This may take several seconds.")
    }
    UIManager:show(info)
    UIManager:forceRePaint()
    local txt
    if runNTPClient() ~= 0 then
        txt = _("Failed to retrieve time from server. Please check your network configuration.")
    else
        txt = currentTime()
        os.execute("hwclock -u -w")

        -- On Kindle, do it the native way, too, to make sure the native UI gets the memo...
        if Device:isKindle() and lfs.attributes("/usr/sbin/setdate", "mode") == "file" then
            os.execute(string.format("/usr/sbin/setdate '%d'", os.time()))
        end
    end
    UIManager:close(info)
    UIManager:show(InfoMessage:new{
        text = txt,
        timeout = 3,
    })
end

local menuItem = {
    text = _("Synchronize time"),
    keep_menu_open = true,
    callback = function()
        NetworkMgr:runWhenOnline(function() syncNTP() end)
    end
}

function TimeSync:init()
    self.ui.menu:registerToMainMenu(self)
end

function TimeSync:addToMainMenu(menu_items)
    menu_items.synchronize_time = menuItem
end

return TimeSync
