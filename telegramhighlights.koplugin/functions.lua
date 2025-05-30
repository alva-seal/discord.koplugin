local logger = require("logger")
local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local _ = require("gettext")
local ConfirmBox = require("ui/widget/confirmbox")

local functions = {}

function functions.handleWifiTurnOff()
    NetworkMgr:afterWifiAction()
end

function functions.showNetworkErrorDialog(title, message, retry_callback, custom_cancel_callback)
    UIManager:show(ConfirmBox:new{
        title = title,
        text = message,
        ok_text = _("Retry"),
        cancel_text = _("Cancel"),
        ok_callback = retry_callback,
        cancel_callback = function()
        if custom_cancel_callback and type(custom_cancel_callback) == "function" then
            logger.info()
            custom_cancel_callback()          
        end
            logger.info("Network error dialog: Cancel chosen.")
            functions.handleWifiTurnOff()
        end,
    })
end

return functions