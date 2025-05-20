# Telegram Highlights Plugin for KOReader

Send book highlights from KOReader to a Telegram bot [@bookshotsbot](https://t.me/bookshotsbot) with ease. Select text or use existing highlights, then send or save-and-send to the bot.

## Features

- Send selected text or existing highlights to @bookshotsbot.
- **Send to Bot**: Sends text and clears selection.
- **Save & Send**: Saves highlight, sends to bot, keeps selection.

## What You Need

- KOReader on your e-reader.
- Telegram account on your phone or pc
- Wi-Fi for sending highlights.

## Install

1. Download the plugin:
   - [Click Here](https://github.com/0xmiki/telegramhighlights.koplugin/archive/refs/heads/main.zip) to download the zip of this repo
2. Unzip the folder, open it and then copy the `telegramhighlights.koplugin` folder to KOReader’s plugins folder:
3. Restart KOReader. Look for "Telegram Highlights" in the last page of the "Tools" menu.

## How to Use

1. **Get a Code**:
   - Chat with @bookshotsbot on Telegram to get a verification code.
   - In KOReader, go `Tools > Telegram Highlights > Set verification code`, enter it, and save.
2. **Send Highlights**:
   - **New Text**: Select text, open highlight menu, pick "Send to Bot" or "Save Highlight and Send to Bot".
   - **Existing Highlight**: Tap a highlight, hit the three dots, choose "Send to Bot" or "Save & Send".
3. **Check Telegram**: Highlights appear in your @bookshotsbot chat with book title and author.

## Highlight examples

![Alt text](./images/david.jpg)

![Alt text](./images/lao.jpg)

## About the Bot

- The bot is hosted on Deno Deploy and uses deno key value store to save and retrieve user ids and preferences

## Todo

- Add cool customizations for the user
- Gracefully handle languages like Arabic that are not supported by og-image

---

more updates and improvements coming. you can join my telegram channel to stay updated [@willtocode](https://t.me/willtocode)
