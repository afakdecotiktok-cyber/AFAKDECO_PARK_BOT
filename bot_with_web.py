import os, sys, logging, threading, asyncio
from datetime import datetime, time, timedelta
from io import BytesIO
from collections import defaultdict

import psycopg2, psycopg2.extras
from flask import Flask
from openpyxl import Workbook
from openpyxl.styles import Font

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, InputMediaPhoto, InputMediaVideo, ReplyKeyboardMarkup, KeyboardButton
from telegram.ext import Application, CommandHandler, MessageHandler, CallbackQueryHandler, filters, ContextTypes

# ----------------------------------------------------------------------
# Flask app
# ----------------------------------------------------------------------
web_app = Flask(__name__)

@web_app.route('/')
def home():
    return "Bot is running."

# ----------------------------------------------------------------------
# Environment variables
# ----------------------------------------------------------------------
BOT_TOKEN = os.environ.get("BOT_TOKEN")
ADMIN_GROUP_ID_STR = os.environ.get("ADMIN_GROUP_ID")
ADMIN_IDS_STR = os.environ.get("ADMIN_IDS", "")
DATABASE_URL = os.environ.get("DATABASE_URL")

TOPIC_RECLAMATIONS = int(os.environ.get("TOPIC_RECLAMATIONS", "0"))
TOPIC_VALIDATION = int(os.environ.get("TOPIC_VALIDATION", "0"))
TOPIC_VIDANGE = int(os.environ.get("TOPIC_VIDANGE", "0"))
TOPIC_VEHICLE_MGMT = int(os.environ.get("TOPIC_VEHICLE_MGMT", "0"))
TOPIC_GENERAL = int(os.environ.get("TOPIC_GENERAL", "0"))
TOPIC_HISTORY = int(os.environ.get("TOPIC_HISTORY", "0"))

if not all([BOT_TOKEN, ADMIN_GROUP_ID_STR, DATABASE_URL]):
    sys.exit("FATAL: BOT_TOKEN, ADMIN_GROUP_ID and DATABASE_URL must be set.")
if not all([TOPIC_RECLAMATIONS, TOPIC_VALIDATION, TOPIC_VIDANGE, TOPIC_VEHICLE_MGMT, TOPIC_GENERAL, TOPIC_HISTORY]):
    sys.exit("FATAL: All TOPIC_* environment variables must be set.")

try:
    ADMIN_GROUP_ID = int(ADMIN_GROUP_ID_STR)
except ValueError:
    sys.exit("FATAL: ADMIN_GROUP_ID must be an integer.")

ADMIN_IDS = set()
if ADMIN_IDS_STR:
    for uid in ADMIN_IDS_STR.split(","):
        uid = uid.strip()
        if uid.isdigit():
            ADMIN_IDS.add(int(uid))

# ----------------------------------------------------------------------
# PostgreSQL helper
# ----------------------------------------------------------------------
def get_conn():
    return psycopg2.connect(DATABASE_URL, sslmode='require')

