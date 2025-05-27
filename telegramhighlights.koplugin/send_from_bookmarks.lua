local InfoMessage  = require("ui/widget/infomessage")
local JSON         = require("json")
local NetworkMgr   = require("ui/network/manager")
local Notification = require("ui/widget/notification")
local UIManager    = require("ui/uimanager")
local http         = require("socket.http")
local ltn12        = require("ltn12")
local socketutil   = require("socketutil")
local util         = require("util")
local logger       = require("logger")
local _            = require("gettext")
local T            = require("ffi/util").template
local functions    = require("functions")


local function sendBookmarkToBot(self, bookmark_item, wifi_was_turned_on)

    wifi_was_turned_on = wifi_was_turned_on or false

    local text = bookmark_item.text_orig or bookmark_item.text
    if not text or text == "" then
        logger.warn("Send to Bot: No text available in bookmark.")
        UIManager:show(Notification:new { text = _("No text available in bookmark.") })
        return
    end

    local code = self.verification_code
    if code == "" then
        logger.warn("Send to Bot: Verification code is not set!")
        UIManager:show(InfoMessage:new {
            title = _("Configuration Error"),
            text = _("Please set your verification code in the Telegram Highlights settings menu."),
            timeout = 7
        })
        return
    end

    code = code:upper()

    text = util.cleanupSelectedText(text)
    local title = self.ui.doc_props and self.ui.doc_props.title or self.ui.document:getFileName()
    local author = self.ui.doc_props and self.ui.doc_props.authors or _("Unknown Author")
    local payload = {
        code = code,
        text = text,
        title = title,
        author = author,
    }

    local ok, json_payload = pcall(JSON.encode, payload)
    if not ok then
        logger.warn("Send to Bot: Error encoding JSON payload:", json_payload)
        UIManager:show(InfoMessage:new { title = _("Send to Bot Error"), text = _("Failed to prepare data."), timeout = 5 })
        return
    end

    local progress_widget



    local function hideProgress()
        if progress_widget then
            UIManager:close(progress_widget)
            progress_widget = nil
        end
    end

    if not NetworkMgr:isConnected() then
        logger.info("Send to Bot: Network not connected. Prompting for Wi-Fi.")
        NetworkMgr:promptWifiOn(function()
            sendBookmarkToBot(self,  bookmark_item, true)
        end, _("Connect to Wi-Fi to send the bookmark to the bot?"))
        return
    end

    local co = coroutine.create(function(handler_func)
        local request_url = self.BOT_SERVER_URL
        local timeout = 15
        local success, response_body, response_code

        local sink = {}
        socketutil:set_timeout(timeout)
        local req_params = {
            url = request_url,
            method = "POST",
            headers = {
                ["Content-Type"] = "application/json",
                ["Content-Length"] = #json_payload,
                ["User-Agent"] = "KOReader Telegram Highlights Plugin",
            },
            source = ltn12.source.string(json_payload),
            sink = ltn12.sink.table(sink),
        }

        local ok_req, req_res_or_err = pcall(http.request, req_params)
        socketutil:reset_timeout()

        if not ok_req then
            success = false
            response_body = "Network request failed: " .. tostring(req_res_or_err)
            response_code = -1
            logger.warn("Send to Bot: http.request pcall failed:", req_res_or_err)
        else
            if type(req_res_or_err) == "number" then
                response_code = req_res_or_err
            elseif type(req_res_or_err) == "table" and type(req_res_or_err[1]) == "number" then
                response_code = req_res_or_err[1]
            else
                response_code = nil
            end
            response_body = table.concat(sink)
            local json_ok, json_response = pcall(JSON.decode, response_body)
            if json_ok and json_response and type(json_response) == "table" and json_response.success == true then
                success = true
                response_code = response_code or 200
            else
                success = false
                if json_ok and json_response and type(json_response) == "table" and json_response.error then
                    response_body = json_response.error
                end
            end

        end

        local runner = coroutine.running()
        if runner and coroutine.status(runner) == "suspended" then
            coroutine.resume(runner, success, response_body, response_code)
        else
            logger.warn("Send to Bot: Coroutine not in suspended state, calling handler directly.")
            handler_func(success, response_body, response_code)
        end
    end)

    local function handleResult(success, body, code)
        hideProgress()
        if success then

            UIManager:show(InfoMessage:new {
                text = _("Bookmark Sent"),
                timeout = 3,
            })
        else
            local err_title = _("Send to Bot Error")
            local err_text
            logger.warn("Send to Bot: Failed. Code:", code, "Body:", body)
            if code == 403 then
                err_text = _("Server rejected the request: Invalid verification code.") ..
                    "\n\n" .. _("Check your verification code in the settings menu.")
            elseif code == 400 then
                err_text = _("Server reported bad data. Check bot/server logs.") ..
                    "\n(URL: " .. self.BOT_SERVER_URL .. ")"
            elseif code == 500 then
                err_text = _("Server encountered an internal error. Please try again later.") ..
                    "\n(URL: " .. self.BOT_SERVER_URL .. ")"
            elseif code == -1 or not code then
                err_text = _("Network error: ") .. tostring(body)
            else
                err_text = T(_("Server returned error code: %1"), code) .. "\n(URL: " .. self.BOT_SERVER_URL .. ")"
            end
            UIManager:show(InfoMessage:new { title = err_title, text = err_text, timeout = 10 })
        end

        -- Turn off Wi-Fi if we turned it on
        functions.handleWifiTurnOff(self, wifi_was_turned_on)
    end

    local resume_ok, err = coroutine.resume(co, handleResult)
    if not resume_ok then
        logger.warn("Send to Bot: Coroutine failed to start:", err)
        hideProgress()
        UIManager:show(InfoMessage:new { title = _("Internal Error"), text = _("Failed to start sending process."), timeout = 5 })
    end

end

return sendBookmarkToBot
