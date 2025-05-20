import {
  Bot,
  ImageResponse,
  webhookCallback,
  InlineKeyboard,
  InputFile,
} from "./deps.ts";
import React from "https://esm.sh/react@18.2.0";
import { h } from "https://esm.sh/preact@10.19.2";
import { franc } from "npm:franc";
// Environment Variables (ensure these are set in Deno Deploy)
const BOT_TOKEN = Deno.env.get("BOT_TOKEN");
const BOT_SECRET = Deno.env.get("BOT_SECRET");

if (!BOT_TOKEN) throw new Error("BOT_TOKEN is required");
if (!BOT_SECRET) throw new Error("BOT_SECRET is required for webhook");

const bot = new Bot(BOT_TOKEN);
const kv = await Deno.openKv();

// User data helpers
type Theme = "dark" | "light";
type UserRecord = { key: string; theme: Theme };

const usersNS = ["users"];
const keysNS = ["user_keys"];
const donationsNS = ["donations"];

// Donation record type
type DonationRecord = {
  userId: number;
  stars: number;
  timestamp: number;
  paymentChargeId: string;
  refunded: boolean;
};

async function getUserRecord(userId: number): Promise<UserRecord | null> {
  const entry = await kv.get<UserRecord>([...usersNS, userId]);
  return entry.value ?? null;
}

async function getUserIdByKey(key: string): Promise<number | null> {
  const entry = await kv.get<number>([...keysNS, key]);
  return entry.value ?? null;
}

async function setUserRecord(userId: number, record: UserRecord) {
  const existing = await getUserRecord(userId);
  if (existing) await kv.delete([...keysNS, existing.key]);
  await kv.set([...usersNS, userId], record);
  await kv.set([...keysNS, record.key], userId);
}

async function storeDonation(
  userId: number,
  stars: number,
  paymentChargeId: string
) {
  const donation: DonationRecord = {
    userId,
    stars,
    timestamp: Date.now(),
    refunded: false,
    paymentChargeId,
  };
  // The key includes userId and timestamp, which is good for retrieval.
  await kv.set([...donationsNS, userId, donation.timestamp], donation);
}

function generateCode(): string {
  return Math.random().toString(36).substring(2, 10).toUpperCase();
}
// Command: /start
bot.command("start", async (ctx) => {
  const userId = ctx.from?.id;
  if (!userId) return;

  let user = await getUserRecord(userId);
  if (!user) {
    const newKey = generateCode();
    user = { key: newKey, theme: "dark" };
    await setUserRecord(userId, user);
  }

  const helpText = `Welcome! Your verification key is:

\` ${user.key}\`

 /newkey get a new key
 /key view your current key
 /changetheme change the image style
 /help full list of commands
 /donate Donate stars 🤗✨🫶🏻😗

made with ❤️ and 👻 by @willtocode
`;
  await ctx.reply(helpText, { parse_mode: "Markdown" });
});

// // Command: /donate
bot.command("donate", async (ctx) => {
  const userId = ctx.from?.id;
  if (!userId) return ctx.reply("Cannot identify user.");

  // Create inline keyboard with predefined amounts and custom value
  const keyboard = new InlineKeyboard()
    .text("9 ⭐", "donate_9")
    .text("33 ⭐", "donate_33")
    .row()
    .text("69 ⭐", "donate_69")
    .text("333 ⭐", "donate_333")
    .row()
    .text("777 ⭐", "donate_777")
    .text("Custom Value", "donate_custom");

  await ctx.reply(
    "Support the bot with a donation! Choose an amount or select Custom Value to enter your own.",
    { reply_markup: keyboard }
  );
});

// Command: /newkey
bot.command("newkey", async (ctx) => {
  const userId = ctx.from?.id;
  if (!userId) return ctx.reply("Cannot identify user.");

  const old = await getUserRecord(userId);
  const newKey = generateCode();
  const theme = old?.theme ?? "dark";
  await setUserRecord(userId, { key: newKey, theme });

  await ctx.reply(`Your new key is:\n\`${newKey}\``);
});