def init_db():
    conn = get_conn()
    cur = conn.cursor()
    cur.execute('''
        CREATE TABLE IF NOT EXISTS drivers (
            user_id BIGINT PRIMARY KEY,
            name TEXT,
            vehicle TEXT,
            state TEXT
        )
    ''')
    cur.execute('''
        CREATE TABLE IF NOT EXISTS vehicles (
            code TEXT PRIMARY KEY
        )
    ''')
    cur.execute("SELECT COUNT(*) FROM vehicles")
    if cur.fetchone()[0] == 0:
        default_vehicles = ["F01","F02","H01"] + [f"M{i:02d}" for i in range(1,32)] + ["LOGAN"]
        for v in default_vehicles:
            cur.execute("INSERT INTO vehicles (code) VALUES (%s) ON CONFLICT DO NOTHING", (v,))
    cur.execute('''
        CREATE TABLE IF NOT EXISTS problems (
            id SERIAL PRIMARY KEY,
            user_id BIGINT,
            driver_name TEXT,
            vehicle TEXT,
            problem_text TEXT,
            media_type TEXT,
            date TEXT,
            status TEXT DEFAULT 'قيد الانتظار',
            ruglee TEXT DEFAULT 'غير مُصلح',
            comments TEXT DEFAULT '',
            validation_requester BIGINT DEFAULT 0
        )
    ''')
    cur.execute('''
        CREATE TABLE IF NOT EXISTS km_readings (
            id SERIAL PRIMARY KEY,
            vehicle TEXT,
            km INTEGER,
            date TEXT
        )
    ''')
    cur.execute('''
        CREATE TABLE IF NOT EXISTS vehicle_vidange (
            vehicle TEXT PRIMARY KEY,
            last_vidange_km INTEGER DEFAULT 0
        )
    ''')
    cur.execute("SELECT code FROM vehicles")
    vehicles = [r[0] for r in cur.fetchall()]
    for v in vehicles:
        cur.execute("INSERT INTO vehicle_vidange (vehicle, last_vidange_km) VALUES (%s, 0) ON CONFLICT DO NOTHING", (v,))
    conn.commit()
    cur.close()
    conn.close()

# ----------------------------------------------------------------------
# Database functions
# ----------------------------------------------------------------------
def get_driver(user_id: int) -> dict | None:
    conn = get_conn()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT name, vehicle, state FROM drivers WHERE user_id = %s", (user_id,))
    row = cur.fetchone()
    cur.close()
    conn.close()
    return dict(row) if row else None

def set_driver(user_id: int, name=None, vehicle=None, state=None):
    conn = get_conn()
    cur = conn.cursor()
    driver = get_driver(user_id)
    if driver:
        if name is not None:
            cur.execute("UPDATE drivers SET name=%s WHERE user_id=%s", (name, user_id))
        if vehicle is not None:
            cur.execute("UPDATE drivers SET vehicle=%s WHERE user_id=%s", (vehicle, user_id))
        if state is not None:
            cur.execute("UPDATE drivers SET state=%s WHERE user_id=%s", (state, user_id))
    else:
        cur.execute("INSERT INTO drivers (user_id, name, vehicle, state) VALUES (%s,%s,%s,%s)",
                    (user_id, name or "", vehicle or "", state or "name_entry"))
    conn.commit()
    cur.close()
    conn.close()

def get_all_vehicles():
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("SELECT code FROM vehicles ORDER BY code")
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return [r[0] for r in rows]

def add_vehicle(code: str):
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("INSERT INTO vehicles (code) VALUES (%s) ON CONFLICT DO NOTHING", (code,))
    cur.execute("INSERT INTO vehicle_vidange (vehicle, last_vidange_km) VALUES (%s, 0) ON CONFLICT DO NOTHING", (code,))
    conn.commit()
    cur.close()
    conn.close()

def remove_vehicle(code: str):
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("DELETE FROM vehicles WHERE code=%s", (code,))
    conn.commit()
    cur.close()
    conn.close()

def add_problem(user_id: int, driver_name: str, vehicle: str, problem_text: str, media_type: str) -> int:
    conn = get_conn()
    cur = conn.cursor()
    date = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    cur.execute(
        "INSERT INTO problems (user_id, driver_name, vehicle, problem_text, media_type, date) VALUES (%s,%s,%s,%s,%s,%s) RETURNING id",
        (user_id, driver_name, vehicle, problem_text, media_type, date)
    )
    problem_id = cur.fetchone()[0]
    conn.commit()
    cur.close()
    conn.close()
    return problem_id

def update_problem_status(problem_id: int, status=None, ruglee=None, validation_requester=None):
    conn = get_conn()
    cur = conn.cursor()
    if status is not None:
        cur.execute("UPDATE problems SET status=%s WHERE id=%s", (status, problem_id))
    if ruglee is not None:
        cur.execute("UPDATE problems SET ruglee=%s WHERE id=%s", (ruglee, problem_id))
    if validation_requester is not None:
        cur.execute("UPDATE problems SET validation_requester=%s WHERE id=%s", (validation_requester, problem_id))
    conn.commit()
    cur.close()
    conn.close()

