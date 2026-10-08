import logging
from datetime import datetime, timedelta
from io import BytesIO
from telegram import InlineKeyboardButton, InlineKeyboardMarkup, ReplyKeyboardMarkup, KeyboardButton
from telegram.ext import MessageHandler, CommandHandler, filters

INSTALLED = False
MAIN = None

MEDIA_TTL_DAYS = 30

def _now(main):
    return datetime.now(main.TZ)

def _insert_accident(main, user_id, driver_name, vehicle, description, message_id):
    with main.db_connection() as conn:
        cur = conn.cursor()
        now = _now(main)
        created = now.strftime("%Y-%m-%d %H:%M:%S")
        cur.execute(
            """INSERT INTO problems
               (user_id, driver_name, vehicle, problem_text, media_type, date,
                group_message_id, problem_type, telegram_chat_id, telegram_thread_id)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
               RETURNING id""",
            (user_id, driver_name, vehicle, description, "حادث",
             created, message_id, "accident", main.ADMIN_GROUP_ID,
             main.TOPIC_ACCIDENT),
        )
        problem_id = cur.fetchone()[0]
        conn.commit()
    main.invalidate_cache(vehicle)
    return problem_id

def _insert_media(main, problem_id, media_type, file_id, message_id):
    with main.db_connection() as conn:
        cur = conn.cursor()
        now = _now(main)
        created = now.strftime("%Y-%m-%d %H:%M:%S")
        expires = (now + timedelta(days=MEDIA_TTL_DAYS)).strftime("%Y-%m-%d %H:%M:%S")
        cur.execute(
            """INSERT INTO problem_media
               (problem_id, media_type, telegram_file_id, telegram_message_id,
                telegram_chat_id, created_at, expires_at)
               VALUES (%s,%s,%s,%s,%s,%s,%s)
               RETURNING id""",
            (problem_id, media_type, file_id, message_id,
             main.ADMIN_GROUP_ID, created, expires),
        )
        media_id = cur.fetchone()[0]
        conn.commit()
    return media_id

def _get_media(main, media_id, problem_id=None):
    with main.db_connection() as conn:
        cur = conn.cursor(cursor_factory=main.psycopg2.extras.RealDictCursor)
        if problem_id is None:
            cur.execute("SELECT * FROM problem_media WHERE id=%s", (media_id,))
        else:
            cur.execute("SELECT * FROM problem_media WHERE id=%s AND problem_id=%s", (media_id, problem_id))
        row = cur.fetchone()
        return dict(row) if row else None

def _update_problem_telegram(main, problem_id, message_id):
    with main.db_connection() as conn:
        cur = conn.cursor()
        cur.execute(
            "UPDATE problems SET group_message_id=%s, telegram_chat_id=%s, telegram_thread_id=%s, problem_type='accident' WHERE id=%s",
            (message_id, main.ADMIN_GROUP_ID, main.TOPIC_ACCIDENT, problem_id),
        )
        conn.commit()
    p = main.get_problem(problem_id)
    if p:
        main.invalidate_cache(p["vehicle"])

async def _convert_problem_to_accident(main, request):
    admin = await main.require_auth(request)
    try:
        problem_id = int(request.match_info["id"])
    except (TypeError, ValueError):
        return main.json_err("رقم المشكلة غير صالح")

    problem = await main.run_db(main.get_problem, problem_id)
    if not problem:
        return main.json_err("المشكلة غير موجودة", status=404)
    if problem.get("problem_type") == "accident":
        return main.json_ok(problem, changed_by=admin["user_id"], already_accident=True)

    copied_id = None
    if problem.get("group_message_id"):
        try:
            copied = await main.app.bot.copy_message(
                chat_id=main.ADMIN_GROUP_ID,
                from_chat_id=problem.get("telegram_chat_id") or main.ADMIN_GROUP_ID,
                message_id=problem["group_message_id"],
                message_thread_id=main.TOPIC_ACCIDENT,
            )
            copied_id = copied.message_id
        except Exception as exc:
            logging.warning("Could not copy original problem #%s to accident topic: %s", problem_id, exc)

    if copied_id:
        await main.run_db(_update_problem_telegram, main, problem_id, copied_id)
    else:
        await main.run_db(main._set_problem_type, problem_id, "accident")

    updated = await main.run_db(main.get_problem, problem_id)
    if copied_id:
        try:
            await main.app.bot.edit_message_reply_markup(
                chat_id=main.ADMIN_GROUP_ID,
                message_id=copied_id,
                reply_markup=await main.run_db(main.build_problem_keyboard, problem_id),
            )
        except Exception:
            pass
    return main.json_ok(updated, changed_by=admin["user_id"], copied_message_id=copied_id)

