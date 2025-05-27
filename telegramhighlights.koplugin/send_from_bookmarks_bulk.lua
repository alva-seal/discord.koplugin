local JSON = require("json")
local NetworkMgr = require("ui/network/manager")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local http = require("socket.http")
local ltn12 = require("ltn12")
local socketutil = require("socketutil")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template
local functions = require("functions")
local InfoMessage = require("ui/widget/infomessage")
local util         = require("util")

local function sendBulkBookmarksToBot(self, items, wifi_was_turned_on)
    if not items or #items == 0 then
        UIManager:show(Notification:new { text = _("No bookmarks selected to send."), timeout = 2 })
        return
    end

    wifi_was_turned_on = wifi_was_turned_on or false

    local file_path = self.ui.document.file  
    local path, filename = util.splitFilePathName(file_path)

    local title = self.ui.doc_props and self.ui.doc_props.title or filename or _("Unknown Book")
    local author = self.ui.doc_props and self.ui.doc_props.authors or _("Unknown Author")
    local verification_code = self.verification_code:upper()

    local payload = {
        code = verification_code,
        title = title,
        author = author,
        bookmarks = items,
    }

    local ok_encode, json_payload_or_err = pcall(JSON.encode, payload)
    if not ok_encode then
        logger.info("Failed to encode JSON payload for bulk send:", json_payload_or_err) -- json_payload_or_err here is the error message
        UIManager:show(InfoMessage:new { title = _("Internal Error"), text = _("Failed to prepare data for sending."), timeout = 3 })
        return
    end
    -- If encoding was successful, json_payload_or_err is the actual json_payload string
    local json_payload = json_payload_or_err

    local function send_request()
        if not items or #items == 0 then
            UIManager:show(Notification:new { text = _("No bookmarks found"), timeout = 2 })
            return
        end
        -- UIManager:show(Notification:new { text = _("Sending!"), timeout = 1.5 })

        local sink = {}
        socketutil:set_timeout(30) -- Increased timeout for potentially larger payload
        local BOT_BULK_SERVER_URL = "https://koreader-plugin-bot-server.deno.dev/bulk_create"
        local req_params = {
            url = BOT_BULK_SERVER_URL,
            method = "POST",
            headers = {
                ["Content-Type"] = "application/json",
                ["Content-Length"] = #json_payload,
                ["User-Agent"] = "KOReader Telegram Highlights Plugin",
            },
            source = ltn12.source.string(json_payload),
            sink = ltn12.sink.table(sink),
        }

        -- Correctly capture return values from pcall(http.request, ...)
        -- pcall_success: boolean, true if http.request didn't error.
        -- result1: if pcall_success is true, this is the first return value of http.request (e.g., sink status like 1 or true).
        --          if pcall_success is false, this is the error message from pcall.
        -- result2: if pcall_success is true, this is the second return value of http.request (the HTTP status code).
        local pcall_success, result1, result2 = pcall(http.request, req_params)
        socketutil:reset_timeout()

        local actual_status_code
        local request_error_message

        if pcall_success then
            -- http.request executed without Lua error.
            -- result1 is the sink result (e.g., 1), result2 is the HTTP status code.
            actual_status_code = result2
            logger.info("HTTP request pcall_success: true. Sink result:", result1, "HTTP Status:", actual_status_code)
        else
            -- pcall failed, meaning http.request itself raised a Lua error.
            -- result1 is the error message.
            request_error_message = result1
            logger.info("HTTP request pcall_success: false. Error:", request_error_message)
        end

        if pcall_success and actual_status_code == 200 then
            logger.info("Successfully sent bulk bookmarks to the bot.")
            -- UIManager:show(Notification:new {
            --     text = T(_("Successfully sent %1 bookmarks."), #items),
            --     timeout = 3
            -- })
            UIManager:show(InfoMessage:new {
                text = _("Bookmarks Sent"),
                timeout = 3,
            })
            
        elseif pcall_success then -- pcall succeeded, but HTTP status is not 200
            local response_body = table.concat(sink)
            logger.info("Failed to send bulk bookmarks. Server responded with code:", actual_status_code, "Body:", response_body)
            UIManager:show(InfoMessage:new {
                title = _("Sending Error"),
                text = T(_("Failed to send bookmarks. Server responded with code: %1"), actual_status_code or "Unknown"),
                timeout = 5
            })
        else -- pcall failed, http.request itself errored. request_error_message contains the error.
            logger.info("Failed to send bulk bookmarks. Request error:", request_error_message)
            UIManager:show(InfoMessage:new {
                title = _("Network Error"),
                text = _("Failed to send bookmarks. Please check your connection."),
                timeout = 5
            })
        end
        functions.handleWifiTurnOff(self, wifi_was_turned_on)
    end

    if not NetworkMgr:isConnected() then
        NetworkMgr:promptWifiOn(function()
            sendBulkBookmarksToBot(self,  items, true)
        end, _("Connect to Wi-Fi to send bookmarks to the bot?"))
        return
    end

    send_request()
end

return sendBulkBookmarksToBot
