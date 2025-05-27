local logger = require("logger")
local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local Notification = require("ui/widget/notification")
local _ = require("gettext")

local functions = {}

function functions.handleWifiTurnOff(self, wifi_was_turned_on)
    if wifi_was_turned_on and self.settings.turn_off_wifi_after_sending then
        UIManager:scheduleIn(1, function()
            NetworkMgr:turnOffWifi()
            UIManager:show(Notification:new {
                text = _("WiFi turned off after sending."),
                timeout = 2,
            })
        end)
    end
end

return functions