// Command: /key
bot.command("key", async (ctx) => {
  const userId = ctx.from?.id;
  if (!userId) return ctx.reply("Cannot identify user.");

  const user = await getUserRecord(userId);
  if (!user) return ctx.reply("No key found. Use /newkey to generate one.");

  await ctx.reply(`Your current key is:\n\`${user.key}\``);
});

// Command: /changetheme
bot.command("changetheme", async (ctx) => {
  const userId = ctx.from?.id;
  if (!userId) return ctx.reply("Cannot identify user.");

  const user = await getUserRecord(userId);
  if (!user) return ctx.reply("No user record. Use /start first.");

  // Toggle the theme
  const newTheme: Theme = user.theme === "dark" ? "light" : "dark";
  await setUserRecord(userId, { key: user.key, theme: newTheme });

  // Create button with text showing the *opposite* theme to switch to
  const nextTheme: Theme = newTheme === "dark" ? "light" : "dark";
  const button = new InlineKeyboard().text(
    `Switch to ${nextTheme} mode`,
    `changetheme_${nextTheme}`
  );

  await ctx.reply(`Theme changed to *${newTheme}* mode.`, {
    parse_mode: "Markdown",
    reply_markup: button,
  });
});

bot.command("help", async (ctx) => {
  const userId = ctx.from?.id;
  if (!userId) return;
  const user = await getUserRecord(userId);
  const key = user?.key || "(none)";
  const text = `*How to use this bot:*

1. Install the KOReader Telegram plugin. [Download Zip](https://github.com/0xmiki/telegramhighlights.koplugin/archive/refs/heads/main.zip)
2. Go into the extracted folder
3. Grab the telegramhighlights.koplugin folder and place it in the KOReader plugin directory
4. Then Go to koreader -> menu -> 🛠️ -> Last page -> Telegram Highlights -> Set Verification Code -> enter your verification key: \`${key}\`
5. Thats it

*Available commands:*

/newkey - Generate a new key
/key - Show your current key
/changetheme - Change image style
/help - Show this help message
/donate - Donate stars 🤗✨🫶🏻😗
/refund - If you change your mind 🥹❤️‍🩹
/donations - List donations

for any further questions you can hmu @mikxyas
`;
  await ctx.reply(text, { parse_mode: "Markdown" });
});

bot.command("donations", async (ctx) => {
  const userId = ctx.from?.id;
  if (!userId) return ctx.reply("Cannot identify user.");

  try {
    const donations: DonationRecord[] = [];
    for await (const entry of kv.list<DonationRecord>({
      prefix: [...donationsNS, userId],
    })) {
      if (entry.value) {
        donations.push(entry.value);
      }
    }

    if (donations.length === 0) {
      return ctx.reply(
        "You haven't made any donations yet. Support the bot with `/donate`!",
        { parse_mode: "Markdown" }
      );
    }

    donations.sort((a, b) => b.timestamp - a.timestamp);

    // Format donation history, indicating refunded status
    const donationText = donations
      .map((d) => {
        const date = new Date(d.timestamp).toLocaleString("en-US", {
          dateStyle: "medium",
          timeStyle: "short",
        });
        // ✅ Add refunded status to the display text
        const refundedStatus = d.refunded ? " (Refunded)" : "";
        return `- ${date}: ${d.stars} ⭐ (ID: ${d.paymentChargeId.slice(
          0,
          8
        )}...)${refundedStatus}`;
      })
      .join("\n");

    const message = `Your donation history:\n\n${donationText}\n\nThank you for supporting the bot! 🤗✨🫶🏻😗  Donate more with /donate or contact [@mikxyas](https://t.me/mikxyas) for support.`;

    await ctx.reply(message, { parse_mode: "Markdown" });
  } catch (error) {
    console.error("Error fetching donations:", error);
    await ctx.reply(
      "Sorry, there was an error retrieving your donation history. Please contact [@mikxyas](https://t.me/mikxyas).",
      { parse_mode: "Markdown" }
    );
  }
});