def set_problem_comment(problem_id: int, comment: str):
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("UPDATE problems SET comments=%s WHERE id=%s", (comment, problem_id))
    conn.commit()
    cur.close()
    conn.close()

def delete_problem(problem_id: int):
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("DELETE FROM problems WHERE id=%s", (problem_id,))
    conn.commit()
    cur.close()
    conn.close()

def get_problem(problem_id: int) -> dict | None:
    conn = get_conn()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT * FROM problems WHERE id=%s", (problem_id,))
    row = cur.fetchone()
    cur.close()
    conn.close()
    return dict(row) if row else None

def get_all_problems():
    conn = get_conn()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT * FROM problems ORDER BY date DESC")
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return [dict(r) for r in rows]

def get_driver_problems(user_id: int, status_filter: str = None) -> list:
    conn = get_conn()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    if status_filter:
        cur.execute("SELECT * FROM problems WHERE user_id=%s AND status=%s ORDER BY date DESC", (user_id, status_filter))
    else:
        cur.execute("SELECT * FROM problems WHERE user_id=%s ORDER BY date DESC", (user_id,))
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return [dict(r) for r in rows]

def add_km_reading(vehicle: str, km: int):
    conn = get_conn()
    cur = conn.cursor()
    date = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    cur.execute("INSERT INTO km_readings (vehicle, km, date) VALUES (%s,%s,%s)", (vehicle, km, date))
    conn.commit()
    cur.close()
    conn.close()

def get_last_vidange_km(vehicle: str) -> int:
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("SELECT last_vidange_km FROM vehicle_vidange WHERE vehicle=%s", (vehicle,))
    row = cur.fetchone()
    cur.close()
    conn.close()
    return row[0] if row else 0

def set_last_vidange_km(vehicle: str, km: int):
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("UPDATE vehicle_vidange SET last_vidange_km=%s WHERE vehicle=%s", (km, vehicle))
    conn.commit()
    cur.close()
    conn.close()

def has_active_vidange(vehicle: str) -> bool:
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("SELECT id FROM problems WHERE vehicle=%s AND media_type='نظام' AND ruglee != 'تم الإصلاح'", (vehicle,))
    row = cur.fetchone()
    cur.close()
    conn.close()
    return row is not None

def get_vehicle_status(vehicle: str) -> str:
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM problems WHERE vehicle=%s AND status='قيد الانتظار'", (vehicle,))
    if cur.fetchone()[0] > 0:
        return 'bad'
    cur.execute("SELECT COUNT(*) FROM problems WHERE vehicle=%s AND status='قيد التصليح'", (vehicle,))
    if cur.fetchone()[0] > 0:
        return 'en_cours'
    return 'good'

# ----------------------------------------------------------------------
# Excel generation
# ----------------------------------------------------------------------
def generate_problems_excel() -> BytesIO:
    problems = get_all_problems()
    wb = Workbook()
    ws = wb.active
    ws.title = "المشاكل"
    headers = ["التاريخ", "السائق", "المركبة", "المشكلة", "نوع الوسائط", "الحالة", "تم الإصلاح", "تعليقات"]
    for col, h in enumerate(headers, 1):
        ws.cell(row=1, column=col, value=h).font = Font(bold=True)
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
        max_len = max((len(str(c.value)) for c in col if c.value), default=0)
        ws.column_dimensions[col[0].column_letter].width = min(max_len+2, 50)
    out = BytesIO()
    wb.save(out)
    out.seek(0)
    return out

