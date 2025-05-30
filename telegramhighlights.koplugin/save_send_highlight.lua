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

local function saveAndSendHighlightToBot(self, instance,  _current_attempt)
    _current_attempt = _current_attempt or 1
   

    if not instance.selected_text or not instance.selected_text.text or instance.selected_text.text == "" then
        UIManager:show(Notification:new { text = _("No text selected.") })

        functions.handleWifiTurnOff()
        return
    end

    local code = self.verification_code
    if code == "" then
        UIManager:show(InfoMessage:new {
            title = _("Configuration Error"),
            text = _("Please set your verification code in the Telegram Highlights settings menu."),
            timeout = 7
        })

        functions.handleWifiTurnOff()
        return
    end
    code = code:upper()

    local text = util.cleanupSelectedText(instance.selected_text.text)
    local file_path = self.ui.document.file
    local path, filename = util.splitFilePathName(file_path)
    local title = self.ui.doc_props and self.ui.doc_props.title or filename or _("Unknown Book")
    local author = self.ui.doc_props and self.ui.doc_props.authors or _("Unknown Author")
    
    local pos0, pos1, page, pageno, datetime  
    local chapter
    

    if instance.selected_text then  
        pos0 = instance.selected_text.pos0  
        pos1 = instance.selected_text.pos1  
        datetime = os.date("!%Y-%m-%dT%H:%M:%SZ") -- Current time in ISO format  
          
        -- Extract page number based on document type  
        if self.ui.paging then  
            -- PDF documents: page number is directly in pos0.page  
            page = pos0.page  
            pageno = pos0.page  
        else  
            -- EPUB documents: pos0 is XPointer, need to convert  
            page = pos0  
            pageno = self.ui.document:getPageFromXPointer(pos0)  
        end  
    end  

    if pageno then
        chapter = instance.ui.toc:getTocTitleOfCurrentPage() -- Use 'page' (raw reference) not 'pageno'
        if chapter == "" then
            chapter = nil
        end
    end
    
    local payload = {
        code = code,
        text = text,
        title = title,
        author = author,
        page = page,
        pageno = pageno,
        pos0 = pos0,
        pos1 = pos1,
        datetime = datetime,
        chapter = chapter,
    }

    local ok_json, json_payload = pcall(JSON.encode, payload)
    if not ok_json then
        logger.warn("Send to Bot: Error encoding JSON payload:", json_payload)
        UIManager:show(InfoMessage:new { title = _("Send to Bot Error"), text = _("Failed to prepare data."), timeout = 5 })

        functions.handleWifiTurnOff()
        return
    end

    local function close_instance() 
        instance:onClose()
    end

    local function actual_perform_send_request()


        if not NetworkMgr:isConnected() then    
            logger.info("Send to Bot: Network not connected. Using WiFi action setting.")    
              
            -- Add error handling for LIPC issues  
            local success, result = pcall(function()  
                NetworkMgr:beforeWifiAction(function()    
                    saveAndSendHighlightToBot(self, instance, 1) -- Start fresh  
                end)  
            end)  
              
            if not success then  
                logger.warn("WiFi action failed:", result)  
                -- Fall back to manual prompt  
                NetworkMgr:promptWifiOn(function()  
                    saveAndSendHighlightToBot(self, instance, 1) -- Start fresh  
                end, _("Connect to Wi-Fi to send the screenshot?"))  
            end  
            return    
        end

        if _current_attempt == 1  then
            instance:saveHighlight(true)
            UIManager.close(instance.highlight_dialog)
        end

        local co = coroutine.create(function(handler_func_co)
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
                response_code_req = -1
                logger.warn("Send to Bot: http.request pcall failed:", req_res_or_err)
            else
                response_body_req = table.concat(sink)
                if type(req_res_or_err) == "number" then
                    response_code_req = req_res_or_err
                elseif type(req_res_or_err) == "table" and type(req_res_or_err[1]) == "number" then
                    response_code_req = req_res_or_err[1]
                else
                    response_code_req = nil
                end
                local json_ok, json_response = pcall(JSON.decode, response_body_req)
                if json_ok and json_response and type(json_response) == "table" and json_response.success == true then
                    success_req = true
                    response_code_req = response_code_req or 200
                else
                    success_req = false
                    if json_ok and json_response and type(json_response) == "table" and json_response.error then
                        response_body_req = json_response.error
                    elseif not json_ok then
                        logger.warn("Send to Bot: Failed to decode JSON response:", response_body_req)
                    end
                end
            end
            local runner = coroutine.running()
            if runner and coroutine.status(runner) == "suspended" then
                coroutine.resume(runner, success_req, response_body_req, response_code_req)
            else
                logger.warn("Send to Bot: Coroutine not in suspended state, calling handler directly.")
                handler_func_co(success_req, response_body_req, response_code_req)
            end
        end)

        local function handleResult(success_res, body_res, code_res)

            if success_res then
                UIManager:show(Notification:new { text = _("Highlight sent successfully!"), timeout = 3 })
                functions.handleWifiTurnOff()
                instance:onClose()
            else
                logger.warn("Save & Send: Failed. Attempt:", _current_attempt, "Code:", code_res, "Body:", body_res)
                if _current_attempt <= MAX_AUTO_RETRIES then
                    logger.info("Save & Send: Scheduling automatic retry", _current_attempt + 1)
                    UIManager:scheduleIn(3, function()
                        saveAndSendHighlightToBot(self, instance, _current_attempt + 1)
                    end)
                else
                    logger.warn("Save & Send: Max auto retries reached. Showing dialog.")
                    local dialog_title = _("Sending Error")
                    local dialog_message

                    if code_res == -1 then -- Network error
                        dialog_title = _("Network Error")
                        local pcall_error_message = body_res and string.gsub(tostring(body_res), "Network request failed: ", "") or _("Unknown network issue.")
                        dialog_message = _("Failed to send highlight after saving due to a network issue. Would you like to retry sending?")
                        if pcall_error_message ~= "" then
                            dialog_message = dialog_message .. "\n\n" .. _("Details: ") .. pcall_error_message
                        end
                    elseif code_res == 403 then
                        dialog_title = _("Authorization Error")
                        dialog_message = _("Server rejected the request: Invalid verification code.") ..
                                         "\n\n" .. _("Please check your verification code in the settings menu.") ..
                                         "\n\n" .. _("Would you like to retry sending?")
                    elseif code_res == 400 then
                        dialog_title = _("Bad Request")
                        dialog_message = T(_("Server reported bad data (Error %1) while sending.", code_res)) ..
                                         "\n" .. _("This could be due to an issue with the data sent or a server-side problem.") ..
                                         "\nError: " .. tostring(body_res) ..
                                         "\n(URL: " .. self.BOT_SERVER_URL .. ")" ..
                                         "\n\n" .. _("Would you like to retry sending?")
                    elseif code_res == 500 then
                        dialog_title = _("Server Error")
                        dialog_message = T(_("Server encountered an internal error (Error %1) while sending. Please try again later.", code_res)) ..
                                         "\n(URL: " .. self.BOT_SERVER_URL .. ")" ..
                                         "\n\n" .. _("Would you like to retry sending?")
                    else
                        dialog_title = _("Sending Error")
                        dialog_message = T(_("Failed to send highlight after saving. Server returned error code: %1.", code_res or "Unknown")) ..
                                         "\nMessage: " .. tostring(body_res) ..
                                         "\n(URL: " .. self.BOT_SERVER_URL .. ")" ..
                                         "\n\n" .. _("Would you like to retry sending?")
                    end
                    dialog_message = _("Highlight was saved locally.") .. "\n\n" .. dialog_message

                    functions.showNetworkErrorDialog(
                        dialog_title,
                        dialog_message,
                        function()
                            saveAndSendHighlightToBot(self, instance, 1) -- Reset attempts for sending part
                        end,
                        close_instance
                    )
                end
            end
        end

        local resume_ok, err_resume = coroutine.resume(co, handleResult)
        if not resume_ok then
            logger.warn("Send to Bot: Coroutine failed to start:", err_resume)
            UIManager:show(InfoMessage:new { title = _("Internal Error"), text = _("Failed to start sending process."), timeout = 5 })
            functions.handleWifiTurnOff()
        end
    end
    actual_perform_send_request()
end

return saveAndSendHighlightToBot
