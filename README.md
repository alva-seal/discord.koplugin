# Telegram Highlights Plugin for KOReader

Send book highlights and screenshots from KOReader to a Telegram bot [@bookshotsbot](https://t.me/bookshotsbot) with ease. Select text or use existing highlights, then send or save-and-send to the bot.

## Features

- Send selected text or existing highlights to @bookshotsbot.
- **Send to Bot**: Sends text with image quote.
- **Save & Send**: Saves the highlight and sends image quote.
- **Upload all your bookmarks of a book to cloud**
  - Bulk Send all your bookmarks at once
  - Delete duplicates on the miniapp with one click
  - Send bookmarks individually
- **Auto turn on and turn off wifi after sending (might not work on android based e-readers)**
  - Toggle this feature in the plugins setting page
- **Send Screenshots to Bot**

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
4. **How to Bulk Send your Bookmarks**
   - Open the Book that has the bookmarks you need
   - Goto the main menu or the bookmark icon
   - Bookmarks
   - Click the menu icon on the top left
   - Click Send all to Bot
5. **How to Send individual Bookmarks**
   - Navigate to the bookmarks page
   - Long press the bookmark you want to send
   - Then click the send to bot button
6. **Send Screenshots to bot**
   - Swipe diagonally on your kindle
   - On the dialog, click send to bot
7. **Customize Quote Images**
   - Goto miniapp, press on customize button on image quote
   - Launch the miniapp by pressing the Highlights button, then press the image icon the the quote you want to customize
   - You can choose colors, Unsplash presets, or search any image from Unsplash that you want to use as a background image

## Highlight examples

- Raw highlight from bot

  - ![Alt text](./images/lao.png)

- Customized with in the miniapp

  - ![Alt text](./images/lao-custom.png)

## About the Bot

- The bot is hosted on Deno Deploy and uses deno key value store to save and retrieve user ids and preferences

---

For feature requests or any problems you can create issues or message me on Telegram [@mikxyas](https://t.me/mikxyas)