bot.command("refund", async (ctx) => {
  const userId = ctx.from?.id;
  if (!userId) return ctx.reply("Cannot identify user.");

  try {
    // Retrieve all non-refunded donation records for the user
    const donations: DonationRecord[] = [];
    for await (const entry of kv.list<DonationRecord>({
      prefix: [...donationsNS, userId],
    })) {
      if (entry.value && !entry.value.refunded) {
        donations.push(entry.value);
      }
    }

    // Handle case of no refundable donations
    if (donations.length === 0) {
      return ctx.reply(
        "You have no refundable donations. View your donation history with `/donations` or donate with `/donate`.",
        { parse_mode: "Markdown" }
      );
    }

    // Sort donations by timestamp (newest first)
    donations.sort((a, b) => b.timestamp - a.timestamp);

    // Create inline keyboard with donation options
    const keyboard = new InlineKeyboard();
    donations.forEach((d) => {
      const date = new Date(d.timestamp).toLocaleString("en-US", {
        dateStyle: "short",
      });
      keyboard
        .text(`${d.stars} ⭐ on ${date}`, `refund_${userId}_${d.timestamp}`)
        .row();
    });

    await ctx.reply("Select a donation to refund:", { reply_markup: keyboard });
  } catch (error) {
    console.error("Error fetching donations for refund:", error);
    await ctx.reply(
      "Sorry, there was an error retrieving your donations. Please contact [@mikxyas](https://t.me/mikxyas).",
      { parse_mode: "Markdown" }
    );
  }
});

// Handle pre-checkout query for Stars payments
bot.on("pre_checkout_query", async (ctx) => {
  const query = ctx.preCheckoutQuery;
  if (!query.invoice_payload.startsWith("donation:")) {
    return ctx.answerPreCheckoutQuery(false, "Invalid invoice type.");
  }

  // Verify the payload format and user
  const [_, userId, stars, timestamp] = query.invoice_payload.split(":");
  if (parseInt(userId) !== query.from.id) {
    return ctx.answerPreCheckoutQuery(false, "User ID mismatch.");
  }

  // Confirm the checkout within 10 seconds
  try {
    await ctx.answerPreCheckoutQuery(true);
  } catch (error) {
    console.error("Error answering pre-checkout query:", error);
    await ctx.answerPreCheckoutQuery(false, "Internal error.");
  }
});

// Handle successful payment
bot.on("message:successful_payment", async (ctx) => {
  const payment = ctx.message?.successful_payment;
  if (!payment || !payment.invoice_payload.startsWith("donation:")) return;

  const userId = ctx.from?.id;
  if (!userId) return;

  const [_, __, stars, timestamp] = payment.invoice_payload.split(":");
  const starsAmount = parseInt(stars);

  // Store the donation
  try {
    await storeDonation(
      userId,
      starsAmount,
      payment.telegram_payment_charge_id
    );
    await ctx.reply(
      `Thank you for your generous donation of ${starsAmount} Stars! Your support keeps this bot running! 🌟`,
      { parse_mode: "Markdown" }
    );
  } catch (error) {
    console.error("Error processing payment:", error);
    await ctx.reply(
      "Payment received, but there was an error saving the donation. Please contact support."
    );
  }
});

bot.on("message:text", async (ctx) => {
  const userId = ctx.from?.id;
  if (!userId) return;

  // Check if the message is a reply to a custom donation prompt
  const promptMessageId = (
    await kv.get<number>(["custom_donation_prompt", userId])
  ).value;
  if (
    !promptMessageId ||
    ctx.message?.reply_to_message?.message_id !== promptMessageId
  )
    return;

  const starsText = ctx.message.text.trim();
  const stars = parseInt(starsText, 10);

  if (isNaN(stars) || stars < 1) {
    await ctx.reply("Please enter a valid number of Stars (e.g., 50).", {
      reply_markup: { force_reply: true },
    });
    return;
  }

  // Clear the prompt to prevent re-processing
  await kv.delete(["custom_donation_prompt", userId]);

  // Send invoice for custom amount
  try {
    let title = "Donation to the Bot";
    let description = `Thank you for supporting the bot with ${stars} Stars! 🤗✨🫶🏻😗`;
    let payload = `donation:${userId}:${stars}:${Date.now()}`;
    let currency = "XTR";
    let prices = [{ label: "Donation", amount: stars }];
    let start_parameter = "donation";
    await ctx.replyWithInvoice(
      title,
      description,
      payload,
      currency,
      prices,
      start_parameter
    );
    // await ctx.reply("Invoice sent");
  } catch (error) {
    console.error("Error sending invoice:", error);
    await ctx.reply("Sorry, there was an error creating the donation invoice.");
  }
});