def _replace_keyboard(main):
    main.MAIN_KEYBOARD = ReplyKeyboardMarkup(
        [
            [KeyboardButton("📝 تقديم شكوى"), KeyboardButton("🟣 حادث"), KeyboardButton("✅ طلب التحقق من الإصلاح")],
            [KeyboardButton("🚗 إدخال عدد الكيلومترات"), KeyboardButton("⚙️ الإعدادات")],
        ],
        resize_keyboard=True,
    )

async def accident_start(update, context):
    user_id = update.effective_user.id
    if update.effective_chat.type != "private":
        return
    driver = await MAIN.run_db(MAIN.get_driver, user_id)
    if not driver or not driver.get("name") or not driver.get("vehicle") or driver.get("approval_status") != "approved":
        await update.message.reply_text("ملفك غير مكتمل.")
        return
    context.user_data.pop("accident_draft", None)
    context.user_data["accident_stage"] = "description"
    await update.message.reply_text(
        "🟣 تسجيل حادث\nأرسل وصف الحادث الآن. بعد ذلك أرسل صورة أو فيديو واحداً أو أكثر، وعند الانتهاء أرسل /done.",
        reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton("إلغاء", callback_data="cancel_input")]]),
    )

async def accident_text(update, context):
    if update.effective_chat.type != "private":
        return
    if not context.user_data.get("accident_stage"):
        return
    text = (update.message.text or "").strip()
    if not text:
        return
    if text == "🟣 حادث":
        await accident_start(update, context)
        return
    if context.user_data.get("accident_stage") != "description":
        return
    driver = await MAIN.run_db(MAIN.get_driver, update.effective_user.id)
    if not driver or not driver.get("vehicle"):
        context.user_data.pop("accident_stage", None)
        await update.message.reply_text("ملفك غير مكتمل.", reply_markup=MAIN.MAIN_KEYBOARD)
        return
    context.user_data["accident_draft"] = {
        "user_id": update.effective_user.id,
        "driver_name": driver["name"],
        "vehicle": driver["vehicle"],
        "description": text,
        "media_ids": [],
    }
    context.user_data["accident_stage"] = "media"
    await update.message.reply_text(
        "تم حفظ وصف الحادث. الآن أرسل صورة أو فيديو واحداً أو أكثر. عند الانتهاء أرسل /done.",
        reply_markup=MAIN.MAIN_KEYBOARD,
    )

async def accident_media(update, context):
    if update.effective_chat.type != "private":
        return
    if context.user_data.get("accident_stage") != "media":
        return
    draft = context.user_data.get("accident_draft")
    if not draft:
        return

    msg = update.message
    file_id = None
    media_type = None
    send_kwargs = {}
    if msg.photo:
        file_id = msg.photo[-1].file_id
        media_type = "صورة"
        send_kwargs["photo"] = file_id
    elif msg.video:
        file_id = msg.video.file_id
        media_type = "فيديو"
        send_kwargs["video"] = file_id
    else:
        return

    problem_id = draft.get("problem_id")
    if not problem_id:
        header = (
            f"🟣 حادث جديد\nالسائق: {draft['driver_name']}\n"
            f"المركبة: {draft['vehicle']}\nالحادث: {draft['description']}\n"
            "الحالة: 🔴 قيد الانتظار"
        )
        first = await context.bot.send_message(
            chat_id=MAIN.ADMIN_GROUP_ID,
            message_thread_id=MAIN.TOPIC_ACCIDENT,
            text=header,
        )
        problem_id = await MAIN.run_db(
            _insert_accident, MAIN, draft["user_id"], draft["driver_name"],
            draft["vehicle"], draft["description"], first.message_id
        )
        draft["problem_id"] = problem_id

    caption = f"🟣 حادث #{problem_id} — {media_type}"
    if media_type == "صورة":
        media_msg = await context.bot.send_photo(
            chat_id=MAIN.ADMIN_GROUP_ID,
            message_thread_id=MAIN.TOPIC_ACCIDENT,
            photo=file_id,
            caption=caption,
        )
    else:
        media_msg = await context.bot.send_video(
            chat_id=MAIN.ADMIN_GROUP_ID,
            message_thread_id=MAIN.TOPIC_ACCIDENT,
            video=file_id,
            caption=caption,
        )
    media_id = await MAIN.run_db(
        _insert_media, MAIN, problem_id, media_type, file_id, media_msg.message_id
    )
    draft["media_ids"].append(media_id)
    await update.message.reply_text(
        f"تم حفظ {media_type}. يمكنك إرسال المزيد أو /done.",
        reply_markup=MAIN.MAIN_KEYBOARD,
    )

