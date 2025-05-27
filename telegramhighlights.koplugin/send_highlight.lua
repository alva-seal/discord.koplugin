local InfoMessage = require("ui/widget/infomessage")
local JSON = require("json")
local NetworkMgr = require("ui/network/manager")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local http = require("socket.http")
local ltn12 = require("ltn12")
local socketutil = require("socketutil")
local util = require("util")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template
local functions = require("functions")

local function sendHighlightToBot(self, instance, was_wifi_turned_on)
   
    was_wifi_turned_on = was_wifi_turned_on or false


    -- Helper function to clear selection and refresh
    local function clearSelection()
        if self.ui and self.ui.document and type(self.ui.document.clearSelection) == "function" then
            self.ui.document:clearSelection()
        else
            logger.warn("clearSelection: self.ui.document.clearSelection is not available or not a function.")
        end
     end
    -- 1. Determine the source of the text (new selection or existing highlight)
    local text
    local is_existing_highlight = instance.selected_link and instance.selected_link.note
    if is_existing_highlight then
        text = instance.selected_link.note
        -- logger.info("Send to Bot: Using text from existing highlight")
    elseif instance.selected_text and instance.selected_text.text and instance.selected_text.text ~= "" then
        text = instance.selected_text.text
        -- logger.info("Send to Bot: Using text from new selection")
    else
        logger.warn("Send to Bot: No text available.")
        UIManager:show(Notification:new { text = _("No text available.") })
        clearSelection()
        return
    end

    -- 2. Get the verification code
    local code = self.verification_code
    if code == "" then
        logger.warn("Send to Bot: Verification code is not set!")
        UIManager:show(InfoMessage:new {
            title = _("Configuration Error"),
            text = _("Please set your verification code in the Telegram Highlights settings menu."),
            timeout = 7
        })
        clearSelection()
        return
    end

    -- Make sure code is uppercase if the server expects it
    code = code:upper()

    -- 3. Prepare payload
    text = util.cleanupSelectedText(text)
    local file_path = self.ui.document.file  
    local path, filename = util.splitFilePathName(file_path)
    local title = self.ui.doc_props and self.ui.doc_props.title or filename or _("Unknown Book")
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
        clearSelection()
        return
    end

    -- 4. Check network and perform request
    local function performSendRequest()
    
        UIManager:close(instance.highlight_dialog)
        -- UIManager:show(Notification:new { text = _("Sending!"), timeout = 1.5 })
    
        local _showProgress = function()
            if not instance._progress_widget then
                instance._progress_widget = InfoMessage:new { text = _("Sending highlight to bot..."), timeout = 0 }
                UIManager:show(instance._progress_widget)
            end
        end
        local _hideProgress = function()
            if instance._progress_widget then
                UIManager:close(instance._progress_widget)
                instance._progress_widget = nil
            end
        end

        if not NetworkMgr:isConnected() then
            _hideProgress()
            logger.info("Send to Bot: Network not connected. Prompting for Wi-Fi.")
            NetworkMgr:promptWifiOn(function()
                -- logger.info("Send to Bot: Wi-Fi possibly enabled, retrying send...")
                sendHighlightToBot(self, instance, true)
            end, _("Connect to Wi-Fi to send the highlight to the bot?"))
            return
        end

        -- UIManager:show(Notification:new {
        --     text = _("Sending Highlight"),
        --     timeout = 2,
        -- })
        _showProgress()

        -- Perform the HTTP POST request in a coroutine
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
            _hideProgress()
            if success then
                UIManager:show(Notification:new { text = _("Highlight sent successfully!"), timeout = 2 })
                clearSelection()
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
                clearSelection()
                UIManager:close(instance.highlight_dialog)
            end
        end

        local resume_ok, err = coroutine.resume(co, handleResult)
        if not resume_ok then
            logger.warn("Send to Bot: Coroutine failed to start:", err)
            _hideProgress()
            UIManager:show(InfoMessage:new { title = _("Internal Error"), text = _("Failed to start sending process."), timeout = 5 })
            clearSelection()
        end
        functions.handleWifiTurnOff(self, was_wifi_turned_on)
    end

    -- 5. Call the send request function
    performSendRequest()
end

return sendHighlightToBot
