local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Notification = require("ui/widget/notification")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local logger = require("logger")
local _ = require("gettext")

local sendHighlightToBot = require("send_highlight")
local saveAndSendHighlightToBot = require("save_send_highlight")


local TelegramHighlights = WidgetContainer:new{
    name = "telegramhighlights",
    BOT_SERVER_URL = "https://koreader-plugin-bot-server.deno.dev/highlight",
    verification_code = ""
}

function TelegramHighlights:init()
    self.settings = G_reader_settings:readSetting("telegramhighlights") or {}
    self.verification_code = self.settings.verification_code or ""
    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end
    if self.ui and self.ui.highlight then
        self:extendHighlightMenu()
    elseif self.ui then
        if self.ui.registerPostInitCallback then
            self.ui:registerPostInitCallback(function()
                if self.ui.highlight then
                    self:extendHighlightMenu()
                end
            end)
        end
    end
end

function TelegramHighlights:extendHighlightMenu()
    if not self.ui or not self.ui.highlight then return end
    self.ui.highlight:addToHighlightDialog("13_send_to_bot", function(this)
        logger.info(this.selected_link)
        local is_existing_highlight = this.selected_link and this.selected_link.note
        local has_selected_text = this.selected_text and this.selected_text.text and this.selected_text.text ~= ""
        return {
            text = _("Send to Bot"),
            enabled = (this.hold_pos ~= nil and has_selected_text) or is_existing_highlight,
            callback = function()
                UIManager:scheduleIn(0, function()
                    sendHighlightToBot(self, this)
                end)
            end,
        }
    end)
    self.ui.highlight:addToHighlightDialog("14_save_and_send_to_bot", function(this)
        return {
            text = _("Save Highlight and Send to Bot"),
            enabled = this.hold_pos ~= nil and this.selected_text ~= nil and this.selected_text.text ~= "",
            callback = function()
                UIManager:scheduleIn(0, function()
                    saveAndSendHighlightToBot(self,this)
                end)
            end,
        }
    end)
end


function TelegramHighlights:addToMainMenu(menu_items)
    menu_items.telegramhighlights = {
        text = _("Telegram Highlights"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Set verification code"),
                keep_menu_open = true,
                callback = function()
                    local password_dialog
                    password_dialog = InputDialog:new{
                        title = _("Telegram Bot Verification Code"),
                        input = self.verification_code,
                        description = _("Enter the verification code you received from @bookshotsbot\n(Capitalization doesn't matter)"),
                        buttons = {{
                            {
                                text = _("Cancel"),
                                id = "close",
                                callback = function()
                                    UIManager:close(password_dialog)
                                end,
                            },
                            {
                                text = _("Save"),
                                callback = function()
                                    self.verification_code = password_dialog:getInputText()
                                    self.settings.verification_code = self.verification_code
                                    G_reader_settings:saveSetting("telegramhighlights", self.settings)
                                    UIManager:close(password_dialog)
                                    UIManager:show(Notification:new{
                                        text = _("Verification code saved."),
                                        timeout = 2,
                                    })
                                end,
                            },
                        }},
                    }
                    UIManager:show(password_dialog)
                    password_dialog:onShowKeyboard()
                end,
            },
            {
                text = _("About Telegram Highlights"),
                keep_menu_open = true,
                callback = function()
                    UIManager:show(InfoMessage:new{
                        text = _("Telegram Highlights allows you to send book highlights to a Telegram bot.\n\nTo use this plugin:\n1. Start a chat with @bookshotsbot on Telegram\n2. Get your verification code\n3. Enter the code in the plugin settings\n4. Select text in a book and use 'Send to Bot' from the highlight menu\n\nNote: Capitalization of the verification code doesn't matter."),
                    })
                end,
            },
        },
    }
end

return TelegramHighlights