// Handler for inline button presses
bot.on("callback_query:data", async (ctx) => {
  const data = ctx.callbackQuery.data;
  const userId = ctx.from?.id;

  if (data.startsWith("changetheme_")) {
    const userId = ctx.from?.id;
    if (!userId) {
      await ctx.answerCallbackQuery({ text: "Cannot identify user." });
      return;
    }

    const newTheme = data.split("_")[1] as Theme;
    const user = await getUserRecord(userId);
    if (!user) {
      await ctx.answerCallbackQuery({ text: "No user record found." });
      return;
    }

    // Update the theme
    await setUserRecord(userId, { key: user.key, theme: newTheme });

    // Create new button with text showing the *opposite* theme
    const nextTheme: Theme = newTheme === "dark" ? "light" : "dark";
    const button = new InlineKeyboard().text(
      `Switch to ${nextTheme} mode`,
      `changetheme_${nextTheme}`
    );

    // Update the message with new text and persistent button
    await ctx.editMessageText(`Theme switched to *${newTheme}* mode.`, {
      parse_mode: "Markdown",
      reply_markup: button,
    });

    await ctx.answerCallbackQuery({ text: `Switched to ${newTheme} mode!` });
  }

  if (data.startsWith("donate_")) {
    const action = data.split("_")[1];

    if (action === "custom") {
      // Prompt for custom amount
      const message = await ctx.reply(
        "Please enter the number of Stars you want to donate (e.g., 50).",
        { reply_markup: { force_reply: true } }
      );
      // Store the prompt message ID to track the conversation
      await kv.set(["custom_donation_prompt", userId], message.message_id);
      await ctx.answerCallbackQuery();
      return;
    }

    // Handle predefined amounts
    const stars = parseInt(action);
    if (!stars || isNaN(stars)) {
      await ctx.answerCallbackQuery({ text: "Invalid donation amount." });
      return;
    }

    try {
      let title = "Donation to the Bot";
      let description = `Thank you for supporting the bot with ${stars} Stars! 🤗✨🫶🏻😗`;
      let payload = `donation:${userId}:${stars}:${Date.now()}`;
      let currency = "XTR";
      let prices = [{ label: "Donation", amount: stars }];
      let start_parameter = "donation";
      await ctx.replyWithInvoice(
        title,
        description,
        payload,
        currency,
        prices,
        start_parameter
      );
    } catch (error) {
      console.error("Error sending invoice:", error);
      await ctx.answerCallbackQuery({ text: "Error creating invoice." });
    }
  }

  if (data.startsWith("refund_")) {
    const BOT_OWNER_ID = Deno.env.get("BOT_OWNER_ID");
    const [, targetUserId, timestamp] = data
      .split("_")
      .map((v, i) => (i < 2 ? parseInt(v) : v));
    if (!targetUserId || !timestamp) {
      await ctx.answerCallbackQuery({ text: "Invalid refund request." });
      return;
    }

    // Restrict refunds to the original payer or bot owner
    if (
      userId !== targetUserId &&
      (!BOT_OWNER_ID || userId !== parseInt(BOT_OWNER_ID))
    ) {
      await ctx.answerCallbackQuery({
        text: "You are not authorized to refund this donation.",
      });
      return;
    }

    try {
      // Retrieve the donation record
      const donationEntry = await kv.get<DonationRecord>([
        ...donationsNS,
        targetUserId,
        parseInt(timestamp),
      ]);
      const donation = donationEntry.value;
      if (!donation || donation.refunded) {
        await ctx.answerCallbackQuery({
          text: "Donation not found or already refunded.",
        });
        return;
      }

      // Process the refund
      let user_id = targetUserId;
      let telegram_payment_charge_id = donation.paymentChargeId;
      await ctx.api.refundStarPayment(user_id, telegram_payment_charge_id);

      // Mark the donation as refunded
      const updatedDonation: DonationRecord = { ...donation, refunded: true };
      await kv.set(
        [...donationsNS, targetUserId, parseInt(timestamp)],
        updatedDonation
      );

      // Notify the user
      await ctx.reply(
        `Successfully refunded ${donation.stars} ⭐ for donation on ${new Date(
          donation.timestamp
        ).toLocaleString("en-US", { dateStyle: "short" })}.`,
        { parse_mode: "Markdown" }
      );

      // Notify bot owner if the refund was initiated by the payer
      if (BOT_OWNER_ID && userId === targetUserId) {
        await ctx.api.sendMessage(
          parseInt(BOT_OWNER_ID),
          `User ${userId} refunded ${
            donation.stars
          } ⭐ for donation on ${new Date(donation.timestamp).toLocaleString(
            "en-US",
            { dateStyle: "short" }
          )} (ID: ${donation.paymentChargeId.slice(0, 8)}...).`
        );
      }

      await ctx.answerCallbackQuery({ text: "Refund processed successfully!" });
    } catch (error) {
      console.error("Error processing refund:", error);
      await ctx.answerCallbackQuery({
        text: "Failed to process refund. Please contact @mikxyas.",
      });
      await ctx.reply(
        "There was an error processing your refund. Please contact [@mikxyas](https://t.me/mikxyas).",
        { parse_mode: "Markdown" }
      );
    }
  }
});

