local http = require("socket.http")  
local ltn12 = require("ltn12")  
local UIManager = require("ui/uimanager")  
local InfoMessage = require("ui/widget/infomessage")  
local NetworkMgr = require("ui/network/manager")  
local _ = require("gettext")  

local function sendScreenshotToBot(plugin, screenshot_path, wifi_was_turned_on)
    
    wifi_was_turned_on = wifi_was_turned_on or false

    if not NetworkMgr:isConnected() then
        NetworkMgr:promptWifiOn(function()
            sendScreenshotToBot(plugin, screenshot_path, true)
        end, _("Connect to Wi-Fi to send bookmarks to the bot?"))
        return
    end

    -- Check if file exists  
    local file = io.open(screenshot_path, "rb")  
    if not file then  
        UIManager:show(InfoMessage:new{  
            text = _("Screenshot file not found."),  
        })  
        return  
    end  
      
    --  check the verification code
    if not plugin.verification_code or plugin.verification_code == "" then  
        UIManager:show(InfoMessage:new{  
            text = _("Please set your verification code in the plugin settings."),  
        })  
        return  
    end

    local image_data = file:read("*all")  
    file:close()  
      

      
    -- Create multipart form data  
    local boundary = "----formdata" .. os.time()  
    local body_parts = {}  
      
    -- Add verification code  
    table.insert(body_parts, "--" .. boundary)  
    table.insert(body_parts, 'Content-Disposition: form-data; name="code"')  
    table.insert(body_parts, "")  
    table.insert(body_parts, plugin.verification_code)
    
    -- Add image file  
    table.insert(body_parts, "--" .. boundary)  
    table.insert(body_parts, 'Content-Disposition: form-data; name="image"; filename="screenshot.png"')  
    table.insert(body_parts, "Content-Type: image/png")  
    table.insert(body_parts, "")  
    table.insert(body_parts, image_data)  
    table.insert(body_parts, "--" .. boundary .. "--")  
      
    -- FIX: Append the final CRLF required by multipart/form-data specification
    local body = table.concat(body_parts, "\r\n") .. "\r\n"
      
    local response_body = {}  
    local result, status = http.request{  
        url = "https://koreader-plugin-bot-server.deno.dev/send_screenshot",  
        method = "POST",  
        headers = {  
            ["Content-Type"] = "multipart/form-data; boundary=" .. boundary,  
            ["Content-Length"] = tostring(#body),  
        },  
        source = ltn12.source.string(body),  
        sink = ltn12.sink.table(response_body),  
    }
    if result and status == 200 then
        UIManager:show(InfoMessage:new {
            text = _("Screenshot sent successfully!"),
            timeout = 3,
        })
    else
        UIManager:show(InfoMessage:new {
            text = _("Failed to send screenshot. Please check your connection"),
            timeout= 4,
        })
    end
    

end  
  
return sendScreenshotToBot