def generate_vidange_excel() -> BytesIO:
    vehicles = get_all_vehicles()
    wb = Workbook()
    wb.remove(wb.active)
    for v in vehicles:
        ws = wb.create_sheet(title=v)
        ws.append(["التاريخ", "العداد الحالي (KM)", "آخر فيدانج (KM)"])
        conn = get_conn()
        cur = conn.cursor()
        cur.execute("SELECT date, km FROM km_readings WHERE vehicle=%s ORDER BY date DESC", (v,))
        readings = cur.fetchall()
        last_km = get_last_vidange_km(v)
        for date_str, km in readings:
            ws.append([date_str, km, last_km])
        cur.close()
        conn.close()
        for col in ws.columns:
            max_len = max((len(str(c.value)) for c in col if c.value), default=0)
            ws.column_dimensions[col[0].column_letter].width = min(max_len+2, 50)
    out = BytesIO()
    wb.save(out)
    out.seek(0)
    return out

# ----------------------------------------------------------------------
# Keyboards
# ----------------------------------------------------------------------
DRIVER_KEYBOARD = ReplyKeyboardMarkup([
    [KeyboardButton("📝 تقديم شكوى"), KeyboardButton("✅ طلب التحقق من الإصلاح")],
    [KeyboardButton("🚗 إدخال عدد الكيلومترات")]
], resize_keyboard=True)

def vehicle_inline_keyboard(vehicles: list, prefix="selv_") -> InlineKeyboardMarkup:
    buttons = [InlineKeyboardButton(v, callback_data=f"{prefix}{v}") for v in vehicles]
    return InlineKeyboardMarkup([buttons[i:i+4] for i in range(0, len(buttons), 4)])

def status_emoji(vehicle: str) -> str:
    s = get_vehicle_status(vehicle)
    if s == 'bad': return "🔴"
    if s == 'en_cours': return "🟠"
    return "🟢"

# ----------------------------------------------------------------------
# Handlers
# ----------------------------------------------------------------------
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    driver = get_driver(user_id)
    if driver and driver["name"] and driver["vehicle"]:
        # Force state to idle if already fully registered
        if driver["state"] != "idle":
            set_driver(user_id, state="idle")
        await update.message.reply_text(
            f"أهلاً بعودتك، {driver['name']}!\nمركبتك: {driver['vehicle']}",
            reply_markup=DRIVER_KEYBOARD
        )
    else:
        set_driver(user_id, state="name_entry")
        await update.message.reply_text("مرحباً! الرجاء إدخال اسمك الكامل:")

