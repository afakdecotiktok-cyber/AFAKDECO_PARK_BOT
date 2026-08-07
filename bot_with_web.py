import os, sys, logging, asyncio, threading
from datetime import datetime, time, timedelta
from io import BytesIO
from zoneinfo import ZoneInfo

import psycopg2, psycopg2.extras
from flask import Flask, request, jsonify
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill
from openpyxl.utils import get_column_letter

from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup, ReplyKeyboardMarkup, KeyboardButton
from telegram.ext import Application, CommandHandler, MessageHandler, CallbackQueryHandler, filters, ContextTypes

# ----------------------------------------------------------------------
# Flask app – webhook endpoint
# ----------------------------------------------------------------------
web_app = Flask(__name__)

# ----------------------------------------------------------------------
# Environment variables (Render)
# ----------------------------------------------------------------------
BOT_TOKEN = os.environ.get("BOT_TOKEN")
ADMIN_GROUP_ID_STR = os.environ.get("ADMIN_GROUP_ID")
ADMIN_IDS_STR = os.environ.get("ADMIN_IDS", "")
DATABASE_URL = os.environ.get("DATABASE_URL")
WEBHOOK_URL = os.environ.get("RENDER_EXTERNAL_URL")

TOPIC_RECLAMATIONS = int(os.environ.get("TOPIC_RECLAMATIONS", "0"))
TOPIC_VALIDATION = int(os.environ.get("TOPIC_VALIDATION", "0"))
TOPIC_VIDANGE = int(os.environ.get("TOPIC_VIDANGE", "0"))
TOPIC_VEHICLE_MGMT = int(os.environ.get("TOPIC_VEHICLE_MGMT", "0"))
TOPIC_GENERAL = int(os.environ.get("TOPIC_GENERAL", "0"))
TOPIC_HISTORY = int(os.environ.get("TOPIC_HISTORY", "0"))

if not all([BOT_TOKEN, ADMIN_GROUP_ID_STR, DATABASE_URL, WEBHOOK_URL]):
    sys.exit("FATAL: BOT_TOKEN, ADMIN_GROUP_ID, DATABASE_URL and WEBHOOK_URL must be set.")
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

# Algeria timezone
TZ = ZoneInfo("Africa/Algiers")

# ----------------------------------------------------------------------
# PostgreSQL helper (using Supabase Pooler connection)
# ----------------------------------------------------------------------
def get_conn():
    # Supabase connection via pooler (port 5432 or 6543)
    return psycopg2.connect(DATABASE_URL, sslmode='require')

def init_db():
    conn = get_conn()
    cur = conn.cursor()
    cur.execute('''
        CREATE TABLE IF NOT EXISTS drivers (
            user_id BIGINT PRIMARY KEY,
            name TEXT,
            vehicle TEXT,
            state TEXT,
            approval_status TEXT DEFAULT 'pending'
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
            validation_requester BIGINT DEFAULT 0,
            group_message_id BIGINT DEFAULT 0
        )
    ''')
    # Add columns if they don't exist
    for col, typ in [("validation_requester", "BIGINT DEFAULT 0"), ("group_message_id", "BIGINT DEFAULT 0")]:
        try:
            cur.execute(f"ALTER TABLE problems ADD COLUMN {col} {typ}")
            conn.commit()
        except Exception:
            conn.rollback()
    cur.execute('''
        CREATE TABLE IF NOT EXISTS allowed_users (
            user_id BIGINT PRIMARY KEY,
            status TEXT DEFAULT 'approved'
        )
    ''')
    cur.execute('''
        CREATE TABLE IF NOT EXISTS help_videos (
            id SERIAL PRIMARY KEY,
            file_id TEXT,
            description TEXT DEFAULT ''
        )
    ''')
    cur.execute('''
        CREATE TABLE IF NOT EXISTS km_readings (
            id SERIAL PRIMARY KEY,
            vehicle TEXT,
            km INTEGER,
            date TEXT,
            driver_name TEXT DEFAULT ''
        )
    ''')
    cur.execute('''
        CREATE TABLE IF NOT EXISTS vehicle_vidange (
            vehicle TEXT PRIMARY KEY,
            last_vidange_km INTEGER DEFAULT 0
        )
    ''')
    cur.execute("SELECT code FROM vehicles")
    for v in [r[0] for r in cur.fetchall()]:
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
    cur.execute("SELECT name, vehicle, state, approval_status FROM drivers WHERE user_id = %s", (user_id,))
    row = cur.fetchone()
    cur.close()
    conn.close()
    return dict(row) if row else None

