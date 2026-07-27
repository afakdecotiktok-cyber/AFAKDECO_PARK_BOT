import os
import sqlite3
import logging
import threading
import asyncio
from flask import Flask

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, InputMediaPhoto, InputMediaVideo
from telegram.ext import (
    Application,
    CommandHandler,
    MessageHandler,
    CallbackQueryHandler,
    filters,
    ContextTypes,
)

# --- Flask app for Render "always on" pinging ---
web_app = Flask(__name__)

@web_app.route('/')
def home():
    return "Bot is running."

# --- Configuration ---
BOT_TOKEN = os.environ["BOT_TOKEN"]
ADMIN_GROUP_ID = int(os.environ["ADMIN_GROUP_ID"])

# --- Vehicle list ---
VEHICLES = ["F01", "F02", "H01"] + \
           [f"M{i:02d}" for i in range(1, 32)] + \
           ["LOGAN"]

# --- Database setup ---
DB_NAME = "drivers.db"

def init_db():
    conn = sqlite3.connect(DB_NAME)
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS drivers (
                    user_id INTEGER PRIMARY KEY,
                    name TEXT,
                    vehicle TEXT,
                    state TEXT)''')
    conn.commit()
    conn.close()

def get_driver(user_id: int) -> dict | None:
    conn = sqlite3.connect(DB_NAME)
    c = conn.cursor()
    c.execute("SELECT name, vehicle, state FROM drivers WHERE user_id=?", (user_id,))
    row = c.fetchone()
    conn.close()
    if row:
        return {"name": row[0], "vehicle": row[1], "state": row[2]}
    return None

def set_driver(user_id: int, name: str = None, vehicle: str = None, state: str = None):
    conn = sqlite3.connect(DB_NAME)
    c = conn.cursor()
    driver = get_driver(user_id)
    if driver:
        fields = []
        values = []
        if name is not None:
            fields.append("name=?")
            values.append(name)
        if vehicle is not None:
            fields.append("vehicle=?")
            values.append(vehicle)
        if state is not None:
            fields.append("state=?")
            values.append(state)
        if fields:
            c.execute(f"UPDATE drivers SET {', '.join(fields)} WHERE user_id=?",
                      tuple(values) + (user_id,))
    else:
        c.execute("INSERT INTO drivers (user_id, name, vehicle, state) VALUES (?,?,?,?)",
                  (user_id, name or "", vehicle or "", state or "name_entry"))
    conn.commit()
    conn.close()

def vehicle_keyboard() -> InlineKeyboardMarkup:
    buttons = [InlineKeyboardButton(v, callback_data=f"veh_{v}") for v in VEHICLES]
    rows = [buttons[i:i+5] for i in range(0, len(buttons), 5)]
    return InlineKeyboardMarkup(rows)

# --- Media group handling ---
media_groups = {}

async def forward_media_group(context: ContextTypes.DEFAULT_TYPE, group_id: str):
    data = media_groups.pop(group_id, None)
    if not data:
        return
    msgs = data["messages"]
    media_list = []
    user_id = msgs[0].from_user.id
    driver = get_driver(user_id)
    header = ""
    if driver and driver["name"] and driver["vehicle"]:
        header = f"Driver: {driver['name']}\nVehicle: {driver['vehicle']}\n"
        first_caption = msgs[0].caption or ""
        if first_caption:
            header += f"Problem: {first_caption}"
        else:
            header += "Problem: (see media)"
    else:
        header = "Driver info missing – please complete your profile with /start"

    for i, msg in enumerate(msgs):
        if msg.photo:
            file_id = msg.photo[-1].file_id
            if i == 0:
                media_list.append(InputMediaPhoto(media=file_id, caption=header))
            else:
                media_list.append(InputMediaPhoto(media=file_id))
        elif msg.video:
            file_id = msg.video.file_id
            if i == 0:
                media_list.append(InputMediaVideo(media=file_id, caption=header))
            else:
                media_list.append(InputMediaVideo(media=file_id))
    if media_list:
        await context.bot.send_media_group(chat_id=ADMIN_GROUP_ID, media=media_list)

# --- Handlers ---
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    driver = get_driver(user_id)
    if driver and driver["name"] and driver["vehicle"]:
        await update.message.reply_text(
            f"Welcome back, {driver['name']}!\nYour vehicle: {driver['vehicle']}\n"
            "Send me the problem description (text, photo, video) – I'll forward it to the workshop."
        )
    else:
        set_driver(user_id, state="name_entry")
        await update.message.reply_text("Hello! I'm the problem reporter bot.\nPlease enter your full name:")

async def change_name(update: Update, context: ContextTypes.DEFAULT_TYPE):
    set_driver(update.effective_user.id, state="name_entry")
    await update.message.reply_text("Send me your new name:")

async def change_vehicle(update: Update, context: ContextTypes.DEFAULT_TYPE):
    set_driver(update.effective_user.id, state="vehicle_selection")
    await update.message.reply_text("Choose your vehicle:", reply_markup=vehicle_keyboard())

async def my_info(update: Update, context: ContextTypes.DEFAULT_TYPE):
    driver = get_driver(update.effective_user.id)
    if driver and driver["name"] and driver["vehicle"]:
        await update.message.reply_text(f"Name: {driver['name']}\nVehicle: {driver['vehicle']}")
    else:
        await update.message.reply_text("Your profile is incomplete. Use /start to set it up.")

async def handle_text(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    text = update.message.text
    driver = get_driver(user_id)
    state = driver["state"] if driver else "name_entry"

    if state == "name_entry":
        set_driver(user_id, name=text, state="vehicle_selection")
        await update.message.reply_text(f"Name saved: {text}\nNow select your vehicle:", reply_markup=vehicle_keyboard())
        return

    if state == "vehicle_selection":
        await update.message.reply_text("Please use the buttons to choose your vehicle.")
        return

    if driver and driver["name"] and driver["vehicle"]:
        report_text = f"Driver: {driver['name']}\nVehicle: {driver['vehicle']}\nProblem: {text}"
        await context.bot.send_message(chat_id=ADMIN_GROUP_ID, text=report_text)
    else:
        await update.message.reply_text("Your profile is incomplete. Please /start first.")

async def handle_media(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    driver = get_driver(user_id)
    if not driver or not driver["name"] or not driver["vehicle"]:
        await update.message.reply_text("Your profile is incomplete. Please /start first.")
        return

    header = f"Driver: {driver['name']}\nVehicle: {driver['vehicle']}\n"
    caption = update.message.caption or ""
    if caption:
        header += f"Problem: {caption}"
    else:
        header += "Problem: (see media)"

    if update.message.photo:
        file_id = update.message.photo[-1].file_id
        await context.bot.send_photo(chat_id=ADMIN_GROUP_ID, photo=file_id, caption=header)
    elif update.message.video:
        file_id = update.message.video.file_id
        await context.bot.send_video(chat_id=ADMIN_GROUP_ID, video=file_id, caption=header)

async def handle_album_msg(update: Update, context: ContextTypes.DEFAULT_TYPE):
    msg = update.message
    group_id = msg.media_group_id
    if not group_id:
        await handle_media(update, context)
        return

    if group_id not in media_groups:
        media_groups[group_id] = {"messages": [msg], "timer": None}
    else:
        media_groups[group_id]["messages"].append(msg)

    if media_groups[group_id]["timer"]:
        media_groups[group_id]["timer"].schedule_removal()
    job = context.job_queue.run_once(
        lambda ctx: forward_media_group(ctx, group_id),
        when=1,
        chat_id=update.effective_chat.id,
        name=f"album_{group_id}"
    )
    media_groups[group_id]["timer"] = job

async def handle_vehicle_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    vehicle = query.data.split("_")[1]
    user_id = query.from_user.id
    set_driver(user_id, vehicle=vehicle, state="idle")
    await query.edit_message_text(
        f"Vehicle set to {vehicle}.\nYour profile is complete. You can now send problem reports.\n"
        "Use /changevehicle or /changename to modify later."
    )

async def error_handler(update: object, context: ContextTypes.DEFAULT_TYPE) -> None:
    logging.error(msg="Exception while handling an update:", exc_info=context.error)

def main():
    logging.basicConfig(level=logging.INFO)
    init_db()

    # Build the bot application
    app = Application.builder().token(BOT_TOKEN).build()

    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("changename", change_name))
    app.add_handler(CommandHandler("changevehicle", change_vehicle))
    app.add_handler(CommandHandler("myinfo", my_info))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text))
    app.add_handler(MessageHandler(
        (filters.PHOTO | filters.VIDEO) & ~filters.CAPTION & ~filters.COMMAND,
        handle_media))
    app.add_handler(MessageHandler(
        filters.PHOTO | filters.VIDEO,
        handle_album_msg,
        block=False))
    app.add_handler(CallbackQueryHandler(handle_vehicle_callback, pattern="^veh_"))
    app.add_error_handler(error_handler)

    print("Bot polling started...")
    # Run the bot (this call blocks forever)
    app.run_polling(stop_signals=[])

if __name__ == "__main__":
    # Start Flask in a daemon thread so the main thread can run the bot
    flask_thread = threading.Thread(
        target=lambda: web_app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 5000))),
        daemon=True
    )
    flask_thread.start()
    print("Flask server started on port", os.environ.get("PORT", 5000))

    # Run the bot in the main thread
    main()