const escapeHtml = (unsafe: string | null | undefined): string => {
  if (unsafe === null || unsafe === undefined) return "";
  return (
    unsafe
      .replace(/[\u2018\u2019]/g, "'") // Curly single quotes to straight
      .replace(/[\u201C\u201D]/g, '"') // Curly double quotes to straight
      .replace(/[\u2013\u2014]/g, "-") // En-dash and em-dash to hyphen
      .replace(/…/g, "...") // Ellipsis to three dots
      // Remove or escape potentially dangerous characters (e.g., HTML tags)
      .replace(/[<>]/g, "") // Remove < and > to prevent HTML injection
      .replace(/&/g, "&amp;") // Escape ampersand (for safety, though not rendered as HTML)
      .trim()
  );
};

// --- Configuration and Function for Dynamic Layout ---
interface LayoutConfig {
  initialWidth: number;
  initialHeight: number;
  minFontSize: number;
  maxFontSize: number;
  charsForMaxFont: number;
  charsForMinFont: number;
  padding: number;
  baseTextLengthForHeightScaling: number;
  heightScaleFactor: number;
  baseTextLengthForWidthScaling: number;
  widthScaleThreshold: number;
  widthScaleFactor: number;
  maxWidth: number;
  maxHeight: number;
}

interface LayoutOutput {
  cardWidth: number;
  cardHeight: number;
  fontSize: number;
}

const DEFAULT_LAYOUT_CONFIG: LayoutConfig = {
  initialWidth: 603,
  initialHeight: 603,
  minFontSize: 28,
  maxFontSize: 55,
  charsForMaxFont: 150,
  charsForMinFont: 888,
  padding: 33,
  baseTextLengthForHeightScaling: 90,
  heightScaleFactor: 88,
  baseTextLengthForWidthScaling: 290,
  widthScaleThreshold: 290,
  widthScaleFactor: 33,
  maxWidth: 1500,
  maxHeight: 2000,
};