def set_driver(user_id: int, name=None, vehicle=None, state=None, approval_status=None):
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
        if approval_status is not None:
            cur.execute("UPDATE drivers SET approval_status=%s WHERE user_id=%s", (approval_status, user_id))
    else:
        cur.execute("INSERT INTO drivers (user_id, name, vehicle, state, approval_status) VALUES (%s,%s,%s,%s,%s)",
                    (user_id, name or "", vehicle or "", state or "name_entry", approval_status or "pending"))
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

def add_problem(user_id: int, driver_name: str, vehicle: str, problem_text: str, media_type: str, group_msg_id: int = 0) -> int:
    conn = get_conn()
    cur = conn.cursor()
    date = datetime.now(TZ).strftime("%Y-%m-%d %H:%M:%S")
    cur.execute(
        "INSERT INTO problems (user_id, driver_name, vehicle, problem_text, media_type, date, group_message_id) VALUES (%s,%s,%s,%s,%s,%s,%s) RETURNING id",
        (user_id, driver_name, vehicle, problem_text, media_type, date, group_msg_id)
    )
    problem_id = cur.fetchone()[0]
    conn.commit()
    cur.close()
    conn.close()
    return problem_id

def update_problem_status(problem_id: int, status=None, ruglee=None, validation_requester=None, group_message_id=None):
    conn = get_conn()
    cur = conn.cursor()
    if status is not None:
        cur.execute("UPDATE problems SET status=%s WHERE id=%s", (status, problem_id))
    if ruglee is not None:
        cur.execute("UPDATE problems SET ruglee=%s WHERE id=%s", (ruglee, problem_id))
    if validation_requester is not None:
        cur.execute("UPDATE problems SET validation_requester=%s WHERE id=%s", (validation_requester, problem_id))
    if group_message_id is not None:
        cur.execute("UPDATE problems SET group_message_id=%s WHERE id=%s", (group_message_id, problem_id))
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

def add_km_reading(vehicle: str, km: int, driver_name: str = ""):
    conn = get_conn()
    cur = conn.cursor()
    date = datetime.now(TZ).strftime("%Y-%m-%d %H:%M:%S")
    cur.execute("INSERT INTO km_readings (vehicle, km, date, driver_name) VALUES (%s,%s,%s,%s)", (vehicle, km, date, driver_name))
    conn.commit()
    cur.close()
    conn.close()

def get_latest_km(vehicle: str) -> int | None:
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("SELECT km FROM km_readings WHERE vehicle=%s ORDER BY date DESC LIMIT 1", (vehicle,))
    row = cur.fetchone()
    cur.close()
    conn.close()
    return row[0] if row else None

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
    cur.execute("SELECT COUNT(*) FROM problems WHERE vehicle=%s AND status='قيد الانتظار' AND ruglee != 'تم الإصلاح'", (vehicle,))
    if cur.fetchone()[0] > 0: return 'bad'
    last_km = get_latest_km(vehicle)
    if last_km:
        last_vid = get_last_vidange_km(vehicle)
        if last_vid > 0 and last_km >= last_vid + 9500: return 'bad'
    cur.execute("SELECT COUNT(*) FROM problems WHERE vehicle=%s AND status='قيد التصليح' AND ruglee != 'تم الإصلاح'", (vehicle,))
    if cur.fetchone()[0] > 0: return 'en_cours'
    return 'good'

def count_open_problems(vehicle: str) -> int:
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("SELECT COUNT(*) FROM problems WHERE vehicle=%s AND ruglee != 'تم الإصلاح'", (vehicle,))
    cnt = cur.fetchone()[0]
    cur.close()
    conn.close()
    return cnt

def get_remaining_km(vehicle: str) -> int | str:
    last_km = get_latest_km(vehicle)
    if last_km:
        last_vid = get_last_vidange_km(vehicle)
        if last_vid > 0:
            return (last_vid + 10000) - last_km
    return "—"

def add_help_video(file_id: str, description: str = ""):
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("INSERT INTO help_videos (file_id, description) VALUES (%s,%s)", (file_id, description))
    conn.commit()
    cur.close()
    conn.close()

