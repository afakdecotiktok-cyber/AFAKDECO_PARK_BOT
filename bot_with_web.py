import os
import sys
import sqlite3
import logging
import threading
import asyncio
from datetime import datetime
from io import BytesIO

from flask import Flask
from openpyxl import Workbook
from openpyxl.styles import Font

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, InputMediaPhoto, InputMediaVideo
from telegram.ext import (
    Application,
    CommandHandler,
    MessageHandler,
    CallbackQueryHandler,
    filters,
    ContextTypes,
)

# ----------------------------------------------------------------------
# Flask app – runs in a daemon thread so the main thread can run the bot
# ----------------------------------------------------------------------
web_app = Flask(__name__)

@web_app.route('/')
def home():
    return "Bot is running."

# ----------------------------------------------------------------------
# Configuration – must be set as environment variables on Render
# ----------------------------------------------------------------------
BOT_TOKEN = os.environ.get("BOT_TOKEN")
ADMIN_GROUP_ID_STR = os.environ.get("ADMIN_GROUP_ID")

if not BOT_TOKEN:
    sys.exit("FATAL: BOT_TOKEN environment variable not set.")
if not ADMIN_GROUP_ID_STR:
    sys.exit("FATAL: ADMIN_GROUP_ID environment variable not set.")
try:
    ADMIN_GROUP_ID = int(ADMIN_GROUP_ID_STR)
except ValueError:
    sys.exit("FATAL: ADMIN_GROUP_ID must be an integer (e.g. -1004417485510).")

# ----------------------------------------------------------------------
# Vehicle list
# ----------------------------------------------------------------------
VEHICLES = ["F01", "F02", "H01"] + \
           [f"M{i:02d}" for i in range(1, 32)] + \
           ["LOGAN"]

# ----------------------------------------------------------------------
# Database setup (SQLite) – drivers + problems
# ----------------------------------------------------------------------
DB_NAME = "drivers.db"

