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

local MAX_AUTO_RETRIES = 2 -- Total 3 attempts: 1 initial + 2 retries

local function sendBookmarkToBot(self, bookmark_item, _current_attempt)
    _current_attempt = _current_attempt or 1
  
    local text = bookmark_item.text_orig or bookmark_item.text
    if not text or text == "" then
        logger.warn("Send to Bot: No text available in bookmark.")
        UIManager:show(Notification:new { text = _("No text available in bookmark.") })
        functions.handleWifiTurnOff()
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
        functions.handleWifiTurnOff()
        return
    end

    code = code:upper()

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

    local ok_json, json_payload = pcall(JSON.encode, payload)
    if not ok_json then
        logger.warn("Send to Bot: Error encoding JSON payload:", json_payload)
        UIManager:show(InfoMessage:new { title = _("Send to Bot Error"), text = _("Failed to prepare data."), timeout = 5 })
        functions.handleWifiTurnOff()
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
        logger.info("Send to Bot: Network not connected. Using WiFi action setting.")    
          
        -- Add error handling for LIPC issues  
        local success, result = pcall(function()  
            NetworkMgr:beforeWifiAction(function()    
                sendBookmarkToBot(self, bookmark_item, 1) -- Start fresh  
            end)  
        end)  
          
        if not success then  
            logger.warn("WiFi action failed:", result)  
            -- Fall back to manual prompt  
            NetworkMgr:promptWifiOn(function()  
                sendBookmarkToBot(self, bookmark_item, 1) -- Start fresh  
            end, _("Connect to Wi-Fi to send the screenshot?"))  
        end  
        return    
    end

    -- if not NetworkMgr:isConnected() then  
    --     logger.info("Send to Bot: Network not connected. Using WiFi action setting.")  
    --     NetworkMgr:beforeWifiAction(function()  
    --     end)  
    --     return  
    -- end
    -- progress_widget = UIManager:show(InfoMessage:new{text = _("Sending bookmark..."), timeout = 0}) -- Optional progress

    local co = coroutine.create(function(handler_func)
        local request_url = self.BOT_SERVER_URL
        local timeout = 15
        local success_req, response_body_req, response_code_req

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
            success_req = false
            response_body_req = "Network request failed: " .. tostring(req_res_or_err)
            response_code_req = -1 -- Indicate network/pcall error
            logger.warn("Send to Bot: http.request pcall failed:", req_res_or_err)
        else
            response_body_req = table.concat(sink)
            -- Determine response_code_req from req_res_or_err (which is http.request's second return value)
            if type(req_res_or_err) == "number" then
                response_code_req = req_res_or_err
            elseif type(req_res_or_err) == "table" and type(req_res_or_err[1]) == "number" then
                 -- This case might not be standard for http.request, but good to be defensive
                response_code_req = req_res_or_err[1]
            else
                 -- If http.request returns true (first val) but no code (second val), it's unusual.
                 -- For JSON APIs, we rely on parsing the body. If body parsing fails, it's not a success.
                response_code_req = nil -- Will be updated if JSON response is valid
            end

            local json_ok, json_response = pcall(JSON.decode, response_body_req)
            if json_ok and json_response and type(json_response) == "table" and json_response.success == true then
                success_req = true
                response_code_req = response_code_req or 200 -- If server said success but no code, assume 200
            else
                success_req = false
                if json_ok and json_response and type(json_response) == "table" and json_response.error then
                    response_body_req = json_response.error -- Use server's error message
                elseif not json_ok then
                    logger.warn("Send to Bot: Failed to decode JSON response:", response_body_req)
                    -- Keep original response_body_req
                end
                -- If response_code_req was not set by http.request and JSON parsing failed or success=false,
                -- it remains nil or its original http.request value.
            end
        end

        local runner = coroutine.running()
        if runner and coroutine.status(runner) == "suspended" then
            coroutine.resume(runner, success_req, response_body_req, response_code_req)
        else
            logger.warn("Send to Bot: Coroutine not in suspended state, calling handler directly.")
            handler_func(success_req, response_body_req, response_code_req)
        end
    end)

    local function handleResult(success_res, body_res, code_res)
        hideProgress()
        if success_res then
            UIManager:show(InfoMessage:new {
                text = _("Bookmark Sent"),
                timeout = 3,
            })
            functions.handleWifiTurnOff()
        else
            logger.warn("Send to Bot: Failed. Attempt:", _current_attempt, "Code:", code_res, "Body:", body_res)
            if _current_attempt <= MAX_AUTO_RETRIES then
                logger.info("Send to Bot: Scheduling automatic retry", _current_attempt + 1, "for bookmark.")
                UIManager:scheduleIn(3, function() -- 3s delay for retry
                    sendBookmarkToBot(self, bookmark_item,  _current_attempt + 1)
                end)
            else
                logger.warn("Send to Bot: Max auto retries reached for bookmark. Showing dialog.")
                local dialog_title = _("Sending Error")
                local dialog_message

                if code_res == -1 then -- Network error
                    dialog_title = _("Network Error")
                    local pcall_error_message = body_res and string.gsub(tostring(body_res), "Network request failed: ", "") or _("Unknown network issue.")
                    dialog_message = _("Failed to send bookmark due to a network issue after multiple attempts. Would you like to retry?")
                    if pcall_error_message ~= "" then
                        dialog_message = dialog_message .. "\n\n" .. _("Details: ") .. pcall_error_message
                    end
                elseif code_res == 403 then
                    dialog_title = _("Authorization Error")
                    dialog_message = _("Server rejected the request: Invalid verification code.") ..
                                     "\n\n" .. _("Please check your verification code in the settings menu.") ..
                                     "\n\n" .. _("Would you like to retry?")
                elseif code_res == 400 then
                    dialog_title = _("Bad Request")
                    dialog_message = T(_("Server reported bad data (Error %1).", code_res)) ..
                                     "\nError: " .. tostring(body_res) ..
                                     "\n(URL: " .. self.BOT_SERVER_URL .. ")" ..
                                     "\n\n" .. _("Would you like to retry?")
                elseif code_res == 500 then
                    dialog_title = _("Server Error")
                    dialog_message = T(_("Server encountered an internal error (Error %1). Please try again later.", code_res)) ..
                                     "\n(URL: " .. self.BOT_SERVER_URL .. ")" ..
                                     "\n\n" .. _("Would you like to retry?")
                else
                    dialog_title = _("Sending Error")
                    dialog_message = T(_("Failed to send bookmark. Server returned error code: %1 after multiple attempts.", code_res or "Unknown")) ..
                                   "\nMessage: " .. tostring(body_res) ..
                                   "\n(URL: " .. self.BOT_SERVER_URL .. ")" ..
                                   "\n\n" .. _("Would you like to retry?")
                end

                functions.showNetworkErrorDialog(
                    dialog_title,
                    dialog_message,
                    function()
                        sendBookmarkToBot(self, bookmark_item, 1) -- Reset attempts on manual retry
                    end,
                    nil -- No custom cancel logic needed for bookmarks
                )
            end
        end
    end

    local resume_ok, err_resume = coroutine.resume(co, handleResult)
    if not resume_ok then
        hideProgress()
        logger.warn("Send to Bot: Coroutine failed to start:", err_resume)
        UIManager:show(InfoMessage:new { title = _("Internal Error"), text = _("Failed to start sending process."), timeout = 5 })
        functions.handleWifiTurnOff()
    end
end

return sendBookmarkToBot