function calculateDynamicLayout(
  text: string,
  config: LayoutConfig
): LayoutOutput {
  const length = text?.length || 0;

  let fontSize: number;
  if (length <= config.charsForMaxFont) {
    fontSize = config.maxFontSize;
  } else if (length >= config.charsForMinFont) {
    fontSize = config.minFontSize;
  } else {
    const fontRange = config.maxFontSize - config.minFontSize;
    const charRange = config.charsForMinFont - config.charsForMaxFont;
    fontSize =
      config.maxFontSize -
      ((length - config.charsForMaxFont) / charRange) * fontRange;
    fontSize = Math.max(
      config.minFontSize,
      Math.min(config.maxFontSize, Math.round(fontSize))
    );
  }

  let cardHeight = config.initialHeight;
  if (length > config.baseTextLengthForHeightScaling) {
    const extraHeight =
      Math.log(
        Math.max(1, length - config.baseTextLengthForHeightScaling + 1)
      ) * config.heightScaleFactor;
    cardHeight = Math.round(config.initialHeight + extraHeight);
  }

  let cardWidth = config.initialWidth;
  if (
    length >= config.widthScaleThreshold &&
    length > config.baseTextLengthForWidthScaling
  ) {
    const extraWidth =
      Math.log(Math.max(1, length - config.baseTextLengthForWidthScaling + 1)) *
      config.widthScaleFactor;
    cardWidth = Math.round(config.initialWidth + extraWidth);
  }

  cardWidth = Math.min(cardWidth, config.maxWidth);
  cardHeight = Math.min(cardHeight, config.maxHeight);

  // Ensure card dimensions are not smaller than initial ones if calculated values are smaller
  // (e.g. for very short text after some calculation, though current logic doesn't decrease)
  cardWidth = Math.max(cardWidth, config.initialWidth);
  cardHeight = Math.max(cardHeight, config.initialHeight);

  return { cardWidth, cardHeight, fontSize };
}

const handleUpdate = webhookCallback(bot, "std/http");