def init_db():
    conn = sqlite3.connect(DB_NAME)
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS drivers (
                    user_id INTEGER PRIMARY KEY,
                    name TEXT,
                    vehicle TEXT,
                    state TEXT)''')
    c.execute('''CREATE TABLE IF NOT EXISTS problems (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    user_id INTEGER,
                    driver_name TEXT,
                    vehicle TEXT,
                    problem_text TEXT,
                    media_ids TEXT,
                    date TEXT,
                    status TEXT DEFAULT 'Invalide')''')
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

def add_problem(user_id: int, driver_name: str, vehicle: str, problem_text: str, media_ids: str) -> int:
    conn = sqlite3.connect(DB_NAME)
    c = conn.cursor()
    date = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    c.execute("INSERT INTO problems (user_id, driver_name, vehicle, problem_text, media_ids, date) VALUES (?,?,?,?,?,?)",
              (user_id, driver_name, vehicle, problem_text, media_ids, date))
    problem_id = c.lastrowid
    conn.commit()
    conn.close()
    return problem_id

def update_problem_status(problem_id: int, new_status: str):
    conn = sqlite3.connect(DB_NAME)
    c = conn.cursor()
    c.execute("UPDATE problems SET status=? WHERE id=?", (new_status, problem_id))
    conn.commit()
    conn.close()

def get_problem(problem_id: int) -> dict | None:
    conn = sqlite3.connect(DB_NAME)
    c = conn.cursor()
    c.execute("SELECT id, driver_name, vehicle, problem_text, media_ids, date, status FROM problems WHERE id=?", (problem_id,))
    row = c.fetchone()
    conn.close()
    if row:
        return {
            "id": row[0],
            "driver_name": row[1],
            "vehicle": row[2],
            "problem_text": row[3],
            "media_ids": row[4],
            "date": row[5],
            "status": row[6]
        }
    return None

def get_all_problems() -> list:
    conn = sqlite3.connect(DB_NAME)
    c = conn.cursor()
    c.execute("SELECT id, driver_name, vehicle, problem_text, media_ids, date, status FROM problems ORDER BY date DESC")
    rows = c.fetchall()
    conn.close()
    return [
        {
            "id": r[0],
            "driver_name": r[1],
            "vehicle": r[2],
            "problem_text": r[3],
            "media_ids": r[4],
            "date": r[5],
            "status": r[6]
        }
        for r in rows
    ]

def vehicle_keyboard() -> InlineKeyboardMarkup:
    buttons = [InlineKeyboardButton(v, callback_data=f"veh_{v}") for v in VEHICLES]
    rows = [buttons[i:i+5] for i in range(0, len(buttons), 5)]
    return InlineKeyboardMarkup(rows)

# ----------------------------------------------------------------------
# Excel generation
# ----------------------------------------------------------------------
def generate_excel() -> BytesIO:
    problems = get_all_problems()
    wb = Workbook()
    ws = wb.active
    ws.title = "Problèmes"
    # Headers
    headers = ["Date", "Driver", "Vehicle", "Problem", "Media IDs", "Status"]
    for col, header in enumerate(headers, 1):
        cell = ws.cell(row=1, column=col, value=header)
        cell.font = Font(bold=True)
    # Data
    for row_idx, p in enumerate(problems, 2):
        ws.cell(row=row_idx, column=1, value=p["date"])
        ws.cell(row=row_idx, column=2, value=p["driver_name"])
        ws.cell(row=row_idx, column=3, value=p["vehicle"])
        ws.cell(row=row_idx, column=4, value=p["problem_text"])
        ws.cell(row=row_idx, column=5, value=p["media_ids"] or "—")
        ws.cell(row=row_idx, column=6, value=p["status"])
    # Auto-size columns (approximate)
    for col in ws.columns:
        max_length = 0
        col_letter = col[0].column_letter
        for cell in col:
            try:
                if cell.value:
                    max_length = max(max_length, len(str(cell.value)))
            except:
                pass
        ws.column_dimensions[col_letter].width = min(max_length + 2, 50)
    output = BytesIO()
    wb.save(output)
    output.seek(0)
    return output

# ----------------------------------------------------------------------
# Media group handling (for albums)
# ----------------------------------------------------------------------
media_groups = {}

async def forward_media_group(context: ContextTypes.DEFAULT_TYPE, group_id: str):
    data = media_groups.pop(group_id, None)
    if not data:
        return
    msgs = data["messages"]
    media_list = []
    user_id = msgs[0].from_user.id
    driver = get_driver(user_id)
    if not driver or not driver["name"] or not driver["vehicle"]:
        # fallback
        return

    header = f"Driver: {driver['name']}\nVehicle: {driver['vehicle']}\n"
    first_caption = msgs[0].caption or ""
    problem_text = first_caption if first_caption else "(voir média)"
    header += f"Problem: {problem_text}"

    # Collect file IDs
    file_ids = []
    for i, msg in enumerate(msgs):
        if msg.photo:
            fid = msg.photo[-1].file_id
            file_ids.append(fid)
            if i == 0:
                media_list.append(InputMediaPhoto(media=fid, caption=header))
            else:
                media_list.append(InputMediaPhoto(media=fid))
        elif msg.video:
            fid = msg.video.file_id
            file_ids.append(fid)
            if i == 0:
                media_list.append(InputMediaVideo(media=fid, caption=header))
            else:
                media_list.append(InputMediaVideo(media=fid))

    # Save problem to DB
    media_str = ",".join(file_ids)
    problem_id = add_problem(user_id, driver["name"], driver["vehicle"], problem_text, media_str)

    # Add inline button to toggle status
    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("✅ Marquer comme Valide", callback_data=f"status_{problem_id}")]
    ])
    sent_msgs = await context.bot.send_media_group(chat_id=ADMIN_GROUP_ID, media=media_list)
    # Attach the keyboard to the first message of the album (where caption is)
    if sent_msgs:
        await sent_msgs[0].edit_reply_markup(reply_markup=keyboard)

    # Send updated Excel
    await send_excel_to_group(context)

# ----------------------------------------------------------------------
# Helper: send Excel to group
# ----------------------------------------------------------------------
async def send_excel_to_group(context: ContextTypes.DEFAULT_TYPE):
    try:
        excel_file = generate_excel()
        await context.bot.send_document(
            chat_id=ADMIN_GROUP_ID,
            document=excel_file,
            filename="problemes.xlsx",
            caption="📊 Dernière mise à jour des problèmes"
        )
    except Exception as e:
        logging.error(f"Failed to send Excel: {e}")

# ----------------------------------------------------------------------
# Bot command & message handlers
# ----------------------------------------------------------------------
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
        # Save problem
        problem_id = add_problem(user_id, driver["name"], driver["vehicle"], text, "")
        report_text = f"Driver: {driver['name']}\nVehicle: {driver['vehicle']}\nProblem: {text}"
        keyboard = InlineKeyboardMarkup([
            [InlineKeyboardButton("✅ Marquer comme Valide", callback_data=f"status_{problem_id}")]
        ])
        await context.bot.send_message(
            chat_id=ADMIN_GROUP_ID,
            text=report_text,
            reply_markup=keyboard
        )
        # Send updated Excel
        await send_excel_to_group(context)
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
    problem_text = caption if caption else "(voir média)"
    header += f"Problem: {problem_text}"

    # Determine file ID
    file_id = None
    if update.message.photo:
        file_id = update.message.photo[-1].file_id
        media_input = InputMediaPhoto(media=file_id)
    elif update.message.video:
        file_id = update.message.video.file_id
        media_input = InputMediaVideo(media=file_id)
    else:
        return

    # Save to DB
    media_str = file_id if file_id else ""
    problem_id = add_problem(user_id, driver["name"], driver["vehicle"], problem_text, media_str)

    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton("✅ Marquer comme Valide", callback_data=f"status_{problem_id}")]
    ])
    msg = None
    if update.message.photo:
        msg = await context.bot.send_photo(
            chat_id=ADMIN_GROUP_ID,
            photo=file_id,
            caption=header,
            reply_markup=keyboard
        )
    elif update.message.video:
        msg = await context.bot.send_video(
            chat_id=ADMIN_GROUP_ID,
            video=file_id,
            caption=header,
            reply_markup=keyboard
        )
    # Send Excel
    await send_excel_to_group(context)

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

# ----------------------------------------------------------------------
# Status toggle callback (in group)
# ----------------------------------------------------------------------
async def status_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    data = query.data  # format: "status_<problem_id>"
    problem_id = int(data.split("_")[1])
    problem = get_problem(problem_id)
    if not problem:
        await query.edit_message_text("Problème introuvable.")
        return

    # Toggle status
    new_status = "Valide" if problem["status"] == "Invalide" else "Invalide"
    update_problem_status(problem_id, new_status)

    # Edit the keyboard to show the opposite action
    button_text = "✅ Marquer comme Valide" if new_status == "Invalide" else "❌ Marquer comme Invalide"
    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton(button_text, callback_data=f"status_{problem_id}")]
    ])
    # Also update the caption/text to reflect new status? We'll just edit the reply markup.
    try:
        await query.edit_message_reply_markup(reply_markup=keyboard)
    except Exception as e:
        logging.error(f"Failed to edit message: {e}")

    # Send updated Excel to group
    await send_excel_to_group(context)

# ----------------------------------------------------------------------
# /export command (group only, but works anywhere)
# ----------------------------------------------------------------------
async def export_excel(update: Update, context: ContextTypes.DEFAULT_TYPE):
    excel_file = generate_excel()
    await update.message.reply_document(
        document=excel_file,
        filename="problemes.xlsx",
        caption="📊 Dernière mise à jour des problèmes"
    )

async def error_handler(update: object, context: ContextTypes.DEFAULT_TYPE) -> None:
    logging.error(msg="Exception while handling an update:", exc_info=context.error)

# ----------------------------------------------------------------------
# Main – runs the bot in the main thread (Flask is in a daemon thread)
# ----------------------------------------------------------------------
def main():
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s"
    )
    logging.info("Starting bot...")
    init_db()

    try:
        app = Application.builder().token(BOT_TOKEN).build()
    except Exception as e:
        logging.critical(f"Failed to build Application: {e}")
        sys.exit(1)

    # Command / export
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("changename", change_name))
    app.add_handler(CommandHandler("changevehicle", change_vehicle))
    app.add_handler(CommandHandler("myinfo", my_info))
    app.add_handler(CommandHandler("export", export_excel))

    # Message handlers
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text))
    app.add_handler(MessageHandler(
        (filters.PHOTO | filters.VIDEO) & ~filters.CAPTION & ~filters.COMMAND,
        handle_media))
    app.add_handler(MessageHandler(
        filters.PHOTO | filters.VIDEO,
        handle_album_msg,
        block=False))
    app.add_handler(CallbackQueryHandler(handle_vehicle_callback, pattern="^veh_"))
    app.add_handler(CallbackQueryHandler(status_callback, pattern="^status_"))
    app.add_error_handler(error_handler)

    logging.info("Bot polling started...")
    app.run_polling(stop_signals=[])

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    flask_thread = threading.Thread(
        target=lambda: web_app.run(host="0.0.0.0", port=port),
        daemon=True
    )
    flask_thread.start()
    logging.info(f"Flask server started on port {port}")

    try:
        main()
    except KeyboardInterrupt:
        logging.info("Bot stopped by user.")
    except Exception as e:
        logging.critical(f"Unhandled exception in main: {e}", exc_info=True)
        sys.exit(1)