async def handle_text(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    text = update.message.text.strip()
    driver = get_driver(user_id)
    state = driver["state"] if driver else "name_entry"

    # ----- global comment sessions -----
    if context.user_data.get("awaiting_comment"):
        problem_id = context.user_data.pop("awaiting_comment")
        set_problem_comment(problem_id, text)
        await update.message.reply_text("✅ تم حفظ التعليق بنجاح.", reply_markup=DRIVER_KEYBOARD)
        return

    # ----- await km entry after vidange repair -----
    if context.user_data.get("await_km"):
        vehicle = context.user_data["await_km_vehicle"]
        if text.isdigit():
            km = int(text)
            add_km_reading(vehicle, km)
            set_last_vidange_km(vehicle, km)
            await update.message.reply_text(f"✅ تم تحديث العداد إلى {km} كم للمركبة {vehicle}.", reply_markup=DRIVER_KEYBOARD)
            context.user_data.clear()
            return
        else:
            await update.message.reply_text("الرجاء إرسال رقم صحيح.")
            return

    # ----- state machine for name / vehicle -----
    if state == "name_entry":
        set_driver(user_id, name=text, state="vehicle_selection")
        vehicles = get_all_vehicles()
        await update.message.reply_text("تم حفظ الاسم. اختر مركبتك:", reply_markup=vehicle_inline_keyboard(vehicles, "selv_"))
        return

    if state == "vehicle_selection":
        # Show the vehicle list again
        vehicles = get_all_vehicles()
        await update.message.reply_text("الرجاء اختيار المركبة من القائمة:", reply_markup=vehicle_inline_keyboard(vehicles, "selv_"))
        return

    # ----- Driver commands via keyboard buttons -----
    if text == "📝 تقديم شكوى":
        await update.message.reply_text("أرسل وصف المشكلة (نص، صورة، فيديو، أو صوت).", reply_markup=DRIVER_KEYBOARD)
        context.user_data["expecting_reclamation"] = True
        return

    if text == "✅ طلب التحقق من الإصلاح":
        problems = get_driver_problems(user_id, status_filter="قيد التصليح")
        if not problems:
            await update.message.reply_text("لا توجد مشاكل بحاجة للتحقق من إصلاحها.", reply_markup=DRIVER_KEYBOARD)
            return
        buttons = [InlineKeyboardButton(f"مشكلة #{p['id']} - {p['problem_text'][:30]}...", callback_data=f"valreq_{p['id']}") for p in problems]
        await update.message.reply_text("اختر المشكلة التي تم إصلاحها:", reply_markup=InlineKeyboardMarkup([buttons[i:i+2] for i in range(0, len(buttons), 2)]))
        return

    if text == "🚗 إدخال عدد الكيلومترات":
        driver = get_driver(user_id)
        if not driver or not driver["vehicle"]:
            await update.message.reply_text("يجب إكمال الملف أولاً.")
            return
        await update.message.reply_text(f"أرسل عدد الكيلومترات الحالي للمركبة {driver['vehicle']}:")
        context.user_data["expecting_km"] = True
        return

    # ----- actual reclamation or km entry -----
    if context.user_data.get("expecting_reclamation"):
        context.user_data.pop("expecting_reclamation")
        if not driver or not driver["name"] or not driver["vehicle"]:
            await update.message.reply_text("ملفك غير مكتمل.")
            return
        problem_id = add_problem(user_id, driver["name"], driver["vehicle"], text, "")
        report = f"السائق: {driver['name']}\nالمركبة: {driver['vehicle']}\nالمشكلة: {text}"
        await context.bot.send_message(chat_id=ADMIN_GROUP_ID, message_thread_id=TOPIC_RECLAMATIONS, text=report, reply_markup=build_problem_keyboard(problem_id))
        await update.message.reply_text("تم إرسال الشكوى.", reply_markup=DRIVER_KEYBOARD)
        return

    if context.user_data.get("expecting_km"):
        context.user_data.pop("expecting_km")
        if not driver or not driver["vehicle"]:
            await update.message.reply_text("ملف غير مكتمل.")
            return
        if not text.isdigit():
            await update.message.reply_text("يجب إرسال رقم.")
            return
        km = int(text)
        vehicle = driver["vehicle"]
        add_km_reading(vehicle, km)
        last_km = get_last_vidange_km(vehicle)
        if last_km > 0 and km >= last_km + 9000 and not has_active_vidange(vehicle):
            vidange_problem_id = add_problem(0, "نظام", vehicle, f"Vidange {vehicle}", "نظام")
            await context.bot.send_message(
                chat_id=ADMIN_GROUP_ID, message_thread_id=TOPIC_VIDANGE,
                text=f"⚠️ تنبيه فيدانج: المركبة {vehicle}\nالعداد الحالي: {km} كم\nآخر فيدانج: {last_km} كم",
                reply_markup=build_problem_keyboard(vidange_problem_id)
            )
        await update.message.reply_text(f"تم تسجيل العداد: {km} كم.", reply_markup=DRIVER_KEYBOARD)
        return

    # fallback
    await update.message.reply_text("استخدم الأزرار أدناه.", reply_markup=DRIVER_KEYBOARD)

# ----------------------------------------------------------------------
# Callback handlers
# ----------------------------------------------------------------------
async def vehicle_selection_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    vehicle = query.data.split("_", 1)[1]
    user_id = query.from_user.id
    set_driver(user_id, vehicle=vehicle, state="idle")
    await query.edit_message_text(f"تم تعيين المركبة إلى {vehicle}.")
    # Send the main driver keyboard as a new message
    await context.bot.send_message(chat_id=user_id, text="يمكنك الآن استخدام الأزرار أدناه:", reply_markup=DRIVER_KEYBOARD)

async def valide_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    problem_id = int(query.data.split("_")[1])
    problem = get_problem(problem_id)
    if not problem:
        await query.answer("المشكلة غير موجودة.")
        return
    if problem["status"] == "قيد الانتظار":
        new_status = "قيد التصليح"
        btn_text = "⏳ قيد الانتظار"
    else:
        new_status = "قيد الانتظار"
        btn_text = "🔧 قيد التصليح"
    update_problem_status(problem_id, status=new_status)
    rug_text = "🔧 تم الإصلاح" if problem["ruglee"] == "غير مُصلح" else "🔄 لم يتم الإصلاح"
    await query.edit_message_reply_markup(reply_markup=InlineKeyboardMarkup([
        [InlineKeyboardButton(btn_text, callback_data=f"val_{problem_id}"),
         InlineKeyboardButton(rug_text, callback_data=f"rug_{problem_id}")],
        [InlineKeyboardButton("💬 تعليق", callback_data=f"com_{problem_id}")],
        [InlineKeyboardButton("🗑️ حذف", callback_data=f"del_{problem_id}")]
    ]))

async def ruglee_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    if query.from_user.id not in ADMIN_IDS:
        await query.answer("⛔ غير مصرح.", show_alert=True)
        return
    problem_id = int(query.data.split("_")[1])
    problem = get_problem(problem_id)
    if not problem:
        await query.answer("غير موجود.")
        return
    new_ruglee = "تم الإصلاح" if problem["ruglee"] == "غير مُصلح" else "غير مُصلح"
    update_problem_status(problem_id, ruglee=new_ruglee)
    rug_text = "🔧 تم الإصلاح" if new_ruglee == "غير مُصلح" else "🔄 لم يتم الإصلاح"
    val_text = "🔧 قيد التصليح" if problem["status"] == "قيد الانتظار" else "⏳ قيد الانتظار"
    await query.edit_message_reply_markup(reply_markup=InlineKeyboardMarkup([
        [InlineKeyboardButton(val_text, callback_data=f"val_{problem_id}"),
         InlineKeyboardButton(rug_text, callback_data=f"rug_{problem_id}")],
        [InlineKeyboardButton("💬 تعليق", callback_data=f"com_{problem_id}")],
        [InlineKeyboardButton("🗑️ حذف", callback_data=f"del_{problem_id}")]
    ]))
    if problem["media_type"] == "نظام" and new_ruglee == "تم الإصلاح":
        req_id = problem.get("validation_requester") or problem.get("user_id")
        if req_id and req_id != 0:
            try:
                await context.bot.send_message(chat_id=req_id, text=f"تم تأكيد إصلاح الفيدانج للمركبة {problem['vehicle']}. الرجاء إدخال الكيلومترات الحالية:")
                # Mark that the user needs to send km
                context.application.bot_data.setdefault("km_await", {})[req_id] = problem["vehicle"]
            except Exception as e:
                logging.error(f"Failed to ask km: {e}")

async def comment_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    problem_id = int(query.data.split("_")[1])
    context.user_data["awaiting_comment"] = problem_id
    await context.bot.send_message(chat_id=query.from_user.id, text="📝 أرسل تعليقك على المشكلة:")
    await query.answer("أرسل التعليق في المحادثة الخاصة.", show_alert=True)

async def delete_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    if query.from_user.id not in ADMIN_IDS:
        await query.answer("⛔ غير مصرح.", show_alert=True)
        return
    problem_id = int(query.data.split("_")[1])
    delete_problem(problem_id)
    await query.edit_message_text("🗑️ تم حذف المشكلة.")

async def validation_request_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    problem_id = int(query.data.split("_")[1])
    problem = get_problem(problem_id)
    if not problem:
        await query.answer("غير موجود.")
        return
    update_problem_status(problem_id, validation_requester=query.from_user.id)
    driver = get_driver(query.from_user.id)
    driver_name = driver["name"] if driver else "Unknown"
    msg_text = f"📌 طلب تحقق من الإصلاح:\nالمشكلة #{problem_id} - {problem['problem_text']}\nالمركبة: {problem['vehicle']}\nالسائق: {driver_name}"
    await context.bot.send_message(
        chat_id=ADMIN_GROUP_ID, message_thread_id=TOPIC_VALIDATION,
        text=msg_text,
        reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("✅ تم الإصلاح", callback_data=f"rug_{problem_id}")]])
    )
    await query.edit_message_text("تم إرسال طلب التحقق.")