const THEME_COLORS = {
  dark: {
    background: "#0e0e0e", // Dark gray (original)
    text: "#ffffff", // White (original)
    metaText: "#b0b0b0", // Light gray (original)
    authorText: "#f7f4ef", // Off-white (original)
  },
  light: {
    background: "#ffffff", // White
    text: "#000000", // Black
    metaText: "#666666", // Medium gray for meta
    authorText: "#333333", // Dark gray for author
  },
};
function escapeMarkdownV2(text: string): string {
  return text.replace(/[_*[\]()~`>#+\-=|{}.!]/g, "\\$&");
}
Deno.serve(async (req) => {
  const url = new URL(req.url);

  // 1. Handle Telegram Webhook updates (remains the same)
  if (req.method === "POST" && url.searchParams.get("secret") === BOT_SECRET) {
    try {
      return await handleUpdate(req);
    } catch (err) {
      console.error("Error handling Telegram update:", err);
      return new Response("Webhook Error", { status: 500 });
    }
  }

  // 2. Handle Highlight endpoint from KOReader
  if (req.method === "POST" && url.pathname === "/highlight") {
    try {
      if (!req.body) {
        return new Response(JSON.stringify({ error: "Request body missing" }), {
          status: 400,
          headers: { "Content-Type": "application/json" },
        });
      }
      const { code, text, title, author /* cover */ } = await req.json();

      if (!code || !text || !title) {
        return new Response(
          JSON.stringify({
            error: "Missing required fields: code, text, title",
          }),
          {
            status: 400,
            headers: { "Content-Type": "application/json" },
          }
        );
      }

      const userId = await getUserIdByKey(code);
      if (!userId) {
        console.warn(
          `Invalid code received: ${code} from ${
            req.headers.get("user-agent") || "unknown"
          }`
        );
        return new Response(
          JSON.stringify({ error: "Invalid verification code" }),
          {
            status: 403,
            headers: { "Content-Type": "application/json" },
          }
        );
      }

      const user = await getUserRecord(userId);
      if (!user) {
        console.error(`User record not found for userId: ${userId}`);
        return new Response(
          JSON.stringify({ error: "User record not found" }),
          {
            status: 500,
            headers: { "Content-Type": "application/json" },
          }
        );
      }

      const safeText = escapeHtml(text);
      const safeAuthor = author ? escapeHtml(author) : null;
      const safeTitle = title ? escapeHtml(title) : null;

      // --- Use the dynamic layout function ---
      const { cardWidth, cardHeight, fontSize } = calculateDynamicLayout(
        safeText,
        DEFAULT_LAYOUT_CONFIG
      );

      const META_COLOR = "#b0b0b0"; // Lighter grey for author/title
      // console.log(text);
      const detectedLanguage = franc(safeText);
      const escapedText = escapeMarkdownV2(text);
      const escapedAuthor = author ? escapeMarkdownV2(author) : "";
      const escapedTitle = title ? escapeMarkdownV2(title) : "";

      const quoteMessage = `>${escapedText.split("\n").join("\n>")}

*${escapedAuthor}*
_${escapedTitle}_`;

      if (detectedLanguage === "arb") {
        console.log("Arabic text detected");
        await bot.api.sendMessage(userId, quoteMessage, {
          parse_mode: "MarkdownV2",
        });
        return new Response(JSON.stringify({ success: true }), {
          status: 200,
          headers: { "Content-Type": "application/json" },
        });
      }
      console.log(detectedLanguage);
      const colors = THEME_COLORS[user.theme];

      const ogImage = new ImageResponse(
        (
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              justifyContent: "space-between",
              alignItems: "flex-start",
              backgroundColor: colors.background,
              width: "100%",
              height: "100%",
              padding: `${DEFAULT_LAYOUT_CONFIG.padding}px`,
              color: colors.text,
              textAlign: "center",
              boxSizing: "border-box",
              letterSpacing: "-0.5px",
            }}
          >
            <div
              style={{
                display: "flex",
                justifyContent: "center",
                fontSize: `${fontSize}px`,
                lineHeight: 1.2,
                fontWeight: safeText.length >= 100 ? 400 : 500,
                fontFamily: "Lora",
                fontStyle: "normal",
                textAlign: "left",
                opacity: 0.94,
                width: "100%",
              }}
            >
              {safeText}
            </div>

            {(safeAuthor || safeTitle) && (
              <div
                style={{
                  display: "flex",
                  flexDirection: "column",
                  alignItems: "flex-start",
                  marginTop: `${fontSize * 0.5}px`,
                  color: colors.metaText,
                }}
              >
                {safeAuthor && (
                  <div
                    style={{
                      display: "flex",
                      fontSize: "28px",
                      fontWeight: 500,
                      color: colors.authorText,
                      letterSpacing: "0.5px",
                      textAlign: "left",
                      marginBottom: safeTitle ? "6px" : "0px",
                    }}
                  >
                    {safeAuthor}
                  </div>
                )}
                {safeTitle && (
                  <div
                    style={{
                      display: "flex",
                      textAlign: "left",
                      fontSize: "22px",
                      fontWeight: 400,
                      opacity: 0.9,
                      textTransform: "uppercase",
                    }}
                  >
                    {safeTitle}
                  </div>
                )}
              </div>
            )}
          </div>
        ),
        {
          width: cardWidth,
          height: cardHeight,
          embedFont: true,
          fonts: [
            {
              name: "Lora",
              data: await Deno.readFile("./fonts/lora/Lora-MediumItalic.ttf"),
              weight: 500,
              style: "italic",
            },
            {
              name: "Lora",
              data: await Deno.readFile("./fonts/lora/Lora-Regular.ttf"),
              weight: 400,
              style: "normal",
            },
            {
              name: "Lora",
              data: await Deno.readFile("./fonts/lora/Lora-Medium.ttf"),
              weight: 500,
              style: "normal",
            },
          ],
        }
      );

      if (!ogImage.body) {
        console.error("Error: ImageResponse body is null after creation");
        throw new Error("Failed to get image body stream");
      }

      const inputFile = new InputFile(ogImage.body, "highlight.png");
      await bot.api.sendPhoto(userId, inputFile);

      await bot.api.sendMessage(userId, quoteMessage, {
        parse_mode: "MarkdownV2",
      });
      console.log("Highlight Generated");
      return new Response(JSON.stringify({ success: true }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    } catch (error) {
      console.error("Error processing /highlight request:", error);
      return new Response(JSON.stringify({ error: "Internal server error" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }
  }
  return new Response("Not Found", { status: 404 });
});