def get_all_help_videos():
    conn = get_conn()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT * FROM help_videos ORDER BY id DESC")
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return [dict(r) for r in rows]

def delete_help_video(video_id: int):
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("DELETE FROM help_videos WHERE id=%s", (video_id,))
    conn.commit()
    cur.close()
    conn.close()

def get_help_video(video_id: int) -> dict | None:
    conn = get_conn()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT * FROM help_videos WHERE id=%s", (video_id,))
    row = cur.fetchone()
    cur.close()
    conn.close()
    return dict(row) if row else None

def add_allowed_user(user_id: int, status: str = "approved"):
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("INSERT INTO allowed_users (user_id, status) VALUES (%s,%s) ON CONFLICT (user_id) DO UPDATE SET status=%s", (user_id, status, status))
    conn.commit()
    cur.close()
    conn.close()

def is_allowed(user_id: int) -> bool:
    conn = get_conn()
    cur = conn.cursor()
    cur.execute("SELECT status FROM allowed_users WHERE user_id=%s", (user_id,))
    row = cur.fetchone()
    cur.close()
    conn.close()
    return row is not None and row[0] == 'approved'

def get_all_drivers():
    conn = get_conn()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT user_id, name, vehicle FROM drivers")
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return [dict(r) for r in rows]

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
    red_fill = PatternFill(start_color="FFCCCC", end_color="FFCCCC", fill_type="solid")
    orange_fill = PatternFill(start_color="FFE5CC", end_color="FFE5CC", fill_type="solid")
    green_fill = PatternFill(start_color="CCFFCC", end_color="CCFFCC", fill_type="solid")
    for row_idx, p in enumerate(problems, 2):
        if p["ruglee"] == "تم الإصلاح":
            row_fill = green_fill
        elif p["status"] == "قيد الانتظار":
            row_fill = red_fill
        elif p["status"] == "قيد التصليح":
            row_fill = orange_fill
        else:
            row_fill = None
        vals = [p["date"], p["driver_name"], p["vehicle"], p["problem_text"], p["media_type"] or "—",
                p["status"], p["ruglee"], p["comments"] or ""]
        for ci, val in enumerate(vals, 1):
            cell = ws.cell(row=row_idx, column=ci, value=val)
            if row_fill:
                cell.fill = row_fill
    for col in ws.columns:
        max_len = max((len(str(c.value)) for c in col if c.value), default=0)
        ws.column_dimensions[get_column_letter(col[0].column)].width = min(max_len+2, 50)
    out = BytesIO()
    wb.save(out)
    out.seek(0)
    return out

def generate_vidange_excel(vehicle_code: str = None) -> BytesIO:
    vehicles = [vehicle_code] if vehicle_code else get_all_vehicles()
    wb = Workbook()
    wb.remove(wb.active)
    for v in vehicles:
        ws = wb.create_sheet(title=v)
        ws.append(["التاريخ", "السائق", "العداد الحالي (KM)", "آخر فيدانج (KM)", "المسافة المتبقية للفيدانج"])
        conn = get_conn()
        cur = conn.cursor()
        cur.execute("SELECT date, km, driver_name FROM km_readings WHERE vehicle=%s ORDER BY date DESC", (v,))
        readings = cur.fetchall()
        last_km = get_last_vidange_km(v)
        for date_str, km, dname in readings:
            remaining = (last_km + 10000) - km if last_km > 0 else "—"
            ws.append([date_str, dname or "", km, last_km, remaining])
        cur.close()
        conn.close()
        for col in ws.columns:
            max_len = max((len(str(c.value)) for c in col if c.value), default=0)
            ws.column_dimensions[get_column_letter(col[0].column)].width = min(max_len+2, 50)
    out = BytesIO()
    wb.save(out)
    out.seek(0)
    return out

# ----------------------------------------------------------------------
# Keyboards
# ----------------------------------------------------------------------
MAIN_KEYBOARD = ReplyKeyboardMarkup([
    [KeyboardButton("📝 تقديم شكوى"), KeyboardButton("✅ طلب التحقق من الإصلاح")],
    [KeyboardButton("🚗 إدخال عدد الكيلومترات"), KeyboardButton("⚙️ الإعدادات")]
], resize_keyboard=True)