async def accident_done(update, context):
    if update.effective_chat.type != "private":
        return
    if not context.user_data.get("accident_stage"):
        return
    draft = context.user_data.get("accident_draft")
    if not draft or not draft.get("problem_id") or not draft.get("media_ids"):
        await update.message.reply_text("يجب إرسال صورة أو فيديو واحد على الأقل قبل /done.")
        return
    problem_id = draft["problem_id"]
    count = len(draft["media_ids"])
    context.user_data.pop("accident_stage", None)
    context.user_data.pop("accident_draft", None)
    await update.message.reply_text(
        f"✅ تم تسجيل الحادث #{problem_id} وإرسال {count} ملف(ات) إلى قسم الحوادث.",
        reply_markup=MAIN.MAIN_KEYBOARD,
    )

async def accident_media_proxy(request):
    await MAIN.require_auth(request)
    try:
        problem_id = int(request.match_info["id"])
        media_id = int(request.match_info["media_id"])
    except (TypeError, ValueError):
        return MAIN.json_err("المعرّفات غير صالحة")

    media = await MAIN.run_db(_get_media, MAIN, media_id, problem_id)
    if not media:
        return MAIN.json_err("الوسيط غير موجود", status=404)

    now = _now(MAIN)
    expires = datetime.strptime(media["expires_at"], "%Y-%m-%d %H:%M:%S").replace(tzinfo=MAIN.TZ)
    if now >= expires:
        return MAIN.web.json_response(
            {"ok": True, "archived": True, "available_in_app": False,
             "telegram_url": MAIN.telegram_message_url(media.get("telegram_chat_id"), media.get("telegram_message_id"))}
        )

    file_id = media.get("telegram_file_id")
    if not file_id:
        return MAIN.json_err("الملف غير متاح", status=404)
    try:
        tg_file = await MAIN.app.bot.get_file(file_id)
        buf = BytesIO()
        await tg_file.download_to_memory(out=buf)
        body = buf.getvalue()
    except Exception as exc:
        logging.warning("Telegram media download failed for media #%s: %s", media_id, exc)
        return MAIN.json_err("تعذر جلب الوسيط من Telegram", status=502)

    content_type = "image/jpeg" if media["media_type"] == "صورة" else "video/mp4"
    return MAIN.web.Response(body=body, content_type=content_type, headers={"Cache-Control": "private, max-age=300"})

def install(main):
    global MAIN, INSTALLED
    if INSTALLED:
        return
    MAIN = main
    _replace_keyboard(main)

    # Register accident handlers before the normal private handlers.
    main.app.add_handler(CommandHandler("done", accident_done), group=-1)
    main.app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND & filters.ChatType.PRIVATE, accident_text), group=-1)
    main.app.add_handler(MessageHandler((filters.PHOTO | filters.VIDEO) & filters.ChatType.PRIVATE, accident_media), group=-1)

    # The existing route is replaced so conversion also moves the Telegram representation.
    main.api_problem_convert_accident = lambda request: _convert_problem_to_accident(main, request)

    original_register = main.register_api_routes
    def register_with_media(api):
        original_register(api)
        api.router.add_get("/api/problems/{id}/media/{media_id}", accident_media_proxy)
    main.register_api_routes = register_with_media

    INSTALLED = True