async def handle_km_input(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Handles km entry when the user was asked after vidange repair."""
    user_id = update.effective_user.id
    text = update.message.text.strip()
    if not text.isdigit():
        return
    km = int(text)
    await_data = context.application.bot_data.get("km_await", {})
    vehicle = await_data.pop(user_id, None)
    if vehicle:
        add_km_reading(vehicle, km)
        set_last_vidange_km(vehicle, km)
        await update.message.reply_text(f"✅ تم تحديث الفيدانج: {km} كم.", reply_markup=DRIVER_KEYBOARD)

async def vehicle_history_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    query = update.callback_query
    await query.answer()
    vehicle = query.data.split("_", 1)[1]
    conn = get_conn()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT * FROM problems WHERE vehicle=%s ORDER BY date DESC", (vehicle,))
    problems = [dict(r) for r in cur.fetchall()]
    cur.execute("SELECT date, km FROM km_readings WHERE vehicle=%s ORDER BY date DESC LIMIT 5", (vehicle,))
    readings = cur.fetchall()
    cur.close()
    conn.close()
    text = f"🚘 تاريخ المركبة {vehicle}:\n"
    if problems:
        text += "\n📋 المشاكل:\n"
        for p in problems:
            text += f"  #{p['id']} | {p['date']} | {p['problem_text'][:40]} | {p['status']} | {p['ruglee']}\n"
    else:
        text += "لا توجد مشاكل مسجلة.\n"
    if readings:
        text += "\n🛢️ آخر قراءات العداد:\n"
        for d, k in readings:
            text += f"  {d} - {k} كم\n"
    await context.bot.send_message(chat_id=ADMIN_GROUP_ID, message_thread_id=TOPIC_HISTORY, text=text)

# ----------------------------------------------------------------------
# Admin commands
# ----------------------------------------------------------------------
async def add_vehicle_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id not in ADMIN_IDS:
        return
    code = context.args[0] if context.args else None
    if not code:
        await update.message.reply_text("استخدم: /addvehicle CODE")
        return
    add_vehicle(code.upper())
    await context.bot.send_message(chat_id=ADMIN_GROUP_ID, message_thread_id=TOPIC_VEHICLE_MGMT, text=f"✅ تمت إضافة المركبة {code.upper()}.")

async def remove_vehicle_cmd(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if update.effective_user.id not in ADMIN_IDS:
        return
    code = context.args[0] if context.args else None
    if not code:
        await update.message.reply_text("استخدم: /removevehicle CODE")
        return
    remove_vehicle(code.upper())
    await context.bot.send_message(chat_id=ADMIN_GROUP_ID, message_thread_id=TOPIC_VEHICLE_MGMT, text=f"🗑️ تم حذف المركبة {code.upper()}.")

# ----------------------------------------------------------------------
# Export commands
# ----------------------------------------------------------------------
async def export_problems(update: Update, context: ContextTypes.DEFAULT_TYPE):
    file = generate_problems_excel()
    await update.message.reply_document(document=file, filename="المشاكل.xlsx")

async def export_vidange(update: Update, context: ContextTypes.DEFAULT_TYPE):
    file = generate_vidange_excel()
    await update.message.reply_document(document=file, filename="الفيدانج.xlsx")

# ----------------------------------------------------------------------
# Dashboard (daily)
# ----------------------------------------------------------------------
async def send_dashboard(context: ContextTypes.DEFAULT_TYPE):
    vehicles = get_all_vehicles()
    buttons = [InlineKeyboardButton(f"{status_emoji(v)} {v}", callback_data=f"hist_{v}") for v in vehicles]
    markup = InlineKeyboardMarkup([buttons[i:i+4] for i in range(0, len(buttons), 4)])
    await context.bot.send_message(
        chat_id=ADMIN_GROUP_ID, message_thread_id=TOPIC_GENERAL,
        text="📊 الحالة اليومية للمركبات:\n🟢 جيدة | 🟠 قيد المعالجة | 🔴 سيئة",
        reply_markup=markup
    )

async def weekly_excel(context: ContextTypes.DEFAULT_TYPE):
    file = generate_problems_excel()
    await context.bot.send_document(chat_id=ADMIN_GROUP_ID, message_thread_id=TOPIC_GENERAL, document=file, filename="المشاكل_الأسبوعي.xlsx")

def schedule_jobs(app: Application):
    now = datetime.now()
    t = time(7, 30, 0)
    # Daily dashboard
    next_daily = datetime.combine(now.date(), t)
    if now >= next_daily:
        next_daily += timedelta(days=1)
    app.job_queue.run_repeating(send_dashboard, interval=24*60*60, first=next_daily)
    # Weekly Excel (Saturday)
    days_until_sat = (5 - now.weekday()) % 7
    next_sat = datetime.combine(now.date() + timedelta(days=days_until_sat), t)
    if now >= next_sat:
        next_sat += timedelta(days=7)
    app.job_queue.run_repeating(weekly_excel, interval=7*24*60*60, first=next_sat)

# ----------------------------------------------------------------------
# Problem keyboard builder
# ----------------------------------------------------------------------
def build_problem_keyboard(problem_id: int) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("🔧 قيد التصليح", callback_data=f"val_{problem_id}"),
         InlineKeyboardButton("🔧 تم الإصلاح", callback_data=f"rug_{problem_id}")],
        [InlineKeyboardButton("💬 تعليق", callback_data=f"com_{problem_id}")],
        [InlineKeyboardButton("🗑️ حذف", callback_data=f"del_{problem_id}")]
    ])

# ----------------------------------------------------------------------
# Error handler
# ----------------------------------------------------------------------
async def error_handler(update: object, context: ContextTypes.DEFAULT_TYPE):
    logging.error(msg="Exception:", exc_info=context.error)

# ----------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------
def main():
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    init_db()

    app = Application.builder().token(BOT_TOKEN).build()

    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("addvehicle", add_vehicle_cmd))
    app.add_handler(CommandHandler("removevehicle", remove_vehicle_cmd))
    app.add_handler(CommandHandler("export", export_problems))
    app.add_handler(CommandHandler("export_vidange", export_vidange))

    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_km_input), group=1)
    app.add_handler(MessageHandler(filters.PHOTO | filters.VIDEO | filters.VOICE, handle_media))

    app.add_handler(CallbackQueryHandler(vehicle_selection_callback, pattern="^selv_"))
    app.add_handler(CallbackQueryHandler(valide_callback, pattern="^val_"))
    app.add_handler(CallbackQueryHandler(ruglee_callback, pattern="^rug_"))
    app.add_handler(CallbackQueryHandler(comment_callback, pattern="^com_"))
    app.add_handler(CallbackQueryHandler(delete_callback, pattern="^del_"))
    app.add_handler(CallbackQueryHandler(validation_request_callback, pattern="^valreq_"))
    app.add_handler(CallbackQueryHandler(vehicle_history_callback, pattern="^hist_"))

    app.add_error_handler(error_handler)

    schedule_jobs(app)

    logging.info("Bot polling started...")
    app.run_polling(stop_signals=[])

if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    flask_thread = threading.Thread(target=lambda: web_app.run(host="0.0.0.0", port=port), daemon=True)
    flask_thread.start()
    try:
        main()
    except KeyboardInterrupt:
        pass
    except Exception as e:
        logging.critical(f"Fatal: {e}", exc_info=True)