def vehicle_inline_keyboard(vehicles: list, prefix="selv_") -> InlineKeyboardMarkup:
    buttons = [InlineKeyboardButton(v, callback_data=f"{prefix}{v}") for v in vehicles]
    return InlineKeyboardMarkup([buttons[i:i+4] for i in range(0, len(buttons), 4)])

def status_emoji(vehicle: str) -> str:
    s = get_vehicle_status(vehicle)
    if s == 'bad': return "🔴"
    if s == 'en_cours': return "🟠"
    return "🟢"

def dashboard_button_text(vehicle: str) -> str:
    emoji = status_emoji(vehicle)
    cnt = count_open_problems(vehicle)
    rem = get_remaining_km(vehicle)
    line1 = f"{emoji} {vehicle} ({cnt})"
    line2 = f"   {rem} كم" if isinstance(rem, int) else "   —"
    return f"{line1}\n{line2}"

# Admin submenus
def admin_main_keyboard() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("🚘 تعديل المركبات", callback_data="admin_vehicles")],
        [InlineKeyboardButton("👤 إدارة السائقين", callback_data="admin_drivers")],
        [InlineKeyboardButton("🛢️ إدارة الفيدانج", callback_data="admin_vidange_menu")],
        [InlineKeyboardButton("📊 لوحة القيادة", callback_data="admin_dash")],
        [InlineKeyboardButton("📋 تصدير Excel", callback_data="admin_export_menu")],
    ])

def admin_vehicles_keyboard() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("➕ إضافة مركبة", callback_data="admin_addveh"),
         InlineKeyboardButton("➖ حذف مركبة", callback_data="admin_remveh")],
        [InlineKeyboardButton("↩️ رجوع", callback_data="admin_main")]
    ])

def admin_drivers_keyboard() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("✅ قبول سائقين", callback_data="admin_approve_list")],
        [InlineKeyboardButton("❌ حذف سائق", callback_data="admin_remove_driver_list")],
        [InlineKeyboardButton("↩️ رجوع", callback_data="admin_main")]
    ])

def admin_vidange_menu_keyboard() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("⚙️ تعيين فيدانج", callback_data="admin_setvid")],
        [InlineKeyboardButton("🚨 فيدانج عاجل", callback_data="admin_urgentvid")],
        [InlineKeyboardButton("↩️ رجوع", callback_data="admin_main")]
    ])

def admin_export_menu_keyboard() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("📋 تصدير المشاكل", callback_data="admin_export")],
        [InlineKeyboardButton("🛢️ تصدير الفيدانج", callback_data="admin_vid")],
        [InlineKeyboardButton("↩️ رجوع", callback_data="admin_main")]
    ])

TOPIC_ACTIONS = {
    TOPIC_GENERAL: [
        [InlineKeyboardButton("📊 لوحة القيادة", callback_data="admin_dash")],
        [InlineKeyboardButton("📋 تصدير المشاكل", callback_data="admin_export")],
        [InlineKeyboardButton("🛢️ تصدير الفيدانج", callback_data="admin_vid")],
    ],
    TOPIC_RECLAMATIONS: [
        [InlineKeyboardButton("📊 لوحة القيادة", callback_data="admin_dash")],
        [InlineKeyboardButton("📋 تصدير المشاكل", callback_data="admin_export")],
    ],
    TOPIC_VALIDATION: [
        [InlineKeyboardButton("📊 لوحة القيادة", callback_data="admin_dash")],
        [InlineKeyboardButton("📋 تصدير المشاكل", callback_data="admin_export")],
    ],
    TOPIC_VIDANGE: [
        [InlineKeyboardButton("🛢️ تصدير الفيدانج", callback_data="admin_vid")],
        [InlineKeyboardButton("🚨 طلب فيدانج عاجل", callback_data="admin_urgentvid")],
        [InlineKeyboardButton("📋 تصدير المشاكل", callback_data="admin_export")],
    ],
    TOPIC_VEHICLE_MGMT: [
        [InlineKeyboardButton("➕ إضافة مركبة", callback_data="admin_addveh")],
        [InlineKeyboardButton("➖ حذف مركبة", callback_data="admin_remveh")],
        [InlineKeyboardButton("🚘 قائمة المركبات", callback_data="admin_listveh")],
    ],
    TOPIC_HISTORY: [
        [InlineKeyboardButton("📊 لوحة القيادة", callback_data="admin_dash")],
    ],
}

