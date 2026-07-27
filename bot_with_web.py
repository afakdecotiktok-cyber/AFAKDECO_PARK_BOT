import os
import sys
import sqlite3
import logging
import threading
import asyncio
from datetime import datetime, time, timedelta
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
ADMIN_IDS_STR = os.environ.get("ADMIN_IDS", "")  # Comma-separated list of admin user IDs

if not BOT_TOKEN:
    sys.exit("FATAL: BOT_TOKEN environment variable not set.")
if not ADMIN_GROUP_ID_STR:
    sys.exit("FATAL: ADMIN_GROUP_ID environment variable not set.")
try:
    ADMIN_GROUP_ID = int(ADMIN_GROUP_ID_STR)
except ValueError:
    sys.exit("FATAL: ADMIN_GROUP_ID must be an integer (e.g. -1004417485510).")

# Parse admin IDs (now only used for Delete)
ADMIN_IDS = set()
if ADMIN_IDS_STR:
    for uid in ADMIN_IDS_STR.split(","):
        uid = uid.strip()
        if uid.isdigit():
            ADMIN_IDS.add(int(uid))

# ----------------------------------------------------------------------
# Vehicle list – fixed list + dynamic "أخرى" option
# ----------------------------------------------------------------------
VEHICLES = ["F01", "F02", "H01"] + [f"M{i:02d}" for i in range(1, 32)] + ["LOGAN"]

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
                    media_type TEXT,
                    date TEXT,
                    status TEXT DEFAULT 'غير صحيح',
                    ruglee TEXT DEFAULT 'غير مُصلح')''')
    # Add comments column if it doesn't exist
    try:
        c.execute("ALTER TABLE problems ADD COLUMN comments TEXT DEFAULT ''")
    except sqlite3.OperationalError:
        pass  # column already exists
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

def add_problem(user_id: int, driver_name: str, vehicle: str, problem_text: str, media_type: str) -> int:
    conn = sqlite3.connect(DB_NAME)
    c = conn.cursor()
    date = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    c.execute(
        "INSERT INTO problems (user_id, driver_name, vehicle, problem_text, media_type, date) VALUES (?,?,?,?,?,?)",
        (user_id, driver_name, vehicle, problem_text, media_type, date)
    )
    problem_id = c.lastrowid
    conn.commit()
    conn.close()
    return problem_id

def update_problem_status(problem_id: int, status: str = None, ruglee: str = None):
    conn = sqlite3.connect(DB_NAME)
    c = conn.cursor()
    if status is not None:
        c.execute("UPDATE problems SET status=? WHERE id=?", (status, problem_id))
    if ruglee is not None:
        c.execute("UPDATE problems SET ruglee=? WHERE id=?", (ruglee, problem_id))
    conn.commit()
    conn.close()

def set_problem_comment(problem_id: int, comment: str):
    conn = sqlite3.connect(DB_NAME)
    c = conn.cursor()
    c.execute("UPDATE problems SET comments=? WHERE id=?", (comment, problem_id))
    conn.commit()
    conn.close()

def delete_problem(problem_id: int):
    conn = sqlite3.connect(DB_NAME)
    c = conn.cursor()
    c.execute("DELETE FROM problems WHERE id=?", (problem_id,))
    conn.commit()
    conn.close()

def get_problem(problem_id: int) -> dict | None:
    conn = sqlite3.connect(DB_NAME)
    c = conn.cursor()
    c.execute("SELECT id, driver_name, vehicle, problem_text, media_type, date, status, ruglee, comments FROM problems WHERE id=?", (problem_id,))
    row = c.fetchone()
    conn.close()
    if row:
        return {
            "id": row[0],
            "driver_name": row[1],
            "vehicle": row[2],
            "problem_text": row[3],
            "media_type": row[4],
            "date": row[5],
            "status": row[6],
            "ruglee": row[7],
            "comments": row[8] or ""
        }
    return None

def get_all_problems() -> list:
    conn = sqlite3.connect(DB_NAME)
    c = conn.cursor()
    c.execute("SELECT id, driver_name, vehicle, problem_text, media_type, date, status, ruglee, comments FROM problems ORDER BY date DESC")
    rows = c.fetchall()
    conn.close()
    return [
        {
            "id": r[0],
            "driver_name": r[1],
            "vehicle": r[2],
            "problem_text": r[3],
            "media_type": r[4],
            "date": r[5],
            "status": r[6],
            "ruglee": r[7],
            "comments": r[8] or ""
        }
        for r in rows
    ]

# ----------------------------------------------------------------------
# Vehicle keyboard with "أخرى" option
# ----------------------------------------------------------------------
def vehicle_keyboard() -> InlineKeyboardMarkup:
    buttons = [InlineKeyboardButton(v, callback_data=f"veh_{v}") for v in VEHICLES]
    buttons.append(InlineKeyboardButton("➖ أخرى (إدخال يدوي)", callback_data="veh_OTHER"))
    rows = [buttons[i:i+4] for i in range(0, len(buttons), 4)]
    return InlineKeyboardMarkup(rows)

# ----------------------------------------------------------------------
# Excel generation with Arabic columns (including comments)
# ----------------------------------------------------------------------
def generate_excel() -> BytesIO:
    problems = get_all_problems()
    wb = Workbook()
    ws = wb.active
    ws.title = "المشاكل"
    headers = ["التاريخ", "السائق", "المركبة", "المشكلة", "نوع الوسائط", "الحالة", "تم الإصلاح", "تعليقات"]
    for col, header in enumerate(headers, 1):
        cell = ws.cell(row=1, column=col, value=header)
        cell.font = Font(bold=True)
    for row_idx, p in enumerate(problems, 2):
        ws.cell(row=row_idx, column=1, value=p["date"])
        ws.cell(row=row_idx, column=2, value=p["driver_name"])
        ws.cell(row=row_idx, column=3, value=p["vehicle"])
        ws.cell(row=row_idx, column=4, value=p["problem_text"])
        ws.cell(row=row_idx, column=5, value=p["media_type"] or "—")
        ws.cell(row=row_idx, column=6, value=p["status"])
        ws.cell(row=row_idx, column=7, value=p["ruglee"])
        ws.cell(row=row_idx, column=8, value=p["comments"] or "")
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
# Helper: send Excel to group (used only by scheduled job)
# ----------------------------------------------------------------------
async def send_excel_to_group(context: ContextTypes.DEFAULT_TYPE):
    try:
        excel_file = generate_excel()
        await context.bot.send_document(
            chat_id=ADMIN_GROUP_ID,
            document=excel_file,
            filename="المشاكل.xlsx",
            caption="📊 التحديث الدوري لملف المشاكل"
        )
    except Exception as e:
        logging.error(f"Failed to send Excel: {e}")

# ----------------------------------------------------------------------
# Media group handling (albums) – supports photo/video only
# ----------------------------------------------------------------------
media_groups = {}

async def forward_media_group(context: ContextTypes.DEFAULT_TYPE, group_id: str):
    data = media_groups.pop(group_id, None)
    if not data:
        return
    msgs = data["messages"]
    user_id = msgs[0].from_user.id
    driver = get_driver(user_id)
    if not driver or not driver["name"] or not driver["vehicle"]:
        return

    header = f"السائق: {driver['name']}\nالمركبة: {driver['vehicle']}\n"
    first_caption = msgs[0].caption or ""
    problem_text = first_caption if first_caption else "(مرفق وسائط)"
    header += f"المشكلة: {problem_text}"

    media_types = []
    media_list = []
    for i, msg in enumerate(msgs):
        if msg.photo:
            fid = msg.photo[-1].file_id
            media_types.append("صورة")
            if i == 0:
                media_list.append(InputMediaPhoto(media=fid, caption=header))
            else:
                media_list.append(InputMediaPhoto(media=fid))
        elif msg.video:
            fid = msg.video.file_id
            media_types.append("فيديو")
            if i == 0:
                media_list.append(InputMediaVideo(media=fid, caption=header))
            else:
                media_list.append(InputMediaVideo(media=fid))

    if media_list:
        sent_msgs = await context.bot.send_media_group(chat_id=ADMIN_GROUP_ID, media=media_list)
        problem_id = add_problem(user_id, driver["name"], driver["vehicle"], problem_text, ", ".join(media_types))
        keyboard = build_problem_keyboard(problem_id)
        if sent_msgs:
            try:
                await sent_msgs[0].edit_reply_markup(reply_markup=keyboard)
            except:
                pass

# ----------------------------------------------------------------------
# Build inline keyboard for problem (Valide + Ruglee + Comment + Delete)
# ----------------------------------------------------------------------
def build_problem_keyboard(problem_id: int) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup([
        [
            InlineKeyboardButton("✅ صحيح", callback_data=f"val_{problem_id}"),
            InlineKeyboardButton("🔧 تم الإصلاح", callback_data=f"rug_{problem_id}")
        ],
        [InlineKeyboardButton("💬 تعليق", callback_data=f"com_{problem_id}")],
        [InlineKeyboardButton("🗑️ حذف المشكلة", callback_data=f"del_{problem_id}")]
    ])

# ----------------------------------------------------------------------
# Comment sessions (any user can comment)
# ----------------------------------------------------------------------
comment_sessions = {}  # user_id -> problem_id

# ----------------------------------------------------------------------
# Bot command & message handlers (Arabic)
# ----------------------------------------------------------------------
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    driver = get_driver(user_id)
    if driver and driver["name"] and driver["vehicle"]:
        await update.message.reply_text(
            f"أهلاً بعودتك، {driver['name']}!\nمركبتك: {driver['vehicle']}\n"
            "أرسل لي وصف المشكلة (نص، صورة، فيديو، أو رسالة صوتية) وسأقوم بإرسالها إلى الورشة."
        )
    else:
        set_driver(user_id, state="name_entry")
        await update.message.reply_text("مرحباً! أنا بوت الإبلاغ عن الأعطال.\nالرجاء إدخال اسمك الكامل:")

async def change_name(update: Update, context: ContextTypes.DEFAULT_TYPE):
    set_driver(update.effective_user.id, state="name_entry")
    await update.message.reply_text("أرسل لي اسمك الجديد:")

async def change_vehicle(update: Update, context: ContextTypes.DEFAULT_TYPE):
    set_driver(update.effective_user.id, state="vehicle_selection")
    await update.message.reply_text("اختر مركبتك:", reply_markup=vehicle_keyboard())

async def my_info(update: Update, context: ContextTypes.DEFAULT_TYPE):
    driver = get_driver(update.effective_user.id)
    if driver and driver["name"] and driver["vehicle"]:
        await update.message.reply_text(f"الاسم: {driver['name']}\nالمركبة: {driver['vehicle']}")
    else:
        await update.message.reply_text("ملفك غير مكتمل. استخدم /start لإعداده.")

async def handle_text(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    text = update.message.text

    # ---------- Comment session (any user) ----------
    if user_id in comment_sessions:
        problem_id = comment_sessions.pop(user_id)
        set_problem_comment(problem_id, text)
        await update.message.reply_text("✅ تم حفظ التعليق بنجاح.")
        return

    # ---------- Driver state machine ----------
    driver = get_driver(user_id)
    state = driver["state"] if driver else "name_entry"

    if state == "name_entry":
        set_driver(user_id, name=text, state="vehicle_selection")
        await update.message.reply_text(f"تم حفظ الاسم: {text}\nالآن اختر المركبة:", reply_markup=vehicle_keyboard())
        return

    if state == "vehicle_selection":
        await update.message.reply_text("الرجاء اختيار المركبة من الأزرار أدناه، أو اضغط 'أخرى' لإدخال رمز مخصص.")
        return

    if state == "custom_vehicle_entry":
        set_driver(user_id, vehicle=text, state="idle")
        await update.message.reply_text(
            f"تم تعيين المركبة إلى {text}.\nملفك مكتمل. يمكنك الآن إرسال بلاغات الأعطال.\n"
            "استخدم /changevehicle أو /changename للتعديل لاحقاً."
        )
        return

    # Problem report
    if driver and driver["name"] and driver["vehicle"]:
        problem_id = add_problem(user_id, driver["name"], driver["vehicle"], text, "")
        report_text = f"السائق: {driver['name']}\nالمركبة: {driver['vehicle']}\nالمشكلة: {text}"
        await context.bot.send_message(
            chat_id=ADMIN_GROUP_ID,
            text=report_text,
            reply_markup=build_problem_keyboard(problem_id)
        )
    else:
        await update.message.reply_text("ملفك غير مكتمل. الرجاء استخدام /start أولاً.")

async def handle_media(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    driver = get_driver(user_id)
    if not driver or not driver["name"] or not driver["vehicle"]:
        await update.message.reply_text("ملفك غير مكتمل. الرجاء استخدام /start أولاً.")
        return

    caption = update.message.caption or ""
    problem_text = caption if caption else "(مرفق وسائط)"
    header = f"السائق: {driver['name']}\nالمركبة: {driver['vehicle']}\nالمشكلة: {problem_text}"

    media_type = ""
    if update.message.photo:
        file_id = update.message.photo[-1].file_id
        media_type = "صورة"
        problem_id = add_problem(user_id, driver["name"], driver["vehicle"], problem_text, media_type)
        await context.bot.send_photo(
            chat_id=ADMIN_GROUP_ID,
            photo=file_id,
            caption=header,
            reply_markup=build_problem_keyboard(problem_id)
        )
    elif update.message.video:
        file_id = update.message.video.file_id
        media_type = "فيديو"
        problem_id = add_problem(user_id, driver["name"], driver["vehicle"], problem_text, media_type)
        await context.bot.send_video(
            chat_id=ADMIN_GROUP_ID,
            video=file_id,
            caption=header,
            reply_markup=build_problem_keyboard(problem_id)
        )
    elif update.message.voice:
        file_id = update.message.voice.file_id
        media_type = "صوت"
        problem_id = add_problem(user_id, driver["name"], driver["vehicle"], problem_text, media_type)
        await context.bot.send_voice(
            chat_id=ADMIN_GROUP_ID,
            voice=file_id,
            caption=header,
            reply_markup=build_problem_keyboard(problem_id)
        )

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
    data = query.data  # "veh_XXX" or "veh_OTHER"
    vehicle = data.split("_", 1)[1]
    user_id = query.from_user.id

    if vehicle == "OTHER":
        set_driver(user_id, state="custom_vehicle_entry")
        await query.edit_message_text("الرجاء إدخال رمز المركبة يدوياً (مثال: T01، LOGAN):")
    else:
        set_driver(user_id, vehicle=vehicle, state="idle")
        await query.edit_message_text(
            f"تم تعيين المركبة إلى {vehicle}.\nملفك مكتمل. يمكنك الآن إرسال بلاغات الأعطال.\n"
            "استخدم /changevehicle أو /changename للتعديل لاحقاً."
        )

# ----------------------------------------------------------------------
# Valider / Ruglee – NOW OPEN TO ALL GROUP MEMBERS (no admin check)
# ----------------------------------------------------------------------
async def toggle_valide(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    problem_id = int(query.data.split("_")[1])
    problem = get_problem(problem_id)
    if not problem:
        await query.answer("المشكلة غير موجودة.")
        return

    new_status = "صحيح" if problem["status"] == "غير صحيح" else "غير صحيح"
    update_problem_status(problem_id, status=new_status)

    val_text = "✅ صحيح" if new_status == "غير صحيح" else "❌ غير صحيح"
    rug_text = "🔧 تم الإصلاح" if problem["ruglee"] == "غير مُصلح" else "🔄 لم يتم الإصلاح"
    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton(val_text, callback_data=f"val_{problem_id}"),
         InlineKeyboardButton(rug_text, callback_data=f"rug_{problem_id}")],
        [InlineKeyboardButton("💬 تعليق", callback_data=f"com_{problem_id}")],
        [InlineKeyboardButton("🗑️ حذف المشكلة", callback_data=f"del_{problem_id}")]
    ])
    try:
        await query.edit_message_reply_markup(reply_markup=keyboard)
    except Exception as e:
        logging.error(f"Edit markup error: {e}")

async def toggle_ruglee(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    problem_id = int(query.data.split("_")[1])
    problem = get_problem(problem_id)
    if not problem:
        await query.answer("المشكلة غير موجودة.")
        return

    new_ruglee = "تم الإصلاح" if problem["ruglee"] == "غير مُصلح" else "غير مُصلح"
    update_problem_status(problem_id, ruglee=new_ruglee)

    rug_text = "🔧 تم الإصلاح" if new_ruglee == "غير مُصلح" else "🔄 لم يتم الإصلاح"
    val_text = "✅ صحيح" if problem["status"] == "غير صحيح" else "❌ غير صحيح"
    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton(val_text, callback_data=f"val_{problem_id}"),
         InlineKeyboardButton(rug_text, callback_data=f"rug_{problem_id}")],
        [InlineKeyboardButton("💬 تعليق", callback_data=f"com_{problem_id}")],
        [InlineKeyboardButton("🗑️ حذف المشكلة", callback_data=f"del_{problem_id}")]
    ])
    try:
        await query.edit_message_reply_markup(reply_markup=keyboard)
    except Exception as e:
        logging.error(f"Edit markup error: {e}")

# ----------------------------------------------------------------------
# Comment – open to ALL group users
# ----------------------------------------------------------------------
async def comment_problem(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    problem_id = int(query.data.split("_")[1])
    problem = get_problem(problem_id)
    if not problem:
        await query.answer("المشكلة غير موجودة.")
        return

    user_id = update.effective_user.id
    comment_sessions[user_id] = problem_id
    await context.bot.send_message(
        chat_id=user_id,
        text=f"📝 أرسل تعليقك على المشكلة رقم {problem_id} (نص فقط):"
    )
    await query.answer("تم تفعيل وضع التعليق. أرسل التعليق في المحادثة الخاصة.", show_alert=True)

# ----------------------------------------------------------------------
# Delete – admin-only
# ----------------------------------------------------------------------
async def delete_problem_handler(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    if update.effective_user.id not in ADMIN_IDS:
        await query.answer("⛔ غير مصرح لك بهذا الإجراء.", show_alert=True)
        return
    problem_id = int(query.data.split("_")[1])
    problem = get_problem(problem_id)
    if not problem:
        await query.edit_message_text("المشكلة غير موجودة.")
        return

    delete_problem(problem_id)
    original_text = query.message.text or query.message.caption or ""
    new_text = f"🗑️ تم حذف المشكلة\n( {original_text} )"
    try:
        if query.message.text:
            await query.edit_message_text(new_text)
        else:
            await query.edit_message_caption(caption=new_text)
    except Exception as e:
        logging.error(f"Could not edit message after delete: {e}")

# ----------------------------------------------------------------------
# /export command (manual Excel retrieval) – available to anyone in the group
# ----------------------------------------------------------------------
async def export_excel(update: Update, context: ContextTypes.DEFAULT_TYPE):
    excel_file = generate_excel()
    await update.message.reply_document(
        document=excel_file,
        filename="المشاكل.xlsx",
        caption="📊 أحدث تحديث لملف المشاكل"
    )

# ----------------------------------------------------------------------
# Scheduled job: send Excel every 3 days at 7:30 AM
# ----------------------------------------------------------------------
async def scheduled_excel(context: ContextTypes.DEFAULT_TYPE):
    await send_excel_to_group(context)

def schedule_excel_job(app: Application):
    now = datetime.now()
    target_time = time(7, 30, 0)
    next_run = datetime.combine(now.date(), target_time)
    if now >= next_run:
        next_run += timedelta(days=1)
    app.job_queue.run_repeating(
        scheduled_excel,
        interval=3 * 24 * 60 * 60,  # 3 days
        first=next_run
    )

# ----------------------------------------------------------------------
# Error handler
# ----------------------------------------------------------------------
async def error_handler(update: object, context: ContextTypes.DEFAULT_TYPE) -> None:
    logging.error(msg="Exception while handling an update:", exc_info=context.error)

# ----------------------------------------------------------------------
# Main – bot in main thread, Flask in daemon thread
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

    # Command handlers
    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("changename", change_name))
    app.add_handler(CommandHandler("changevehicle", change_vehicle))
    app.add_handler(CommandHandler("myinfo", my_info))
    app.add_handler(CommandHandler("export", export_excel))

    # Message handlers
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text))
    app.add_handler(MessageHandler(
        (filters.PHOTO | filters.VIDEO | filters.VOICE) & ~filters.CAPTION & ~filters.COMMAND,
        handle_media
    ))
    app.add_handler(MessageHandler(
        filters.PHOTO | filters.VIDEO,
        handle_album_msg,
        block=False
    ))

    # Callback handlers
    app.add_handler(CallbackQueryHandler(handle_vehicle_callback, pattern="^veh_"))
    app.add_handler(CallbackQueryHandler(toggle_valide, pattern="^val_"))
    app.add_handler(CallbackQueryHandler(toggle_ruglee, pattern="^rug_"))
    app.add_handler(CallbackQueryHandler(comment_problem, pattern="^com_"))
    app.add_handler(CallbackQueryHandler(delete_problem_handler, pattern="^del_"))
    app.add_error_handler(error_handler)

    # Schedule Excel every 3 days at 7:30 AM
    schedule_excel_job(app)

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