def get_topic_keyboard(thread_id: int) -> InlineKeyboardMarkup | None:
    actions = TOPIC_ACTIONS.get(thread_id)
    if actions:
        return InlineKeyboardMarkup(actions)
    return None

# ----------------------------------------------------------------------
# Webhook
# ----------------------------------------------------------------------
async def set_webhook(app: Application):
    webhook_url = f"{WEBHOOK_URL}/telegram"
    await app.bot.set_webhook(url=webhook_url)
    logging.info(f"Webhook set to {webhook_url}")

@web_app.route('/telegram', methods=['POST'])
async def telegram_webhook():
    data = request.get_json()
    update = Update.de_json(data, app.bot)
    await app.process_update(update)
    return jsonify({"status": "ok"})

@web_app.route('/')
def home():
    return "Bot is running."

# ----------------------------------------------------------------------
# Status helpers
# ----------------------------------------------------------------------
def status_icon_and_text(problem: dict) -> str:
    if problem["ruglee"] == "تم الإصلاح":
        return "🟢 مُصلح"
    if problem["status"] == "قيد الانتظار":
        return "🔴 قيد الانتظار"
    if problem["status"] == "قيد التصليح":
        return "🟠 قيد التصليح"
    return "⚪ حالة غير معروفة"

def build_problem_keyboard(problem_id: int, initial: bool = False) -> InlineKeyboardMarkup:
    if problem_id == 0:
        return InlineKeyboardMarkup([])
    problem = get_problem(problem_id)
    if not problem:
        return InlineKeyboardMarkup([])
    status = problem["status"]
    ruglee = problem["ruglee"]
    row1 = []
    if status == "قيد الانتظار":
        row1.append(InlineKeyboardButton("🔧 قيد التصليح", callback_data=f"val_{problem_id}"))
    elif status == "قيد التصليح":
        row1.append(InlineKeyboardButton("⏳ إعادة للانتظار", callback_data=f"val_{problem_id}"))
        if problem["media_type"] and not problem["comments"]:
            row1.append(InlineKeyboardButton("✅ تم الإصلاح (تعليق مطلوب)", callback_data=f"fix_comment_{problem_id}"))
        else:
            row1.append(InlineKeyboardButton("✅ تم الإصلاح", callback_data=f"rug_{problem_id}"))
    rows = []
    if row1:
        rows.append(row1)
    rows.append([InlineKeyboardButton("💬 تعليق", callback_data=f"com_{problem_id}")])
    if ruglee != "تم الإصلاح":
        rows.append([InlineKeyboardButton("🗑️ حذف", callback_data=f"del_{problem_id}")])
    return InlineKeyboardMarkup(rows)

# ----------------------------------------------------------------------
# Handlers (abbreviated, full version below)
# ----------------------------------------------------------------------
async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    if user_id in ADMIN_IDS:
        add_allowed_user(user_id)
        set_driver(user_id, approval_status="approved")
    driver = get_driver(user_id)
    if driver and driver["name"] and driver["vehicle"] and driver.get("approval_status") == "approved":
        if driver["state"] != "idle":
            set_driver(user_id, state="idle")
        await update.message.reply_text(
            f"أهلاً بعودتك، {driver['name']}!\nمركبتك: {driver['vehicle']}",
            reply_markup=MAIN_KEYBOARD
        )
    elif driver and driver.get("approval_status") == "pending":
        await update.message.reply_text("شكراً لتسجيلك. طلب صلاحيتك قيد المراجعة. انتظر قبول المشرف.")
    else:
        set_driver(user_id, state="name_entry", approval_status="pending")
        await update.message.reply_text("مرحباً! الرجاء إدخال اسمك الكامل:")

async def handle_text(update: Update, context: ContextTypes.DEFAULT_TYPE):
    user_id = update.effective_user.id
    text = update.message.text.strip()
    driver = get_driver(user_id)
    state = driver["state"] if driver else "name_entry"

    # Block non-allowed users (unless super admin)
    if user_id not in ADMIN_IDS and not is_allowed(user_id):
        if state == "name_entry":
            set_driver(user_id, name=text, state="awaiting_approval", approval_status="pending")
            username = update.effective_user.username
            mention = f"@{username}" if username else f"[{text}](tg://user?id={user_id})"
            msg = await context.bot.send_message(
                chat_id=ADMIN_GROUP_ID,
                message_thread_id=TOPIC_VALIDATION,
                text=f"📌 طلب صلاحية جديدة:\nالاسم: {text}\nالمستخدم: {mention}\nالحالة: ⏳ قيد الانتظار",
                reply_markup=InlineKeyboardMarkup([
                    [InlineKeyboardButton("✅ قبول", callback_data=f"approve_{user_id}"),
                     InlineKeyboardButton("❌ رفض", callback_data=f"reject_{user_id}")]
                ])
            )
            context.bot_data.setdefault("approval_msg", {})[user_id] = msg.message_id
            await update.message.reply_text("تم إرسال طلبك للمراجعة. ستصلك رسالة عند القبول.")
            return
        else:
            await update.message.reply_text("غير مصرح لك باستخدام البوت حالياً.")
            return

    # comment session
    if context.user_data.get("awaiting_comment"):
        problem_id = context.user_data.pop("awaiting_comment")
        set_problem_comment(problem_id, text)
        await update.message.reply_text("✅ تم حفظ التعليق بنجاح.", reply_markup=MAIN_KEYBOARD)
        return

    # km after vidange repair
    if context.user_data.get("await_km"):
        vehicle = context.user_data["await_km_vehicle"]
        if text.isdigit():
            km = int(text)
            last_km = get_latest_km(vehicle)
            if last_km is not None and km <= last_km:
                await update.message.reply_text(f"⚠️ الكيلومتر يجب أن يكون أكبر من آخر قراءة ({last_km} كم). أعد إدخال القيمة الصحيحة.")
                return
            driver_name = driver["name"] if driver else "Unknown"
            msg = await context.bot.send_message(
                chat_id=ADMIN_GROUP_ID,
                message_thread_id=TOPIC_VIDANGE,
                text=f"⚙️ تأكيد تحديث الفيدانج:\nالمركبة: {vehicle}\nالقيمة المدخلة: {km} كم\nالسائق: {driver_name}\nالحالة: ⏳ في انتظار التأكيد",
                reply_markup=InlineKeyboardMarkup([
                    [InlineKeyboardButton("✅ تأكيد", callback_data=f"vidconfirm_{user_id}_{km}"),
                     InlineKeyboardButton("✏️ تعديل", callback_data=f"vidmodify_{user_id}")]
                ])
            )
            context.bot_data.setdefault("pending_vidange", {})[msg.message_id] = {
                "user_id": user_id,
                "vehicle": vehicle,
                "km": km
            }
            await update.message.reply_text("تم إرسال القيمة للمراجعة من قبل المشرفين.", reply_markup=MAIN_KEYBOARD)
            context.user_data.pop("await_km_vehicle", None)
            context.user_data.clear()
            return
        else:
            await update.message.reply_text("الرجاء إرسال رقم صحيح.")
            return

    # state machine
    if state == "name_entry":
        set_driver(user_id, name=text, state="vehicle_selection")
        vehicles = get_all_vehicles()
        await update.message.reply_text("تم حفظ الاسم. اختر مركبتك:", reply_markup=vehicle_inline_keyboard(vehicles, "selv_"))
        return

    if state == "vehicle_selection":
        vehicles = get_all_vehicles()
        await update.message.reply_text("الرجاء اختيار المركبة من القائمة:", reply_markup=vehicle_inline_keyboard(vehicles, "selv_"))
        return

    # Main keyboard buttons (identical to previous version, just calling correct functions)
    # ... (full implementation in final file)

# ----------------------------------------------------------------------
# The complete code would continue with all handlers for media, callbacks, admin submenus, etc.
# Due to length, I'll provide the full file in a final message after you confirm the move to Supabase.
# ----------------------------------------------------------------------

def main():
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
    init_db()

    global app
    app = Application.builder().token(BOT_TOKEN).build()

    # Register all handlers (final version will include all)
    # ...

    loop.run_until_complete(set_webhook(app))
    port = int(os.environ.get("PORT", 5000))
    web_app.run(host="0.0.0.0", port=port)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
    except Exception as e:
        logging.critical(f"Fatal: {e}", exc_info=True)
