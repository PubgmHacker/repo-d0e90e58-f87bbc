"""
RaveClone — Полный отчёт об аудите (155 багов)
Generator: ReportLab, A4, русский язык.
Output: /home/z/my-project/download/RaveClone_Audit_Report.pdf
"""

import os
import sys
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm, mm
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, PageBreak, Table, TableStyle,
    KeepTogether, ListFlowable, ListItem, Preformatted
)
from reportlab.platypus.flowables import HRFlowable
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.enums import TA_LEFT, TA_CENTER, TA_RIGHT, TA_JUSTIFY

# ─── Fonts (Cyrillic support) ──────────────────────────────────────────────
FONT_PATHS = {
    "BodyR": "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "BodyB": "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "BodyI": "/usr/share/fonts/truetype/dejavu/DejaVuSans-Oblique.ttf",
    "Mono":  "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    "MonoB": "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
}
for name, path in FONT_PATHS.items():
    if os.path.exists(path):
        pdfmetrics.registerFont(TTFont(name, path))
    else:
        print(f"[warn] font missing: {path}")

# ─── Palette (rave-themed dark) ────────────────────────────────────────────
PAGE_BG       = colors.HexColor('#0b0b0a')
SECTION_BG    = colors.HexColor('#1f1f1c')
CARD_BG       = colors.HexColor('#2a2925')
TABLE_STRIPE  = colors.HexColor('#171613')
HEADER_FILL   = colors.HexColor('#554d36')
BORDER        = colors.HexColor('#5f5a48')
ACCENT        = colors.HexColor('#e6cb77')   # gold
ACCENT_2      = colors.HexColor('#59a3bc')   # cyan
TEXT_PRIMARY  = colors.HexColor('#eaeae8')
TEXT_MUTED    = colors.HexColor('#94918b')

# Severity colors
SEV_CRIT      = colors.HexColor('#c62828')   # red
SEV_HIGH      = colors.HexColor('#ef6c00')   # orange
SEV_MED       = colors.HexColor('#f9a825')   # amber
SEV_LOW       = colors.HexColor('#2e7d32')   # green
SEV_CRIT_BG   = colors.HexColor('#3a1414')
SEV_HIGH_BG   = colors.HexColor('#3a200a')
SEV_MED_BG    = colors.HexColor('#332608')
SEV_LOW_BG    = colors.HexColor('#0e2310')

# ─── Styles ────────────────────────────────────────────────────────────────
ss = getSampleStyleSheet()

def style(name, **kw):
    base = dict(
        fontName="BodyR",
        fontSize=10,
        leading=14,
        textColor=TEXT_PRIMARY,
        alignment=TA_LEFT,
        spaceBefore=2,
        spaceAfter=2,
    )
    base.update(kw)
    return ParagraphStyle(name, **base)

S = {
    "h1":      style("h1",      fontName="BodyB", fontSize=22, leading=28, textColor=ACCENT,   spaceBefore=18, spaceAfter=12),
    "h2":      style("h2",      fontName="BodyB", fontSize=16, leading=22, textColor=ACCENT,   spaceBefore=14, spaceAfter=8),
    "h3":      style("h3",      fontName="BodyB", fontSize=13, leading=18, textColor=ACCENT_2, spaceBefore=10, spaceAfter=6),
    "h4":      style("h4",      fontName="BodyB", fontSize=11, leading=15, textColor=TEXT_PRIMARY, spaceBefore=8, spaceAfter=4),
    "body":    style("body",    fontSize=10, leading=14),
    "small":   style("small",   fontSize=9, leading=12, textColor=TEXT_MUTED),
    "bugid":   style("bugid",   fontName="MonoB", fontSize=9, leading=12, textColor=ACCENT),
    "file":    style("file",    fontName="Mono",  fontSize=8.5, leading=11, textColor=TEXT_MUTED),
    "code":    style("code",    fontName="Mono",  fontSize=8.5, leading=11, textColor=TEXT_PRIMARY),
    "cover_t": style("cover_t", fontName="BodyB", fontSize=32, leading=38, alignment=TA_CENTER, textColor=ACCENT),
    "cover_s": style("cover_s", fontName="BodyR", fontSize=14, leading=18, alignment=TA_CENTER, textColor=TEXT_PRIMARY),
    "cover_m": style("cover_m", fontName="BodyR", fontSize=11, leading=14, alignment=TA_CENTER, textColor=TEXT_MUTED),
    "tbl_h":   style("tbl_h",   fontName="BodyB", fontSize=10, leading=13, textColor=colors.white, alignment=TA_LEFT),
    "tbl_c":   style("tbl_c",   fontSize=9.5, leading=12),
    "tbl_c_c": style("tbl_c_c", fontSize=9.5, leading=12, alignment=TA_CENTER),
    "quote":   style("quote",   fontSize=9.5, leading=13, textColor=TEXT_MUTED, leftIndent=12, rightIndent=8, fontName="BodyI"),
}

# ─── Page templates ────────────────────────────────────────────────────────
PAGE_W, PAGE_H = A4
MARGIN_L = 1.6 * cm
MARGIN_R = 1.6 * cm
MARGIN_T = 1.6 * cm
MARGIN_B = 1.8 * cm

def draw_page_chrome(canvas, doc):
    canvas.saveState()
    # background
    canvas.setFillColor(PAGE_BG)
    canvas.rect(0, 0, PAGE_W, PAGE_H, fill=1, stroke=0)
    # header line
    canvas.setStrokeColor(BORDER)
    canvas.setLineWidth(0.4)
    canvas.line(MARGIN_L, PAGE_H - MARGIN_T + 0.3*cm, PAGE_W - MARGIN_R, PAGE_H - MARGIN_T + 0.3*cm)
    # header text
    canvas.setFont("BodyR", 8)
    canvas.setFillColor(TEXT_MUTED)
    canvas.drawString(MARGIN_L, PAGE_H - MARGIN_T + 0.55*cm, "RaveClone — Отчёт об аудите (155 багов)")
    canvas.drawRightString(PAGE_W - MARGIN_R, PAGE_H - MARGIN_T + 0.55*cm, "v1.0 · 2026-07-03")
    # footer
    canvas.setStrokeColor(BORDER)
    canvas.line(MARGIN_L, MARGIN_B - 0.4*cm, PAGE_W - MARGIN_R, MARGIN_B - 0.4*cm)
    canvas.setFont("BodyR", 8)
    canvas.setFillColor(TEXT_MUTED)
    canvas.drawString(MARGIN_L, MARGIN_B - 0.85*cm, "Super Z (GLM-4.6) · code review")
    canvas.drawRightString(PAGE_W - MARGIN_R, MARGIN_B - 0.85*cm, f"стр. {canvas.getPageNumber()}")
    canvas.restoreState()


def draw_cover(canvas, doc):
    canvas.saveState()
    # bg
    canvas.setFillColor(PAGE_BG)
    canvas.rect(0, 0, PAGE_W, PAGE_H, fill=1, stroke=0)
    # subtle top accent bar
    canvas.setFillColor(ACCENT)
    canvas.rect(0, PAGE_H - 0.4*cm, PAGE_W, 0.4*cm, fill=1, stroke=0)
    # accent orbs (subtle glow simulation)
    canvas.setFillColor(SEV_CRIT)
    canvas.setFillAlpha(0.10)
    canvas.circle(PAGE_W*0.2, PAGE_H*0.75, 4*cm, fill=1, stroke=0)
    canvas.setFillColor(ACCENT_2)
    canvas.setFillAlpha(0.08)
    canvas.circle(PAGE_W*0.85, PAGE_H*0.30, 5*cm, fill=1, stroke=0)
    canvas.setFillColor(ACCENT)
    canvas.setFillAlpha(0.07)
    canvas.circle(PAGE_W*0.55, PAGE_H*0.55, 3.5*cm, fill=1, stroke=0)
    canvas.setFillAlpha(1)
    # title block (manually placed; platypus will draw body below)
    canvas.setFillColor(ACCENT)
    canvas.setFont("BodyB", 12)
    canvas.drawCentredString(PAGE_W/2, PAGE_H - 6*cm, "ОТЧЁТ ОБ АУДИТЕ КОДА")
    canvas.setFillColor(TEXT_PRIMARY)
    canvas.setFont("BodyB", 36)
    canvas.drawCentredString(PAGE_W/2, PAGE_H - 8.2*cm, "RaveClone")
    canvas.setFont("BodyB", 18)
    canvas.setFillColor(ACCENT_2)
    canvas.drawCentredString(PAGE_W/2, PAGE_H - 9.4*cm, "SyncWatch / Плинк")
    canvas.setFillColor(TEXT_MUTED)
    canvas.setFont("BodyR", 12)
    canvas.drawCentredString(PAGE_W/2, PAGE_H - 10.6*cm, "Полный аудит безопасности и качества кода")
    canvas.drawCentredString(PAGE_W/2, PAGE_H - 11.2*cm, "iOS · Backend · React Native")
    # stat tiles
    tile_y = 8*cm
    tile_w = 4.0*cm
    tile_h = 2.4*cm
    gap = 0.4*cm
    tiles_total = 4 * tile_w + 3 * gap
    start_x = (PAGE_W - tiles_total) / 2
    tile_data = [
        ("155", "всего багов",     ACCENT),
        ("27",  "критических",     SEV_CRIT),
        ("46",  "высоких",         SEV_HIGH),
        ("82",  "средн+низких",    ACCENT_2),
    ]
    for i, (big, lbl, col) in enumerate(tile_data):
        x = start_x + i * (tile_w + gap)
        canvas.setFillColor(CARD_BG)
        canvas.setStrokeColor(col)
        canvas.setLineWidth(1.2)
        canvas.roundRect(x, tile_y, tile_w, tile_h, 0.3*cm, fill=1, stroke=1)
        canvas.setFillColor(col)
        canvas.setFont("BodyB", 28)
        canvas.drawCentredString(x + tile_w/2, tile_y + tile_h - 1.3*cm, big)
        canvas.setFillColor(TEXT_MUTED)
        canvas.setFont("BodyR", 9)
        canvas.drawCentredString(x + tile_w/2, tile_y + 0.55*cm, lbl)
    # bottom info
    canvas.setFillColor(TEXT_MUTED)
    canvas.setFont("BodyR", 10)
    canvas.drawCentredString(PAGE_W/2, 4.5*cm, "Подготовлено для передачи в GLM-5.2 (Z Client)")
    canvas.drawCentredString(PAGE_W/2, 4.0*cm, "Источник: github.com/PubgmHacker/xpkcakpkfewp-ofewk-pkv")
    canvas.setStrokeColor(BORDER)
    canvas.line(PAGE_W*0.2, 3.3*cm, PAGE_W*0.8, 3.3*cm)
    canvas.setFillColor(TEXT_MUTED)
    canvas.setFont("BodyR", 9)
    canvas.drawCentredString(PAGE_W/2, 2.7*cm, "2026-07-03 · America/Los_Angeles")
    canvas.restoreState()


# ─── Helper builders ───────────────────────────────────────────────────────

def code_block(text):
    """Render a code block with monospace font on dark stripe."""
    if not text:
        return Spacer(0, 0)
    lines = text.rstrip().split("\n")
    # build a 1-col table to give it a background
    inner = [[Preformatted(line, S["code"])] for line in lines]
    t = Table(inner, colWidths=[PAGE_W - MARGIN_L - MARGIN_R - 4*mm])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0,0), (-1,-1), TABLE_STRIPE),
        ("LEFTPADDING", (0,0), (-1,-1), 8),
        ("RIGHTPADDING", (0,0), (-1,-1), 8),
        ("TOPPADDING", (0,0), (-1,-1), 1),
        ("BOTTOMPADDING", (0,0), (-1,-1), 1),
        ("BOX", (0,0), (-1,-1), 0.3, BORDER),
    ]))
    return t


def sev_chip(label, bg, fg=colors.white):
    """Small colored severity chip."""
    p = Paragraph(f'<font color="white"><b>{label}</b></font>', S["small"])
    t = Table([[p]], colWidths=[2.2*cm])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0,0), (-1,-1), bg),
        ("BOX", (0,0), (-1,-1), 0.3, bg),
        ("LEFTPADDING", (0,0), (-1,-1), 4),
        ("RIGHTPADDING", (0,0), (-1,-1), 4),
        ("TOPPADDING", (0,0), (-1,-1), 2),
        ("BOTTOMPADDING", (0,0), (-1,-1), 2),
        ("ALIGN", (0,0), (-1,-1), "CENTER"),
    ]))
    return t


def bug_entry(sev_label, sev_bg, bug_id, title, file_ref, what, impact, fix):
    """One bug entry as a structured block."""
    # Header row: chip + bug_id + title
    hdr_data = [[
        sev_chip(sev_label, sev_bg),
        Paragraph(f'<font name="MonoB" color="#e6cb77">{bug_id}</font>', S["small"]),
        Paragraph(f'<b>{title}</b>', S["body"]),
    ]]
    hdr = Table(hdr_data, colWidths=[2.4*cm, 1.6*cm, PAGE_W - MARGIN_L - MARGIN_R - 2.4*cm - 1.6*cm - 4*mm])
    hdr.setStyle(TableStyle([
        ("VALIGN", (0,0), (-1,-1), "MIDDLE"),
        ("LEFTPADDING", (0,0), (-1,-1), 2),
        ("RIGHTPADDING", (0,0), (-1,-1), 2),
        ("TOPPADDING", (0,0), (-1,-1), 2),
        ("BOTTOMPADDING", (0,0), (-1,-1), 2),
    ]))
    # File reference
    file_p = Paragraph(f'<font name="Mono" color="#94918b">📁 {file_ref}</font>', S["file"])
    # What's wrong
    what_p = Paragraph(f'<b><font color="#e6cb77">Что не так:</font></b> {what}', S["body"])
    # Impact
    impact_p = Paragraph(f'<b><font color="#c68984">Влияние:</font></b> {impact}', S["body"])
    # Fix
    fix_p = Paragraph(f'<b><font color="#6fb887">Исправление:</font></b> {fix}', S["body"])
    # Combine with file row
    inner = [[hdr], [file_p], [what_p], [impact_p], [fix_p]]
    t = Table(inner, colWidths=[PAGE_W - MARGIN_L - MARGIN_R - 4*mm])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0,0), (-1,-1), CARD_BG),
        ("LEFTPADDING", (0,0), (-1,-1), 8),
        ("RIGHTPADDING", (0,0), (-1,-1), 8),
        ("TOPPADDING", (0,0), (-1,-1), 4),
        ("BOTTOMPADDING", (0,0), (-1,-1), 4),
        ("BOX", (0,0), (-1,-1), 0.3, BORDER),
        ("LINEBELOW", (0,0), (-1,0), 0.2, BORDER),
    ]))
    return KeepTogether([t, Spacer(0, 6)])


def section_header(num, title, color=ACCENT):
    p1 = Paragraph(f'<font color="#94918b" name="MonoB">{num}</font>', S["small"])
    p2 = Paragraph(f'<font color="#{color.hexval()[2:]}"><b>{title}</b></font>', S["h2"])
    t = Table([[p1, p2]], colWidths=[1.2*cm, PAGE_W - MARGIN_L - MARGIN_R - 1.2*cm - 4*mm])
    t.setStyle(TableStyle([
        ("VALIGN", (0,0), (-1,-1), "MIDDLE"),
        ("LEFTPADDING", (0,0), (-1,-1), 0),
        ("RIGHTPADDING", (0,0), (-1,-1), 0),
        ("LINEBELOW", (0,0), (-1,-1), 1.0, color),
        ("BOTTOMPADDING", (0,0), (-1,-1), 6),
    ]))
    return t


def severity_table(rows):
    """rows: list of [platform, crit, high, med, low, total]"""
    header = ["Платформа", "🔴 Критич.", "🟠 Выс.", "🟡 Сред.", "🟢 Низк.", "Итого"]
    data = [header] + rows
    # convert to paragraphs
    body = []
    for i, row in enumerate(data):
        if i == 0:
            body.append([Paragraph(f'<b>{c}</b>', S["tbl_h"]) for c in row])
        else:
            cells = []
            for j, c in enumerate(row):
                sty = S["tbl_c_c"] if j > 0 else S["tbl_c"]
                cells.append(Paragraph(str(c), sty))
            body.append(cells)
    t = Table(body, colWidths=[5*cm, 2.4*cm, 2.4*cm, 2.4*cm, 2.4*cm, 2.4*cm])
    style_cmds = [
        ("BACKGROUND", (0,0), (-1,0), HEADER_FILL),
        ("VALIGN", (0,0), (-1,-1), "MIDDLE"),
        ("LEFTPADDING", (0,0), (-1,-1), 6),
        ("RIGHTPADDING", (0,0), (-1,-1), 6),
        ("TOPPADDING", (0,0), (-1,-1), 6),
        ("BOTTOMPADDING", (0,0), (-1,-1), 6),
        ("BOX", (0,0), (-1,-1), 0.5, BORDER),
        ("INNERGRID", (0,0), (-1,-1), 0.2, BORDER),
    ]
    # stripe data rows
    for i in range(1, len(body)):
        if i % 2 == 0:
            style_cmds.append(("BACKGROUND", (0,i), (-1,i), TABLE_STRIPE))
    t.setStyle(TableStyle(style_cmds))
    return t


def priority_card(num, title, what, why):
    """Top-priority card with big number."""
    num_p = Paragraph(f'<font color="#e6cb77" name="BodyB" size="36">{num}</font>', S["body"])
    title_p = Paragraph(f'<font color="#59a3bc" name="BodyB" size="13">{title}</font>', S["body"])
    what_p = Paragraph(f'<b>Что:</b> {what}', S["small"])
    why_p = Paragraph(f'<b>Почему:</b> {why}', S["small"])
    inner = Table([[num_p, [title_p, Spacer(0,4), what_p, Spacer(0,2), why_p]]],
                  colWidths=[1.6*cm, PAGE_W - MARGIN_L - MARGIN_R - 1.6*cm - 4*mm])
    inner.setStyle(TableStyle([
        ("BACKGROUND", (0,0), (-1,-1), CARD_BG),
        ("VALIGN", (0,0), (-1,-1), "TOP"),
        ("LEFTPADDING", (0,0), (-1,-1), 10),
        ("RIGHTPADDING", (0,0), (-1,-1), 10),
        ("TOPPADDING", (0,0), (-1,-1), 10),
        ("BOTTOMPADDING", (0,0), (-1,-1), 10),
        ("BOX", (0,0), (-1,-1), 0.5, ACCENT),
        ("LINEAFTER", (0,0), (0,0), 1.0, ACCENT),
    ]))
    return KeepTogether([inner, Spacer(0, 8)])


# ─── Build story ───────────────────────────────────────────────────────────

story = []

# Cover (drawn by canvas) — push a page break to start body on page 2
story.append(PageBreak())

# ── EXECUTIVE SUMMARY ─────────────────────────────────────────────────────
story.append(section_header("00", "Краткое резюме"))
story.append(Paragraph(
    "Проведён полный аудит кодовой базы <b>RaveClone / SyncWatch / Плинк</b> — приложения для совместного "
    "просмотра видео в реальном времени. Аудит охватывает три платформы: <b>нативный iOS-клиент (Swift/SwiftUI)</b>, "
    "<b>Node.js бэкенд (Fastify + WebSocket + Prisma)</b> и <b>React Native-клиент (Expo)</b>. "
    "Суммарно обнаружено <b>155 багов</b>, из них <b>27 критических</b>, блокирующих релиз в текущем виде.",
    S["body"]
))
story.append(Spacer(0, 8))
story.append(Paragraph(
    "Главная находка аудита: <b>несколько showstopper-багов делают ключевые фичи приложения неработоспособными «из коробки»</b>. "
    "На iOS не работает весь realtime-слой (WebSocket не переходит в состояние connected), DM/друзья/админка получают 401, "
    "host identity захардкожен как «current_user». На бэкенде 12 хендлеров читают несуществующее поле <code>request.user.sub</code> "
    "вместо <code>request.user.id</code>, ломая DM/друзей/профиль/историю. На React Native JWT хранится в небезопасном AsyncStorage, "
    "а DRM-плейер использует неправильный URL.",
    S["body"]
))
story.append(Spacer(0, 10))

# Severity table
story.append(Paragraph("Распределение по серьёзности и платформам", S["h3"]))
story.append(severity_table([
    ["Backend (Node.js)",     "5",  "11", "10", "6",  "34"],
    ["iOS (Swift/SwiftUI)",   "14", "14", "16", "16", "60"],
    ["React Native (Expo)",   "8",  "21", "17", "15", "61"],
    ["<b>Итого</b>",          "<b>27</b>", "<b>46</b>", "<b>43</b>", "<b>37</b>", "<b>155</b>"],
]))
story.append(Spacer(0, 14))

# Top 5 priorities
story.append(section_header("01", "Топ-5 приоритетов (что фиксить первым делом)"))
story.append(Paragraph(
    "Эти пять исправлений открывают путь к работающему MVP. Без них остальной фикс-ап бессмысленен — "
    "приложение либо не запускается в ключевых сценариях, либо не проходит App Store Review.",
    S["body"]
))
story.append(Spacer(0, 6))

story.append(priority_card(
    "1",
    "iOS C1: починить lifecycle WebSocketClient.isConnected",
    "Вызвать <code>notifyConnectedIfNeeded()</code> в receive-loop после <code>task.resume()</code>, либо открыть сокет через <code>withCheckedThrowingContinuation</code>.",
    "Без этого ВЕСЬ realtime-слой (чат, sync, реакции, сигналинг, WebRTC) мёртв. <code>send()</code> всегда копит в <code>pendingMessages</code> и никогда не флешит."
))
story.append(priority_card(
    "2",
    "Backend #1+#2: request.user.sub → .id + preHandler authenticate на admin",
    "Заменить <code>request.user.sub</code> на <code>request.user.id</code> в 12 хендлерах (messages, friends, profile). Добавить <code>preHandler: [fastify.authenticate]</code> на все admin-роуты.",
    "Сейчас DM, друзья, профиль, история просмотра, премиум и вся админка возвращают 500 или 401. Четыре крупных фичи полностью не работают."
))
story.append(priority_card(
    "3",
    "iOS C4+C5+C6: внедрить общий authenticated APIClient",
    "В <code>RaveCloneApp</code> создать один <code>APIClient</code> с инжектированным <code>authToken</code>, передавать его в <code>DMChatService</code>, <code>FriendManager</code>, <code>AdminPanelView</code> через DI.",
    "Сейчас каждый из этих сервисов создаёт собственный <code>APIClient()</code> без токена. Все их вызовы возвращают 401."
))
story.append(priority_card(
    "4",
    "iOS C7+C8: прокинуть реальный currentUserId и hostIsPremium",
    "В <code>RoomView.setupViewModel</code> и <code>RoomCreationView.createRoom</code> использовать <code>authService.currentUser?.id</code> и <code>PremiumStatusManager.shared.isPremium</code> вместо хардкода «current_user»/false.",
    "<code>isHost</code> всегда false → play/pause/seek не отправляются, sync-движок не запускается. <code>hostIsPremium=false</code> → реклама показывается всем, даже премиум-юзерам."
))
story.append(priority_card(
    "5",
    "RN C2+C3+C4+C5: SecureStore для JWT и DRM-куки + удалить demo-bypass",
    "Перевести JWT из <code>AsyncStorage</code> в <code>expo-secure-store</code>. Перенести туда же куки DRM-сессий Netflix/Кинопоиск. Удалить offline-guest fallback и demo Google/VK exchange.",
    "Текущая модель auth ненадёжна: токены утекают через filesystem, demo-токен «demo_google_token» тривиально логинит любого. App Store отклонит."
))

story.append(PageBreak())

# ── SPECIAL: ANIMATED BACKGROUND BUG ──────────────────────────────────────
story.append(section_header("02", "Спец-задача: не работает анимированный фон в HomeView"))
story.append(Paragraph(
    "Пользователь сообщил: <i>«не работает фон в приложении (анимированный) бэкграунд, который за карточками видео "
    "«смотрят сейчас» и «рекомендации»»</i>. После анализа <code>AnimatedGradientBackground.swift</code>, "
    "<code>HomeView.swift</code> и <code>Color+Theme.swift</code> найдено <b>5 независимых причин</b>, ни одна из которых "
    "не связана с самими карточками. Карточки рендерятся нормально — фон под ними теряется.",
    S["body"]
))
story.append(Spacer(0, 8))

# Root cause 1
story.append(Paragraph("Причина #1 (главная): SwiftUI-антипаттерн withAnimation + repeatForever в .onAppear", S["h3"]))
story.append(Paragraph("📁 <font name='Mono'>RaveClone/RaveClone/Views/Components/AnimatedGradientBackground.swift:53-57</font>", S["file"]))
story.append(Spacer(0, 4))
story.append(code_block(
    ".onAppear {\n"
    "    withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {\n"
    "        animate = true\n"
    "    }\n"
    "}"
))
story.append(Spacer(0, 6))
story.append(Paragraph(
    "<b>Что не так:</b> Известный SwiftUI-антипаттерн. Когда <code>animate = false</code> изначально и вы переключаете его на "
    "<code>true</code> внутри <code>withAnimation</code> в <code>.onAppear</code>:<br/>"
    "1. <code>.onAppear</code> срабатывает ДО того, как view полностью в иерархии — <code>withAnimation</code> запускается, "
    "но первый кадр может не зафиксироваться.<br/>"
    "2. При возврате из RoomView (navigation back) <code>.onAppear</code> срабатывает снова, но <code>animate</code> уже <code>true</code> — "
    "состояние не меняется, новая анимация не запускается, старая продолжается с непредсказуемым состоянием.<br/>"
    "3. <code>repeatForever(autoreverses: true)</code> интерполирует смещения orbs на основе boolean. Между false и true нет "
    "промежуточных кадров — интерполяция может «залипнуть» на первом кадре.",
    S["body"]
))
story.append(Paragraph(
    "<b>Влияние:</b> Орбы либо статичны (вижу только чёрный фон), либо случайно начинают двигаться после навигации.",
    S["body"]
))
story.append(Paragraph(
    "<b>Исправление:</b> Использовать <code>TimelineView</code> или <code>Canvas</code> с <code>TimelineScheduler</code> — "
    "это гарантирует непрерывную анимацию независимо от lifecycle. Альтернатива — отложенный старт через "
    "<code>DispatchQueue.main.asyncAfter</code>:",
    S["body"]
))
story.append(code_block(
    ".onAppear {\n"
    "    animate = false\n"
    "    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {\n"
    "        withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {\n"
    "            animate = true\n"
    "        }\n"
    "    }\n"
    "}\n\n"
    "// ИЛИ (рекомендуется) — TimelineView с постоянной анимацией:\n"
    "TimelineView(.animation) { context in\n"
    "    let t = context.date.timeIntervalSinceReferenceDate\n"
    "    GlowOrb(color: warmColors[0], size: 360, blur: 90,\n"
    "            x: CGFloat(sin(t * 0.1) * 60),\n"
    "            y: CGFloat(cos(t * 0.07) * 180),\n"
    "            opacity: 0.22)\n"
    "}"
))
story.append(Spacer(0, 10))

# Root cause 2
story.append(Paragraph("Причина #2: Color.raveBackground = чистый чёрный + opacity 0.10-0.22 — слишком тускло", S["h3"]))
story.append(Paragraph("📁 <font name='Mono'>Color+Theme.swift:32 + AnimatedGradientBackground.swift:34,41,48</font>", S["file"]))
story.append(Spacer(0, 4))
story.append(code_block(
    "static let raveBackground = Color(hex: 0x000000)   // чистый чёрный\n\n"
    "GlowOrb(color: warmColors[0], size: 360, blur: 90,\n"
    "        x: animate ? -60 : -110, y: animate ? -180 : -120,\n"
    "        opacity: hasActiveRooms ? 0.22 : 0.16)       // макс 22%\n"
    "GlowOrb(... opacity: hasActiveRooms ? 0.18 : 0.13)\n"
    "GlowOrb(... opacity: hasActiveRooms ? 0.15 : 0.10)   // мин 10%"
))
story.append(Paragraph(
    "<b>Что не так:</b> При <code>opacity 0.10-0.22</code> поверх чистого чёрного <code>#000000</code> и blur radius 90-110pt "
    "орбы практически невидимы глазу, особенно: при внешней освещённости, на устройствах с антигларе-покрытием, "
    "в условиях яркого окружения. Даже если анимация работает — её просто не видно.",
    S["body"]
))
story.append(Paragraph(
    "<b>Исправление:</b> Поднять opacity до 0.35-0.55, либо сделать базовый фон не чисто чёрным, а <code>#050810</code> "
    "(есть в теме <code>raveBgGradient</code>), либо использовать <code>blendMode(.screen)</code> для орбов на чёрном:",
    S["body"]
))
story.append(code_block(
    "Circle()\n"
    "    .fill(color.opacity(0.45))            // ← было 0.22\n"
    "    .frame(width: size, height: size)\n"
    "    .blur(radius: blur)\n"
    "    .blendMode(.screen)                   // ← добавит свечение\n"
    "    .offset(x: x, y: y)\n"
    "    .compositingGroup()                   // обязательно для blendMode"
))
story.append(Spacer(0, 10))

# Root cause 3
story.append(Paragraph("Причина #3: Reduce Motion accessibility не проверяется", S["h3"]))
story.append(Paragraph(
    "<b>Что не так:</b> Если у пользователя в iOS Settings → Accessibility → Motion включён <b>Reduce Motion</b> (≈10-15% юзеров), "
    "SwiftUI полностью отключает <code>withAnimation</code>. Орбы остаются в начальной позиции (<code>animate = false</code>) — "
    "т.е. смещены на -110, -180 (вне видимой зоны). Код не проверяет <code>UIAccessibility.isReduceMotionEnabled</code>.",
    S["body"]
))
story.append(Paragraph(
    "<b>Исправление:</b> Для Reduce Motion либо показывать статичные орбы по центру, либо использовать <code>TimelineView</code> "
    "(он не зависит от motion-настроек):",
    S["body"]
))
story.append(code_block(
    "@Environment(\\.accessibilityReduceMotion) var reduceMotion\n\n"
    "var body: some View {\n"
    "    ZStack {\n"
    "        Color.raveBackground.ignoresSafeArea()\n"
    "        if reduceMotion {\n"
    "            // статичные орбы по центру\n"
    "            ZStack { /* fixed positions */ }\n"
    "        } else {\n"
    "            TimelineView(.animation) { ctx in /* animated orbs */ }\n"
    "        }\n"
    "    }\n"
    "}"
))
story.append(Spacer(0, 10))

# Root cause 4
story.append(Paragraph("Причина #4: .blur(radius: 90-110) на 360pt circle — тяжеленный GPU-эффект", S["h3"]))
story.append(Paragraph(
    "<b>Что не так:</b> <code>.blur(radius: 90)</code> на 360pt circle — экстремально тяжёлая операция для GPU. "
    "iOS может деградировать blur до r=20-30 при нехватке ресурсов, либо вообще не рендерить его на старых устройствах "
    "(iPhone X и старше). Симулятор в Xcode может показывать blur, а на реальном устройстве — нет.",
    S["body"]
))
story.append(Paragraph(
    "<b>Исправление:</b> Уменьшить blur до 40-60pt (компенсировать повышением opacity), либо использовать "
    "<code>RadialGradient</code> вместо blur — это нативный GPU-примитив, в разы быстрее:",
    S["body"]
))
story.append(code_block(
    "RadialGradient(\n"
    "    colors: [color.opacity(0.55), color.opacity(0.0)],\n"
    "    center: .center,\n"
    "    startRadius: 0,\n"
    "    endRadius: 180\n"
    ")\n"
    ".frame(width: 360, height: 360)\n"
    ".offset(x: x, y: y)\n"
    "// никакого .blur() — RadialGradient сам по себе glow"
))
story.append(Spacer(0, 10))

# Root cause 5
story.append(Paragraph("Причина #5: конкуренция .onAppear в HomeView и AnimatedGradientBackground", S["h3"]))
story.append(Paragraph("📁 <font name='Mono'>HomeView.swift:162-167 и AnimatedGradientBackground.swift:53-57</font>", S["file"]))
story.append(Spacer(0, 4))
story.append(code_block(
    "// HomeView.swift:162\n"
    ".onAppear {\n"
    "    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {\n"
    "        appeared = true\n"
    "    }\n"
    "    startCTACollapseTimer()\n"
    "}\n\n"
    "// AnimatedGradientBackground.swift:53 (внутри HomeView)\n"
    ".onAppear {\n"
    "    withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {\n"
    "        animate = true\n"
    "    }\n"
    "}"
))
story.append(Paragraph(
    "<b>Что не так:</b> Оба <code>onAppear</code> срабатывают одновременно. SwiftUI может объединить их в один runloop tick — "
    "<code>withAnimation</code> для AnimatedGradientBackground может «проиграть» спринговую анимацию appeared, особенно "
    "<code>repeatForever</code> часть, потому что SwiftUI видит каскад анимаций и может дропнуть ту, что длиннее.",
    S["body"]
))
story.append(Paragraph(
    "<b>Исправление:</b> Разнести во времени или использовать <code>.task</code> вместо <code>.onAppear</code> "
    "для фоновой анимации:",
    S["body"]
))
story.append(code_block(
    ".task {\n"
    "    try? await Task.sleep(nanoseconds: 300_000_000)  // 300мс\n"
    "    withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {\n"
    "        animate = true\n"
    "    }\n"
    "}"
))
story.append(Spacer(0, 14))

# Quick fix summary
story.append(Paragraph("Готовый drop-in фикс AnimatedGradientBackground.swift", S["h3"]))
story.append(Paragraph(
    "Минимальное изменение, которое починит анимацию фона в большинстве случаев — "
    "заменить весь body на версию с TimelineView:",
    S["body"]
))
story.append(code_block(
    "struct AnimatedGradientBackground: View {\n"
    "    var hasActiveRooms: Bool = true\n\n"
    "    var body: some View {\n"
    "        ZStack {\n"
    "            Color.raveBackground.ignoresSafeArea()\n\n"
    "            TimelineView(.animation) { context in\n"
    "                let t = context.date.timeIntervalSinceReferenceDate\n"
    "                ZStack {\n"
    "                    glowOrb(color: warmColors[0], t: t, size: 360, blur: 50,\n"
    "                            xAmp: 60,  yAmp: 180, xPhase: 0.0, yPhase: 0.3, opacity: 0.40)\n"
    "                    glowOrb(color: warmColors[1], t: t, size: 300, blur: 60,\n"
    "                            xAmp: 100, yAmp: 160, xPhase: 1.2, yPhase: 0.7, opacity: 0.32)\n"
    "                    glowOrb(color: warmColors[2], t: t, size: 240, blur: 70,\n"
    "                            xAmp: 80,  yAmp: 40,  xPhase: 2.4, yPhase: 1.1, opacity: 0.28)\n"
    "                }\n"
    "                .ignoresSafeArea()\n"
    "            }\n"
    "        }\n"
    "    }\n\n"
    "    private func glowOrb(color: Color, t: Double, size: CGFloat, blur: CGFloat,\n"
    "                         xAmp: CGFloat, yAmp: CGFloat, xPhase: Double, yPhase: Double,\n"
    "                         opacity: Double) -> some View {\n"
    "        Circle()\n"
    "            .fill(color.opacity(opacity))\n"
    "            .frame(width: size, height: size)\n"
    "            .blur(radius: blur)\n"
    "            .offset(\n"
    "                x: CGFloat(sin(t * 0.1 + xPhase)) * xAmp,\n"
    "                y: CGFloat(cos(t * 0.07 + yPhase)) * yAmp\n"
    "            )\n"
    "            .blendMode(.screen)\n"
    "    }\n"
    "}"
))
story.append(Spacer(0, 6))
story.append(Paragraph(
    "<b>Что изменено:</b><br/>"
    "• <code>TimelineView(.animation)</code> вместо <code>withAnimation + repeatForever</code> — непрерывная анимация, "
    "не зависит от lifecycle.<br/>"
    "• Opacity поднята с 0.10-0.22 до 0.28-0.40 — орбы теперь видны.<br/>"
    "• Blur уменьшен с 90-110 до 50-70pt — компенсация GPU-нагрузки.<br/>"
    "• Добавлен <code>.blendMode(.screen)</code> — свечение поверх чёрного вместо затемнения.<br/>"
    "• Синусоидальные смещения вместо boolean-toggle — плавное движение без «застреваний».",
    S["body"]
))

story.append(PageBreak())

# ── iOS SECTION ───────────────────────────────────────────────────────────
story.append(section_header("03", "iOS (Swift/SwiftUI) — 60 багов"))
story.append(Paragraph(
    "Аудит 50+ Swift-файлов: networking (WebSocket, REST, signaling), services (sync, voice, auth, media, DM, "
    "screen capture, audio, StoreKit, friends, premium, ads), view models, views, models, utilities, resources.",
    S["body"]
))
story.append(Spacer(0, 8))

# iOS Critical
story.append(Paragraph("🔴 CRITICAL (14) — showstoppers / security / auth-bypass", S["h3"]))
story.append(Spacer(0, 4))

ios_crit = [
    ("C1", "WebSocket isConnected никогда не становится true — весь realtime мёртв",
     "Networking/WebSocketClient.swift:408-424",
     "Метод <code>notifyConnectedIfNeeded()</code> объявлен, но нигде не вызывается (grep-verified). Единственное место, где <code>isConnected</code> устанавливается в <code>true</code>.",
     "Метод <code>send()</code> проверяет <code>if isConnected</code> (всегда false) → каждое исходящее сообщение копится в <code>pendingMessages</code> и НИКОГДА не отправляется. <code>delegate?.webSocketDidConnect</code> не вызывается, sync engine не запускается. Чат, реакции, play/pause/seek, сигналинг — ничего не доходит до сервера.",
     "Использовать неявное открытое состояние <code>URLSessionWebSocketTask</code>: сразу после <code>task.resume()</code> вызвать <code>receiveMessage()</code>, либо открыть сокет через <code>withCheckedThrowingContinuation</code>, который resume-ится на первом receive callback."),

    ("C2", "JWT хранится в UserDefaults вместо Keychain",
     "Services/AuthService.swift:130-131",
     "<code>defaults.set(token, forKey: Keys.authToken)</code>. Также <code>Keys.savedUser</code> хранит полный JSON пользователя в UserDefaults.",
     "JWT в UserDefaults читается любым, у кого есть доступ к filesystem: sandbox escape, извлечение iCloud-бэкапа, джейлбрейк. Угон аккаунта → полный account takeover. Apple App Review отклонит за нарушение Secure Coding.",
     "Использовать существующий <code>KeychainHelper</code> (уже определён в <code>YandexAuthService.swift:238</code>). Кстати, Yandex-путь уже хранит JWT в Keychain — несогласованность."),

    ("C3", "getFreshToken() никогда не обновляет токен",
     "Services/AuthService.swift:118-124",
     "Обе ветки <code>if</code> возвращают одно и то же <code>authToken</code>. Нет вызова <code>/api/auth/refresh</code>.",
     "После истечения 24-часового JWT приложение молча продолжает слать истёкший токен. Сервер возвращает 401, юзер логаутится без предупреждения. <code>bridgeAuthToken()</code> в <code>RaveCloneApp.init</code> затем распространяет истёкший токен в WebSocketClient и MediaService.",
     "Реализовать <code>refreshJWT()</code>: POST на <code>/auth/refresh</code> с refresh-токеном из Keychain, обновить authToken и expiry."),

    ("C4", "DMChatService создаёт собственный APIClient без токена",
     "Services/DMChatService.swift:16",
     "<code>private let api = APIClient()</code> — свежий клиент на каждый инстанс. <code>authToken</code> всегда nil и никем не назначается.",
     "Фича DM полностью неработоспособна. <code>loadHistory(friendId:)</code> молча return-ит из guard <code>api.authToken != nil</code>; <code>sendMessage</code> получает 401. UI показывает оптимистичные сообщения, но они никогда не доходят до сервера.",
     "Инжектировать общий <code>APIClient</code> (тот же, что <code>RaveCloneApp.init</code> даёт <code>AuthService</code>) в <code>DMChatService</code> через конструктор."),

    ("C5", "FriendManager создаёт собственный APIClient без токена",
     "Services/FriendManager.swift:26",
     "Тот же паттерн, что C4 — <code>private let api = APIClient()</code>.",
     "Весь социальный слой (друзья, реквесты, поиск) сломан — каждый API-вызов возвращает 401. <code>loadAll()</code> в <code>init()</code> молча no-op из-за guard.",
     "Инжектировать общий authenticated <code>APIClient</code>."),

    ("C6", "AdminPanelView создаёт собственный APIClient без токена",
     "Views/Admin/AdminPanelView.swift:8",
     "Тот же паттерн. <code>loadUsers</code> вызывает <code>api.request(\"admin/users\")</code>, который всегда 401.",
     "Админ-панель не может загрузить или изменить данные. View бесконечно показывает empty state; ban/unban/delete-действия падают.",
     "Инжектировать общий authenticated <code>APIClient</code> из app-контейнера."),

    ("C7", "RoomView.setupViewModel() хардкодит currentUserId: \"current_user\"",
     "Views/Room/RoomView.swift:470-493",
     "<code>userID: \"current_user\"</code> и <code>isHost: room.hostID == \"current_user\"</code> — всегда false для реальных юзеров с UUID.",
     "<code>RoomViewModel.isHost</code> всегда false → <code>SyncEngine.play()</code>/<code>pause()</code>/<code>seek()</code> все <code>guard isHost</code> и молча no-op. Таймер broadcast состояния не запускается. Команды sync от хоста не отправляются. Восстановление сохранённой позиции также gated на isHost.",
     "Получать реальный user id из <code>AuthService.currentUser?.id</code> и передавать вниз. Весь <code>setupViewModel</code> должен быть удалён в пользу DI из <code>RaveCloneApp</code>."),

    ("C8", "RoomCreationView.createRoom() хардкодит hostID и hostIsPremium: false",
     "Views/Home/RoomCreationView.swift:469-483",
     "<code>hostID: \"current_user\"</code>, <code>hostIsPremium: false</code> — хардкод. Также в <code>CreateRoomView.swift:325-337</code>.",
     "Даже если реальный юзер premium, <code>hostIsPremium=false</code> отправляется участникам → AdSessionManager трактует хоста как non-premium и показывает рекламу. <code>hostID=\"current_user\"</code> значит, что проверки isHost в других местах никогда не матчат.",
     "Использовать <code>authService.currentUser?.id ?? UUID().uuidString</code> и <code>PremiumStatusManager.shared.isPremium</code>."),

    ("C9", "PremiumStatusManager.setPremium(_:) позволяет ручную активацию premium без IAP",
     "Services/PremiumStatusManager.swift:62-72",
     "<code>setPremium(true)</code> ставит <code>isPremium = true</code> и <code>subscriptionExpiry = now + 30d</code>. <code>isPremium</code> персистится в UserDefaults (строка 105).",
     "Любой вызов (или юзер с filesystem-доступом) может переключить флаг <code>rave_user_is_premium</code> и получить premium-фичи навсегда — обход StoreKit, обход серверной валидации, обход ad-gating, поднятие caps с 4 до 50 участников. Гарантированный App Review reject (Guideline 3.1.1).",
     "Удалить <code>setPremium</code>. Premium должен активироваться только через <code>StoreManager.handleSuccessfulPurchase</code> И валидироваться серверно: POST StoreKit JWS на <code>/api/iap/verify</code>, сервер ставит <code>isPremium</code> на User-записи."),

    ("C10", "AdSessionManager.triggerAd() скипает premium-host check",
     "Services/AdSessionManager.swift:122-136",
     "Метод <code>triggerAd()</code> не вызывает <code>shouldPlayAd(hostIsPremium:)</code> (строка 109) — это dead code, который никто не вызывает.",
     "Даже premium-хосты видят рекламу — это убивает всё «Premium = no ads» value proposition. В комбинации с C8 (hostIsPremium всегда false) КАЖДЫЙ хост видит рекламу.",
     "Добавить guard в начало <code>triggerAd</code>: <code>guard shouldPlayAd(hostIsPremium: PremiumStatusManager.shared.isPremium) else { startAdTimer(); return }</code>."),

    ("C11", "DirectMessage.isOwnMessage проверяет неверный sentinel",
     "Models/DirectMessage.swift:19-21",
     "<code>senderID == \"current_user\"</code>, но <code>DMChatService.sendMessage</code> (строка 69-82) ставит <code>senderID = me</code>, где <code>me = currentUserId ?? \"me\"</code>. Реальный UUID, не «current_user».",
     "В DMChatView ваши собственные сообщения рендерятся СЛЕВА (как от собеседника) с placeholder-аватаркой. Premium shimmer (строка 219) никогда не триггерится для own messages.",
     "Прокинуть реальный currentUserId в DMChatView и сравнивать там. Или хранить <code>currentUserId</code> в модели при конструировании."),

    ("C12", "Info.plist без privacy usage descriptions (микрофон, камера, галерея, local network)",
     "Resources/Info.plist",
     "Нет <code>NSMicrophoneUsageDescription</code>, <code>NSCameraUsageDescription</code>, <code>NSPhotoLibraryUsageDescription</code>, <code>NSLocalNetworkUsageDescription</code>. Приложение имеет voice chat, screen capture, avatar upload — всем нужны эти ключи.",
     "<code>AVAudioSession.requestRecordPermission</code> и <code>AVCaptureSession.startRunning</code> крашнут приложение с <code>EXC_BREAKPOINT</code> при первом вызове. App Store авто-реджект.",
     "Добавить 4 ключа в Info.plist с русскими описаниями."),

    ("C13", "Plink.entitlements пустой <dict/> — нет Associated Domains, IAP, APNs",
     "Resources/Plink.entitlements",
     "Файл — пустой <code>&lt;dict/&gt;</code>. Нет <code>com.apple.developer.associated-domains</code>, <code>com.apple.developer.in-app-payments</code>, <code>aps-environment</code>.",
     "Universal Links, IAP и push-нотификации молча не работают в release-сборках. Deep-link share flow возвращает 404 по тапу. Premium-подписки могут инициироваться, но не завершаются серверной верификацией.",
     "Добавить entitlements: <code>applinks:raveclone.app</code>, <code>merchant.com.syncwatch.raveclone</code>, <code>aps-environment: production</code>."),

    ("C14", "Yandex OAuth clientID — захардкоженный placeholder",
     "Services/YandexAuthService.swift:40-41",
     "<code>clientID: String = \"yandex_client_id_placeholder\"</code>. Любой код, инстанцирующий <code>YandexAuthService()</code> без override, попадёт на Yandex OAuth с несуществующим client_id.",
     "Yandex ID sign-in не работает. Yandex Plus подписка (<code>isPlus</code>) никогда не проверяется.",
     "Перенести реальный clientID в build configuration / xcconfig, читать через <code>Bundle.main.object(forInfoDictionaryKey: \"YANDEX_CLIENT_ID\")</code>."),
]

for bid, title, fref, what, impact, fix in ios_crit:
    story.append(bug_entry("CRIT", SEV_CRIT, bid, title, fref, what, impact, fix))

story.append(PageBreak())

# iOS High
story.append(Paragraph("🟠 HIGH (14) — leaks / crashes / lifecycle", S["h3"]))
story.append(Spacer(0, 4))

ios_high = [
    ("H1", "WebSocketClient.scheduleReconnect может оставить isReconnecting застрявшим",
     "Networking/WebSocketClient.swift:390-401",
     "Если <code>disconnect()</code> вызывается во время backoff-окна, <code>isManuallyDisconnected</code> становится true, asyncAfter-замыкание выходит, но <code>isReconnecting</code> остаётся true (сбрасывается только в success-ветке).",
     "После backgrounding + manual disconnect клиент может отказаться переподключаться.",
     "Сбросить <code>isReconnecting = false</code> в <code>disconnect()</code>."),

    ("H2", "RoomViewModel и RoomSyncManager дерутся за wsClient.delegate",
     "Views/Room/RoomView.swift:489 + Services/RoomSyncManager.swift:101",
     "Оба объекта назначают себя <code>wsClient.delegate = self</code>. Последний выигрывает. <code>setupViewModel</code> (через .onAppear) идёт первым → RoomSyncManager становится делегатом, затем <code>joinRoomFlow</code> (в .task) перезаписывает на RoomViewModel.",
     "Race condition: входящие WS-сообщения могут идти не в тот handler. Два делегата с расходящейся логикой маршрутизации.",
     "Использовать один делегат (вероятно RoomViewModel) и явно форвардить в RoomSyncManager, либо multicast-delegate паттерн."),

    ("H3", "VideoContainerView создаёт ВТОРОЙ AVPlayer отдельно от SyncEngine",
     "Views/Room/VideoContainerView.swift:114-146",
     "<code>PlayerUIView</code> создаёт собственный <code>AVPlayer</code> из того же URL. <code>SyncEngine.loadMedia</code> ТОЖЕ создаёт AVPlayer. Два AVPlayer играют один поток независимо.",
     "SyncEngine контролирует скрытый AVPlayer; юзер видит другой AVPlayer (рассинхронизированный). Каждый play/pause/seek нужно реэплаить через <code>updateUIView</code> с 1.5s tolerance, который конфликтует с time observer sync engine. Визуальная десинхронизация гарантирована. CPU/memory тратится на дублирующий decode.",
     "Рендерить AVPlayer из SyncEngine через единый <code>AVPlayerLayer</code>, экспортированный из SyncEngine."),

    ("H4", "AdSessionManager.deinit не инвалидейт таймеры",
     "Services/AdSessionManager.swift:66-68",
     "Комментарий в коде врёт: <code>Timer.scheduledTimer</code> retains target/closure через run loop. <code>deinit</code> только пишет «timers invalidate themselves».",
     "Экземпляры <code>AdSessionManager</code> текут, пока <code>stopAllTimers()</code> не вызван явно. Если комната закрыта без stopAllTimers, таймер продолжает стрелять в мёртвой комнате, вызывая фантомные ad-триггеры.",
     "<code>nonisolated deinit { adTimer?.invalidate(); countdownTimer?.invalidate() }</code>."),

    ("H5", "AdPlayerView.startCountdown Timer не чистится на dismiss",
     "Views/Room/AdPlayerView.swift:73-88",
     "<code>Timer.scheduledTimer</code> создаётся в <code>startCountdown()</code>, инвалидируется только когда <code>countdown &lt;= 0</code>. Если view закрыт раньше 15s, таймер продолжает стрелять.",
     "После раннего dismiss <code>onDismiss</code> вызывается ~15 раз за следующие 15s, каждый раз потенциально триггеря <code>AdSessionManager.finishAd()</code> и рестартуя ad-цикл.",
     "Хранить Timer в <code>@State</code>, инвалидировать в <code>.onDisappear</code>."),

    ("H6", "AudioManager.animateVolume спавнит 10 racing Tasks",
     "Services/AudioManager.swift:103-122",
     "<code>for step in 1...steps { Task { @MainActor in ... player.volume = ... } }</code> — 10 detached Tasks на каждый вызов.",
     "Если <code>animateVolume</code> вызывается дважды за 300ms (mute→unmute), 20 task-ов перекрываются, каждый пишет <code>player.volume</code> с устаревшим delta. Финальная громкость непредсказуема. CPU просыпается 10x за 300ms.",
     "Отменять предыдущий animation Task перед новым: <code>volumeAnimTask?.cancel(); volumeAnimTask = Task { ... }</code>."),

    ("H7", "AmbilightSampler.processFrame передаёт CVPixelBuffer в Task.detached без retain",
     "Views/Room/AmbilightBackground.swift:79-84",
     "<code>Task.detached { ... extractDominantColors(from: pixelBuffer, ...) }</code>. Swift bridges CVPixelBuffer как unretained. Если source <code>AVPlayerItemVideoOutput</code> перерабатывает буфер до выполнения task, читается freed memory.",
     "Use-after-free. Возможны интермиттентные краши в <code>extractDominantColors</code> под memory pressure или на медленных устройствах.",
     "Ручной retain: <code>CVPixelBufferRetain(pixelBuffer); defer { CVPixelBufferRelease(pixelBuffer) }</code>."),

    ("H8", "PlayerUIView CADisplayLink retains self forever",
     "Views/Room/VideoContainerView.swift:157-193",
     "<code>CADisplayLink(target: self, ...)</code> retains target. <code>deinit { displayLink?.invalidate() }</code> работает, но deinit не вызывается, если parent-view остаётся жив, а URL меняется — старый <code>PlayerUIView</code> остаётся с активным display link.",
     "Display link течёт между сменами URL; каждая новая загрузка media добавляет ещё один 4Hz capture callback. После 10 смен media — 10 display links вызывают <code>AmbilightSampler.shared.processFrame</code> per frame.",
     "Override <code>willMove(toSuperview:)</code>: при <code>newSuperview == nil</code> инвалидировать display link, поставить player на pause."),

    ("H9", "RoomView.setupViewModel создаёт свежие сервисы на каждый appear",
     "Views/Room/RoomView.swift:469-511",
     "Каждый раз при показе RoomView: новый <code>APIClient()</code> (без токена), новый <code>WebSocketClient()</code> (без JWT), новый <code>AuthService</code>, <code>SignalingClient</code>, <code>VoiceChatService</code>, <code>SyncEngine</code>, <code>RoomViewModel</code>, <code>RoomSyncManager</code>.",
     "Каждый вход в комнату стартует неаутентифицированную сессию. Сохранённый JWT в AuthService (с app launch) никогда не пробрасывается. Создание комнаты, joining, sync — все 401. При dismiss все сервисы деаллоцируются, но замыкания <code>manager.connect()</code> capture-ят vm strongly, удерживая граф до WebSocket timeout.",
     "Инжектировать сервисы из app-контейнера через <code>EnvironmentValue</code> или конструктор."),

    ("H10", "APIClient.encoder/decoder — mutable shared state на Sendable-классе",
     "Networking/APIClient.swift:5-18",
     "<code>APIClient</code> объявлен <code>Sendable</code>, но <code>JSONEncoder/Decoder</code> хранятся как <code>let</code>. Эти классы НЕ thread-safe (конфигурируют внутреннее состояние при encode/decode). Concurrent <code>request(...)</code> из разных Task-ов разделяют инстансы.",
     "Случайные decode-ошибки, повреждённые request bodies, или краши (EXC_BAD_ACCESS) под нагрузкой. Воспроизводится сложно.",
     "Сделать APIClient <code>actor</code>, либо создавать encoder/decoder на каждый request."),

    ("H11", "APIClient.request&lt;T&gt; не обрабатывает 204 No Content",
     "Networking/APIClient.swift:62-64",
     "<code>case 200..&lt;300: return try decoder.decode(T.self, from: data)</code>. Многие REST-эндпоинты возвращают 204 с пустым body. <code>JSONDecoder.decode</code> бросает на пустом Data.",
     "<code>requestNoBody</code> существует как workaround, но любой, кто случайно использует <code>request&lt;EmptyResponse&gt;</code> против 204-эндпоинта, получает confusing decode-ошибку.",
     "Если <code>data.isEmpty</code> и <code>T</code> — EmptyDecodable, вернуть default."),

    ("H12", "WebSocketClient nonisolated(unsafe) var socket — accessed from multiple isolation contexts",
     "Networking/WebSocketClient.swift:53",
     "<code>private nonisolated(unsafe) var socket: URLSessionWebSocketTask?</code> Accessed from: <code>connectInternal</code> (@MainActor), <code>disconnect</code> (@MainActor), <code>cancelSocketForDeinit</code> (nonisolated), <code>sendRaw</code> (background queue).",
     "Data race на <code>socket?.cancel()</code> и <code>socket = nil</code>, если reconnect срабатывает во время deinit с background queue. Краши возможны под TSan.",
     "Обернуть в lock: <code>private let socketLock = NSLock()</code>."),

    ("H13", "RoomViewModel.messages не ограничен — длинные комнаты текут memory",
     "ViewModels/RoomViewModel.swift:13 + Views/Room/RoomView.swift:158-167",
     "<code>var messages: [ChatMessage] = []</code>. Каждое входящее сообщение append-ится. Нет upper bound. <code>RoomSyncManager</code> имеет <code>maxChatMessages = 200</code>, но RoomViewModel поддерживает свой массив.",
     "В 6-часовой комнате с активным чатом массив растёт до десятков тысяч <code>ChatMessage</code> (по ~200 байт каждый) → 10+ MB мёртвой истории. SwiftUI LazyVStack ре-рендерится на каждый append.",
     "Cap на 200 как в RoomSyncManager: <code>if messages.count &gt; maxMessages { messages.removeFirst(...) }</code>."),

    ("H14", "AuthService.init мутирует currentUser из detached Task",
     "Services/AuthService.swift:32-35",
     "<code>Task { @MainActor in self.currentUser = user }</code>. AuthService не <code>@MainActor</code>, только <code>currentUser</code> аннотирован. <code>RaveCloneApp.checkAuth</code> сразу после init вызывает <code>authService.currentUser()</code>, racing с этим detached task.",
     "Cold launch: <code>currentUser()</code> возвращает nil, потому что restore-task ещё не выполнился. <code>isSignedIn = false</code>, splash исчезает на LoginView, через 200ms currentUser появляется — юзер видит флэш login-экрана на каждом cold launch с валидной сессией.",
     "Сделать AuthService полностью <code>@MainActor</code>, либо restore синхронно в init через Mutex/actor."),
]

for bid, title, fref, what, impact, fix in ios_high:
    story.append(bug_entry("HIGH", SEV_HIGH, bid, title, fref, what, impact, fix))

story.append(PageBreak())

# iOS Medium
story.append(Paragraph("🟡 MEDIUM (16) — race / state / @MainActor violations", S["h3"]))
story.append(Spacer(0, 4))

ios_med = [
    ("M1", "SyncEngine.handleSeek extrapolation может реверсировать реальные seek",
     "Services/SyncEngine.swift:389-417",
     "<code>isStatePulse = elapsedSinceEvent &lt; stateBroadcastInterval + 1</code> — эвристика. Реальный seek и периодический state broadcast могут оба попасть в 3s окно.",
     "Реальные seek от хоста молча реверсируются. UI показывает seek, затем snap-back.",
     "Добавить distinct command value для state pulses vs explicit seeks, либо поле <code>isStatePulse: Bool</code> в SyncMessage."),

    ("M2", "SignalingMessage.decode использует raw.contains для определения типа",
     "Networking/SignalingMessage.swift:43-47",
     "<code>guard raw.contains(\"\\\"kind\\\"\")</code>. Любое chat-сообщение, содержащее литерал <code>\"kind\"</code>, пройдёт guard и будет попытано как SignalingMessage decode.",
     "Occasional swallowed chat messages. Хрупко.",
     "Использовать dedicated <code>type</code> field для routing, либо decode через JSONDecoder с проверкой kind после."),

    ("M3", "RoomViewModel.routeInbound декодирует каждое сообщение до 4 раз",
     "ViewModels/RoomViewModel.swift:217-250",
     "Последовательные <code>try? JSONDecoder().decode(...)</code> для SyncMessage, ChatMessage, ParticipantUpdate.",
     "CPU waste на hot path; risk mis-routing, если поля overlap-ят.",
     "Peek single <code>type</code> field once: <code>JSONSerialization.jsonObject</code> + switch."),

    ("M4", "RoomSyncManager.handleRawMessage — тот же паттерн multi-decode",
     "Services/RoomSyncManager.swift:195-221",
     "Sequence: WSPingPong → AdCommandPayload → SyncMessage → RoomEventEnvelope.",
     "Тот же, что M3.",
     "Тот же fix — единый type-dispatch."),

    ("M5", "StoreManager.restorePurchases — фактически no-op",
     "Services/StoreManager.swift:115-126",
     "<code>AppStore.sync()</code> только ре-синхронит StoreKit transaction cache. НЕ итерирует <code>Transaction.currentEntitlements</code> для проверки активных подписок.",
     "Юзеры, переустанавливающие приложение на новом устройстве, жмут «Restore Purchases» → молча ничего не происходит → думают, что подписка потеряна. App Review reject.",
     "После <code>AppStore.sync()</code>: <code>for await result in Transaction.currentEntitlements { ... handleSuccessfulPurchase(t) }</code>."),

    ("M6", "PremiumStatusManager.isPremium грузится из UserDefaults каждый launch",
     "Services/PremiumStatusManager.swift:112-133",
     "<code>loadPersistedState</code> читает <code>rave_user_is_premium</code> из UserDefaults и доверяет. В комбинации с C9 локальный premium state полностью под контролем атакующего.",
     "Premium bypass персистит между запусками. Даже при правильном IAP локальный state может расходиться с серверным.",
     "Source of truth должен быть серверный <code>User.isPremium</code> (из <code>/api/auth/me</code>). Local cache — только hint."),

    ("M7", "APIClient.requestNoBody не обрабатывает 404",
     "Networking/APIClient.swift:124-131",
     "<code>request&lt;T&gt;</code> имеет <code>case 404: throw .notFound</code>, но <code>requestNoBody</code> только 401 и default. Callers не могут отличить «not found» от «server error».",
     "<code>leaveRoom</code> на уже удалённой комнате показывает «Ошибка сервера (404): Request failed» вместо «Комната не найдена».",
     "Отразить switch из <code>request&lt;T&gt;</code>."),

    ("M8", "Room.isHost всегда возвращает false (dead computed property)",
     "Models/Room.swift:25-28",
     "<code>var isHost: Bool { false }</code>. Комментарий врёт: «Set at runtime by ViewModel based on current user» — но никакой код это не делает.",
     "Dead/misleading code; потенциальный silent failure, если кто-то начнёт использовать.",
     "Удалить property или реализовать: <code>func isHost(userId: String) -&gt; Bool { hostID == userId }</code>."),

    ("M9", "OrientationManager.isPortrait — неправильная precedence",
     "Utilities/OrientationManager.swift:38-48",
     "<code>first?.interfaceOrientation.isPortrait ?? true && (...)</code>. <code>??</code> имеет ниже precedence, чем <code>&&</code>. Парсится как <code>?? (true && (...))</code>.",
     "<code>OrientationManager.isPortrait</code> возвращает true для некоторых landscape states, когда <code>UIDevice.current.orientation == .unknown</code>.",
     "Добавить явные скобки: <code>(first?.interfaceOrientation.isPortrait ?? true) && (...)</code>."),

    ("M10", "RoomView вызывает voiceChat.startCall дважды",
     "Views/Room/RoomView.swift:79-90",
     "<code>.task</code> блок: сначала <code>await viewModel.joinRoomFlow()</code> (который сам вызывает startCall на строке 97), затем ещё <code>try? await voiceChat?.startCall(roomId: room.id)</code>.",
     "Wasted work; потенциальная state confusion, если первый вызов упал mid-setup, а второй succeed.",
     "Удалить redundant вызов на строке 83."),

    ("M11", "WebSocketClient.handleReceiveResult реармится на main actor",
     "Networking/WebSocketClient.swift:286-293",
     "На .success <code>receiveMessage()</code> вызывается снова, что зовёт <code>socket?.receive { ... Task { @MainActor in handleReceiveResult } }</code>. Каждый receive hop — один main-actor cycle.",
     "Burst из 100 сообщений от сервера сериализуется через 100 main-actor hops, блокируя UI. UI stutter во время chat flood.",
     "Process messages на background queue, hop to MainActor только для delegate dispatch."),

    ("M12", "WebSocketClient.sendRaw error handler — fragile DispatchQueue.main.async",
     "Networking/WebSocketClient.swift:237-246",
     "<code>socket?.send</code> completion на background queue. <code>self?.handleDisconnect</code> — @MainActor. <code>DispatchQueue.main.async</code> работает, но под strict concurrency может flagged.",
     "Strict concurrency warnings; поведение OK, но хрупко.",
     "Заменить на <code>Task { @MainActor [weak self] in ... }</code>."),

    ("M13", "FriendManager.init вызывает loadAll() до установки authToken",
     "Services/FriendManager.swift:28-31",
     "<code>init() { Task { await loadAll() } }</code>. <code>loadAll</code> → <code>loadFriends</code> → <code>guard api.authToken != nil else { return }</code>. Поскольку FriendManager owns own APIClient (C5), authToken всегда nil.",
     "Friends list остаётся пустым на первом launch. Даже после fix C5, если RaveCloneApp конструирует FriendManager ДО завершения restore-токена в AuthService, Task может выполниться раньше.",
     "Триггерить <code>loadAll</code> из <code>RaveCloneApp.checkAuth</code> после <code>bridgeAuthToken</code>."),

    ("M14", "RoomSyncManager.handleAppBackground 30s timeout — stuck .reconnecting",
     "Services/RoomSyncManager.swift:385-397",
     "30s background task hard-disconnects WS. Если OS убивает app до foreground handler, <code>didDisconnectInBackground</code> остаётся true, следующий launch начинается со stale <code>connectionStatus = .reconnecting</code>.",
     "Stuck .reconnecting state на cold launch.",
     "Reset <code>didDisconnectInBackground = false</code> в <code>init</code>."),

    ("M15", "HomeView.startCTACollapseTimer Timer в @State без cleanup",
     "Views/Home/HomeView.swift:33, 469-475",
     "<code>@State private var ctaCollapseTimer: Timer?</code>. SwiftUI может пересоздать view и reset @State на identity changes. Нет <code>.onDisappear</code> cleanup.",
     "Timer fires на dismissed HomeView, возможно выставляя state на stale view.",
     "Использовать <code>Task</code> с <code>Task.sleep</code>, либо invalidate в <code>.onDisappear</code>."),

    ("M16", "WebSocketClient.isConnectedBridge uses MainActor.assumeIsolated",
     "Networking/WebSocketClient.swift:451-455",
     "<code>nonisolated var isConnectedBridge: Bool { MainActor.assumeIsolated { self.isConnected } }</code>. <code>assumeIsolated</code> crash-нет, если вызвано из non-MainActor контекста.",
     "Crash risk, если non-MainActor код тронет <code>isConnectedBridge</code>.",
     "Использовать только с documented precondition, либо предоставить async accessor."),
]

for bid, title, fref, what, impact, fix in ios_med:
    story.append(bug_entry("MED", SEV_MED, bid, title, fref, what, impact, fix))

story.append(PageBreak())

# iOS Low
story.append(Paragraph("🟢 LOW (16) — hygiene / polish / deprecations", S["h3"]))
story.append(Spacer(0, 4))

ios_low = [
    ("L1", "Захардкоженные русские строки в views (байпас LocalizationManager)",
     "Views/Home/HomeView.swift (lines 175, 260, 295, 324, 518, 575), RoomCreationView.swift (14 мест), AdminPanelView.swift (8 мест), PrivacySettingsView.swift",
     "В приложении есть <code>LocalizationManager</code> с тремя языками (ru/en/zh), но большинство UI обходит его.",
     "English и Chinese локализации неполные; переключение языка в settings не обновляет эти экраны.",
     "Добавить недостающие ключи в <code>L10n.Key</code>, использовать <code>loc.string(.key)</code>."),

    ("L2", "Room.mockRooms — mock-данные в production",
     "Models/Room.swift:105-143",
     "Production-код шлёт 5 фейковых комнат («Дюна 2», «Lo-Fi Chill» и т.д.) как fallback, когда сервер 401 или пустой.",
     "Если сервер возвращает empty/401, юзеры видят фейковые «активные» комнаты с фейковым participant count — misleading.",
     "Удалить <code>mockRooms</code> или gate behind <code>#if DEBUG</code>."),

    ("L3", "WSClient.connectionStats возвращает untyped [String: Any]",
     "Networking/WebSocketClient.swift:428-437",
     "Словарь с mixed types (Bool, Int, String). Not Sendable, not type-safe.",
     "Любой consumer должен cast; нет compile-time гарантий.",
     "Вернуть <code>struct ConnectionStats: Sendable { ... }</code>."),

    ("L4", "ReactionOverlayView — dead code",
     "Views/Room/ReactionOverlayView.swift",
     "Структ существует, есть previews, но никогда не инстанцируется. <code>RoomView</code> использует <code>ReactionSpriteOverlay</code>.",
     "~120 строк мёртвого кода.",
     "Удалить файл."),

    ("L5", "PrivacySettingsView toggles не персистятся и не синхронизируются",
     "Views/Settings/PrivacySettingsView.swift:8-10",
     "<code>profileVisibility</code>, <code>onlineStatus</code>, <code>readReceipts</code> — <code>@State</code> без UserDefaults persistence и без backend call.",
     "Юзер переключает privacy → уходит с экрана → настройки сбрасываются.",
     "Персистить в UserDefaults + POST на <code>/api/users/privacy</code>."),

    ("L6", "LoginView Google/Apple sign-in — fake",
     "Views/Auth/LoginView.swift:207-248",
     "Тап по Google или Apple показывает spinner, через 1.5s fallback на email form. Реального OAuth flow нет.",
     "Misleading UI. Apple Sign In обязателен, если предлагается third-party sign-in (Guideline 4.8).",
     "Реализовать <code>ASAuthorizationAppleIDProvider</code> или убрать кнопки."),

    ("L7", "AmbilightBackground использует @StateObject для shared singleton",
     "Views/Room/AmbilightBackground.swift:20",
     "<code>@StateObject private var sampler = AmbilightSampler.shared</code>. <code>@StateObject</code> означает, что SwiftUI owns lifecycle, но это singleton — два AmbilightBackground будут думать, что они владеют.",
     "Conceptual misuse; работает, потому что singleton игнорирует ownership semantics.",
     "Использовать <code>@ObservedObject</code> для shared singletons."),

    ("L8", "RoomView shareSheet строит неправильный URL",
     "Views/Room/RoomView.swift:119-123",
     "<code>URL(string: \"https://raveclone.com/join/\\(room.code)\")</code>. Domain — <code>raveclone.com</code>, но <code>DeepLinkRouter.domain</code> — <code>raveclone.app</code>, <code>ShareManager.shareBaseURL</code> — <code>raveclone.app</code>. Path <code>/join/&lt;code&gt;</code>, но DeepLinkRouter распознаёт только <code>/r/&lt;code&gt;</code> или <code>/u/&lt;userId&gt;</code>.",
     "Получатели share sheet получают URL, который открывает 404 в браузере.",
     "Использовать <code>ShareManager.shareURL(for: room.id, code: room.code)</code>."),

    ("L9", "EnergyController observer никогда не удаляется",
     "Views/Room/AmbilightBackground.swift:171-181",
     "<code>EnergyController.shared</code> регистрирует NotificationCenter observer в init, но никогда не remove-ит. Singleton, поэтому OK на практике.",
     "Если класс перестанет быть singleton — leak.",
     "<code>deinit { NotificationCenter.default.removeObserver(self) }</code>."),

    ("L10", "RaveCloneApp.handleDeepLink хардкодит «Пользователь» для friend invite",
     "RaveCloneApp.swift:135",
     "<code>friendInviteAlert = FriendInviteAlert(userId: userId, username: \"Пользователь\")</code>.",
     "Username всегда «Пользователь». Реальный username должен быть с сервера.",
     "Fetch через <code>FriendManager</code> или <code>/api/users/:id</code>."),

    ("L11", "Backend URLs разнесены между Railway и raveclone.app",
     "Services/MediaService.swift:38 vs Networking/APIClient.swift:23",
     "<code>APIClient</code>: <code>https://xpkcakpkfewp-ofewk-pkv-production.up.railway.app/api</code>. <code>MediaService</code>: <code>https://raveclone.app/api</code>. <code>YouTubeSearchService</code>: <code>raveclone.app</code>. <code>YandexAuthService</code>: <code>raveclone.app</code>.",
     "Auth/room операции идут на Railway, media extraction — на raveclone.app (которого может не существовать).",
     "Centralize base URL в едином <code>Config</code> struct."),

    ("L12", "RaveCloneApp.init не пробрасывает auth token в RoomService",
     "RaveCloneApp.swift:43-50",
     "<code>RoomService(api: api)</code> разделяет api с AuthService — работает. Но <code>MediaService</code> имеет собственный <code>setAuthToken</code>, обновляется только через <code>bridgeAuthToken()</code>. Если <code>bridgeAuthToken</code> вызывается раньше, чем <code>authService.currentUser</code> populate-ится, <code>getFreshToken()</code> возвращает старый токен.",
     "Media operations могут работать с истёкшим токеном.",
     "Subscribe <code>MediaService.setAuthToken</code> на token-change publisher в AuthService."),

    ("L13", "AuthService.deleteAccount не удаляет на самом деле",
     "Services/AuthService.swift:111-114",
     "<code>func deleteAccount() async throws { /* TODO: добавить DELETE /api/auth/me */ try await signOut() }</code>.",
     "GDPR/CCPA right-to-delete violation. Данные аккаунта персистят на сервере.",
     "Реализовать <code>DELETE /api/auth/me</code> на backend, вызывать перед signOut."),

    ("L14", "MarqueeMessageView.width использует NSString.size",
     "Views/Room/MarqueeMessageView.swift:64-67",
     "<code>NSString.size(withAttributes:)</code> возвращает approx size, не учитывает line breaks или emoji rendering differences. Используется для вычисления <code>scrollDistance</code>.",
     "Minor visual glitch на длинных сообщениях с emoji.",
     "Использовать <code>Text(...).measureSize()</code> via PreferenceKey."),

    ("L15", "WebSocketClient.connectionStats — force-unwrap after nil-check",
     "Networking/WebSocketClient.swift:435",
     "<code>notifyConnectedIfNeeded</code> (строка 421) делает <code>Logger.ws.info(\"Restoring room session: \\(activeRoomID!)\")</code> после <code>if activeRoomID != nil</code> check. Force-unwrap безопасен, но fragile при рефакторинге.",
     "Crash risk при рефакторинге без сохранения nil-check.",
     "Использовать <code>if let</code> binding."),

    ("L16", "SyncEngine.deinit трогает @MainActor state",
     "Services/SyncEngine.swift:88-92",
     "<code>deinit { player?.pause(); if let observer = timeObserver { player?.removeTimeObserver(observer) } }</code>. <code>player</code> и <code>timeObserver</code> — @MainActor ivars. <code>deinit</code> — nonisolated по умолчанию в Swift 5.10+.",
     "Concurrency violation под strict concurrency.",
     "Mark <code>deinit nonisolated</code> явно + <code>MainActor.assumeIsolated</code>, либо move teardown в <code>cleanup()</code> method."),
]

for bid, title, fref, what, impact, fix in ios_low:
    story.append(bug_entry("LOW", SEV_LOW, bid, title, fref, what, impact, fix))

story.append(PageBreak())

# ── BACKEND SECTION ────────────────────────────────────────────────────────
story.append(section_header("04", "Backend (Node.js / Fastify) — 34 бага"))
story.append(Paragraph(
    "Аудит 24 файлов: index, config, middleware/auth, websocket manager+handler, 7 routes (auth, auth-social, rooms, "
    "messages, friends, admin, media-v2, profile), services (push, youtube, extractors), Prisma schema, Dockerfile, env.example.",
    S["body"]
))
story.append(Spacer(0, 8))

story.append(Paragraph("🔴 CRITICAL (5) — security holes", S["h3"]))
story.append(Spacer(0, 4))

be_crit = [
    ("B1", "Admin-роуты никогда не аутентифицируются — весь admin panel возвращает 401",
     "server/src/routes/admin.ts:24-47",
     "Регистрируется <code>preHandler</code>, который читает <code>request.user</code>, но никогда не вызывает <code>fastify.authenticate</code>. <code>@fastify/jwt</code> не авто-verify — <code>request.user</code> всегда undefined, каждый admin-запрос попадает в <code>if (!user) return reply.status(401)</code>.",
     "Весь admin panel неработоспособен. <code>prisma.user.findUnique({ where: { id: user.id } })</code> на строке 34 — dead code. Бан/модерация не работают.",
     "Добавить <code>{ preHandler: [fastify.authenticate] }</code> на каждый admin route, либо вызывать <code>await request.jwtVerify()</code> внутри hook."),

    ("B2", "request.user.sub === undefined в messages/friends/profile — 12 сломанных хендлеров",
     "server/src/middleware/auth.ts:54 + messages.ts:7,15 + friends.ts:15,27,33,45,52 + profile.ts:7,13,21,45,52",
     "Middleware ставит <code>request.user = { id, username, email }</code> (без <code>sub</code>). Но 12 хендлеров читают <code>request.user.sub</code>. Для <code>create</code>-вызовов (DM, FriendRequest, Friendship, WatchHistory) Prisma бросает — поле non-null → 500. Для <code>findMany</code>/<code>count</code> вызовов <code>where: { userID: undefined }</code> молча матчит все строки.",
     "Каждый DM send, friend request, friend accept, watch-history save, premium fetch, subscription create падает с 500. Для list-запросов — данные других юзеров видны всем.",
     "Заменить каждое <code>request.user.sub</code> на <code>request.user.id</code>."),

    ("B3", "Чат-имперсонация — senderID/senderName берутся из payload клиента",
     "server/src/websocket/ws-manager.ts:634-651",
     "<code>ChatMessage.create({ senderID: msg.senderID, ... })</code> — senderID берётся из клиентского payload. Broadcast: <code>{ ...msg, text, id, timestamp }</code> спредит senderID, senderName, senderRole из клиента.",
     "Любой юзер может персистить чаты под чужим ID и бродкастить их как «Admin»/«system» всей комнате.",
     "Игнорировать клиентские identity fields; использовать <code>conn.user.id</code>, <code>conn.user.username</code>, <code>conn.user.role</code>."),

    ("B4", "Banned-юзеры могут signin и подключаться по WS",
     "server/src/routes/auth.ts:77-120 + auth-social.ts:50-130 + ws-handler.ts:111-143",
     "signin и auth-social никогда не читают <code>bannedUntil</code> перед выдачей JWT. <code>authenticateWs</code> verify-ит JWT signature, но не ищет юзера в DB — даже удалённые юзеры продолжают работать. Admin bans ставят bannedUntil и зовут disconnectUserEverywhere, но JWT остаётся валидным 7 дней, юзер может сразу re-signin.",
     "Баны не работают. Забаненный юзер заходит через 5 секунд.",
     "В <code>authenticate</code> и <code>authenticateWs</code> fetch юзера из DB, reject если <code>bannedUntil &gt; now</code>. Добавить server-side jti blacklist или short-lived access + refresh tokens."),

    ("B5", "Free premium bypass — POST /api/users/me/create-subscription",
     "server/src/routes/profile.ts:51-58",
     "Любой авторизованный юзер POST <code>{ plan: \"monthly\" }</code> → сервер ставит <code>isPremium: true, premiumUntil: now + 30d</code>. Нет Stripe/RevenueCat/App-Store-Server webhook, нет signature check, нет receipt validation.",
     "Полный обход платной подписки. Любой может получить premium бесплатно.",
     "Удалить self-service upgrade route; <code>isPremium</code> ставить только из verified payment-provider webhook."),
]

for bid, title, fref, what, impact, fix in be_crit:
    story.append(bug_entry("CRIT", SEV_CRIT, bid, title, fref, what, impact, fix))

story.append(PageBreak())

story.append(Paragraph("🟠 HIGH (11) — race / leaks / SSRF / arg-injection", S["h3"]))
story.append(Spacer(0, 4))

be_high = [
    ("B6", "Несколько new PrismaClient() — bypass singleton",
     "messages.ts:3 + friends.ts:3 + profile.ts:3",
     "<code>const prisma = new PrismaClient()</code> в трёх файлах, минуя <code>config/db.ts</code> singleton.",
     "Лишние connection pools, Postgres exhaustion под нагрузкой.",
     "Импортировать shared <code>prisma</code> из <code>config/db.ts</code>."),

    ("B7", "JWT в URL query string для WS",
     "ws-handler.ts:115-116",
     "<code>new URL(req.url).searchParams.get('token')</code>. JWT в URL утечёт в proxy logs, browser history, Referer header.",
     "Credential disclosure через логи.",
     "Использовать <code>Sec-WebSocket-Protocol</code> subprotocol или first-message auth."),

    ("B8", "authenticateWs хардкодит role: \"USER\"",
     "ws-handler.ts:124,134",
     "<code>const user = { id: payload.sub, username: payload.username, role: 'USER' }</code>. Все admin WS-фичи (<code>ws-manager.ts:197-220</code> admin-join broadcast) — dead code.",
     "Админ-функционал через WS недоступен. Невозможно модерировать через WS.",
     "Fetch юзера из DB, populate реальный role."),

    ("B9", "disconnectAll() вызывается, но не определена",
     "index.ts:124-128 vs ws-manager.ts",
     "В <code>index.ts</code> SIGTERM handler вызывает <code>wsManager.disconnectAll()</code>, но grep подтверждает — такого метода в <code>ws-manager.ts</code> нет.",
     "На SIGTERM WS-клиенты не получают close frame, heartbeat interval продолжает стрелять, process падает.",
     "Добавить реальный <code>disconnectAll()</code> method."),

    ("B10", "SSRF в /api/media/extract и /probe",
     "services/extractors/web.ts:65,71,83 + mediaExtractor.ts:160-162",
     "<code>fetch(url)</code> на attacker-supplied URLs без allowlist. Catch-all <code>web</code> fallback для любого URL.",
     "Атака на AWS IMDSv1, внутренние сервисы, localhost DB probes.",
     "Private-IP blocklist после DNS lookup, redirect cap, body size limit, удалить catch-all web fallback."),

    ("B11", "detectSource использует lower.includes(d) для domain matching",
     "mediaExtractor.ts:149-151",
     "<code>lower.includes(d)</code> — bypassable через <code>https://evil.com/?x=netflix.com</code>.",
     "Неверная классификация источника.",
     "Парсить через <code>new URL()</code>, сравнивать <code>hostname</code>."),

    ("B12", "Argument injection в yt-dlp — URL без --",
     "youtube.ts:100-110, 261-270 + vk.ts:24-29 + rutube.ts:25-30",
     "URL передаётся как trailing arg без <code>--</code> сепаратора. Атакующий может передать <code>--exec=...</code> или <code>--plugin-dirs=...</code> как URL.",
     "RCE-adjacent. Выполнение произвольных команд через yt-dlp plugins.",
     "Вставить <code>\"--\"</code> перед URL arg."),

    ("B13", "/ws/stats debug endpoint без аутентификации",
     "ws-handler.ts:38-40",
     "Эндпоинт отдаёт total connections, room IDs, host IDs, participant counts без auth.",
     "Утечка чувствительной инфо — кто в каких комнатах, сколько активных юзеров.",
     "Gate behind admin auth или удалить в prod."),

    ("B14", "JWT_SECRET defaults to \"dev-secret-change-me\", CORS_ORIGIN = \"*\" + credentials: true",
     "config/index.ts:37,43 + index.ts:48",
     "<code>JWT_SECRET = process.env.JWT_SECRET ?? 'dev-secret-change-me'</code>. <code>CORS_ORIGIN = ['*']</code> с <code>credentials: true</code>.",
     "Пропущенные env vars в prod → куётся любой JWT + reflected-origin CORS.",
     "<code>required('JWT_SECRET')</code>; reject <code>['*']</code> когда <code>credentials: true</code>."),

    ("B15", "Guest username collision после 9000 аккаунтов",
     "auth-social.ts:113",
     "<code>Raver_${1000..9999}</code> с <code>@unique</code>. После 9000 гостей → P2002 → 500. Нет per-IP cap на <code>/api/auth/guest</code>.",
     "DB pollution; сервис падает после 9000 гостей.",
     "Использовать nanoid suffix; stricter per-IP rate limit на /guest."),

    ("B16", "VK token verification не доказывает владение приложением",
     "auth-social.ts:300-307",
     "<code>users.get</code> принимает любой валидный VK token из любого app. Email никогда не возвращается users.get (требует OAuth scope), поэтому <code>upsertSocialUser</code> всегда синтезирует email → несколько строк на VK-юзера.",
     "Любой VK token логинит. Дубликаты пользователей.",
     "Использовать VK <code>secure.checkToken</code> с <code>VK_CLIENT_SECRET</code>; email только из OAuth callback."),
]

for bid, title, fref, what, impact, fix in be_high:
    story.append(bug_entry("HIGH", SEV_HIGH, bid, title, fref, what, impact, fix))

story.append(PageBreak())

story.append(Paragraph("🟡 MEDIUM (10) + 🟢 LOW (6)", S["h3"]))
story.append(Spacer(0, 4))

be_med_low = [
    ("B17", "🟡 request.user.role === undefined в regular routes",
     "auth.ts:47",
     "<code>select: { id: true, username: true, email: true }</code> — без role. <code>request.user.role</code> всегда undefined в regular route handlers.",
     "Role-based checks в regular routes не работают.",
     "Добавить <code>role: true</code> в select."),

    ("B18", "🟡 authenticate трактует только \"Unauthorized\" как 401, всё остальное 500",
     "auth.ts:55-61",
     "<code>catch (err) { if (err.message === 'Unauthorized') return 401; return 500 }</code>. Expired tokens → 500.",
     "Юзер видит «Ошибка сервера» вместо «Сессия истекла, войдите снова».",
     "Catch <code>FAST_JWT_*</code> error codes, возвращать 401."),

    ("B19", "🟡 MAX_ROOM_PARTICIPANTS = 20 глобальный cap игнорирует per-room maxParticipants",
     "ws-manager.ts:191",
     "<code>if (state.participants.size &gt;= MAX_ROOM_PARTICIPANTS)</code> — глобальный cap 20. <code>room.maxParticipants: 2</code> всё равно допускает 20 WS-коннектов.",
     "Premium-комнаты с caps 50 работают как 20-cap; приватные 2-человечные комнаты могут принять 20.",
     "Load <code>room.maxParticipants</code> в <code>RoomRuntimeState</code>."),

    ("B20", "🟡 Нет host migration — host disconnect сразу деактивирует комнату",
     "ws-manager.ts:245-260",
     "При дисконнекте хоста комната сразу деактивируется. Network blip kills room для всех гостей.",
     "Комната «умирает» при кратковременной потере сети у хоста.",
     "Promote longest-tenured member или 60s grace period."),

    ("B21", "🟡 chatRateLimits map никогда не чистится",
     "ws-manager.ts:73",
     "<code>Map&lt;userId, { count, resetAt }&gt;</code> — одна запись на уникального юзера навсегда.",
     "Memory leak — карта растёт бесконечно.",
     "Delete в <code>unregister</code> когда последний conn закрылся; использовать <code>lru-cache</code>."),

    ("B22", "🟡 cleanupRoom вызывает redis.del без await/.catch()",
     "ws-manager.ts:288-293",
     "<code>redis.del(...); redis.del(...)</code> — fire-and-forget. Если Redis упал → unhandled rejection → process crash (Node 15+ default).",
     "Process crash при потере Redis.",
     "<code>await Promise.all([...]).catch(...)</code>."),

    ("B23", "🟡 Redis SREM на disconnect удаляет юзера из participant set даже если у него есть другой открытый коннект",
     "ws-manager.ts:243",
     "SET дедуплицирует по value, поэтому второй коннект невидим для cross-instance reads.",
     "Юзер с двумя вкладками: при закрытии одной вторая становится «невидимой» для других инстансов.",
     "Только SREM когда нет remaining connID для этого юзера в roomID."),

    ("B24", "🟡 connID = ws_${user.id}_${Date.now()} — коллизия при коннекте в same ms",
     "ws-manager.ts:88",
     "<code>const connID = `ws_${user.id}_${Date.now()}`</code>. Если тот же юзер коннектится дважды в одну ms, первый conn orphan-ится с live handlers но unregistered.",
     "Lost connection, leak handlers.",
     "Использовать <code>nanoid()</code>."),

    ("B25", "🟡 Heartbeat interval == timeout (оба 45s)",
     "config/index.ts:50 + ws-manager.ts:75",
     "<code>checkHeartbeats</code> запускается каждые 45s, timeout тоже 45s. Dead conn detected в 45-90s.",
     "Долгое обнаружение мёртвых соединений.",
     "Запускать checkHeartbeats каждые 30s."),

    ("B26", "🟡 Нет global error handler — Zod errors leak stack traces",
     "index.ts",
     "Нет <code>setErrorHandler</code> нигде (grep confirmed).",
     "Zod errors возвращают stack trace клиенту — info disclosure.",
     "Добавить Zod-aware error handler, возвращающий consistent <code>{ error, issues }</code>."),

    ("B27", "🟢 Нет unhandledRejection/uncaughtException handlers в index.ts",
     "index.ts",
     "С многими fire-and-forget promises одна rejection убивает process.",
     "Process crash на unhandled rejection.",
     "Register оба, log + graceful shutdown."),

    ("B28", "🟢 loadConfig(console as any) — _log unused",
     "config/index.ts:31",
     "Параметр передаётся, но не используется.",
     "Dead parameter.",
     "Удалить параметр."),

    ("B29", "🟢 generateRoomCode modulo bias",
     "utils/index.ts:12",
     "<code>chars[Math.floor(Math.random() * chars.length)]</code> — modulo bias.",
     "Неравномерное распределение кодов комнат.",
     "<code>crypto.randomInt(0, chars.length)</code>."),

    ("B30", "🟢 fastify.jwt.sign(payload, { sub: user.id }) — второй аргумент wrong type",
     "auth.ts:58-60 + auth-social.ts:173-176",
     "Передаётся second arg неверного типа, молча игнорируется.",
     "sub не устанавливается в JWT payload.",
     "Удалить второй arg, добавить sub в payload объект."),

    ("B31", "🟢 Dead code: youtubeService decorated в index.ts:69-73, но media-v2.ts:26 создаёт свой",
     "index.ts + media-v2.ts",
     "Декорация бесполезна — каждый route создаёт свой инстанс.",
     "Лишний код + несогласованная конфигурация.",
     "Удалить декорацию или использовать её."),

    ("B32", "🟢 Schema integrity gaps: PlaybackState.roomID и WatchHistory.roomID без FK к Room",
     "schema.prisma:240,222",
     "Нет foreign key к Room. Позволяет баги B17 (произвольный roomID в POST /me/history).",
     "任意 roomID в playback state и watch history.",
     "Добавить <code>room Room? @relation(...)</code> к обеим моделям."),

    ("B33", "🟢 UserRole enum имеет MODERATOR и FOUNDER — ни один code path не читает",
     "schema.prisma:14-19",
     "Значения объявлены, но не используются.",
     "Dead schema.",
     "Реализовать room-scoped permissions или удалить."),
]

# Last B34 - special: POST /api/rooms/:id/playback no host check
be_med_low.append((
    "B34", "🟠 POST /api/rooms/:id/playback без host-check и без Zod validation",
    "rooms.ts:484-502",
    "<code>body = request.body as { time, isPlaying }</code> — raw cast. Нет <code>findUnique</code>, нет проверки <code>room.hostID === user.id</code>, нет zod-схемы. <code>PlaybackState</code> не имеет FK к Room.",
    "Любой авторизованный юзер может спамить upsert для любого roomID (включая случайные строки).",
    "Zod-validate body, <code>findUnique</code> room, требовать <code>room.hostID === user.id</code>, добавить FK в schema."
))

for bid, title, fref, what, impact, fix in be_med_low:
    # extract severity from title
    if title.startswith("🔴"):
        bg = SEV_CRIT
    elif title.startswith("🟠"):
        bg = SEV_HIGH
    elif title.startswith("🟡"):
        bg = SEV_MED
    else:
        bg = SEV_LOW
    sev_label = title[:3].strip()
    clean_title = title[3:].strip()
    story.append(bug_entry(sev_label, bg, bid, clean_title, fref, what, impact, fix))

story.append(PageBreak())

# ── REACT NATIVE SECTION ──────────────────────────────────────────────────
story.append(section_header("05", "React Native (Expo) — 61 баг"))
story.append(Paragraph(
    "Аудит 31 файла: App.tsx, navigation, auth store, WS/WebRTC/DRM/ScreenShare services, 7 screens, 5 components, "
    "native manifests/plists.",
    S["body"]
))
story.append(Spacer(0, 8))

story.append(Paragraph("🔴 CRITICAL (8) — security / auth bypass", S["h3"]))
story.append(Spacer(0, 4))

rn_crit = [
    ("R1", "Ngrok auth token захардкожен в VCS",
     "mobile/scripts/patch-ngrok.js:18",
     "<code>'3Fk4HLUubHn0SxiisuL6tbuiSom_41ehdA3NACxFaNNEZ8F3m'</code> прямо в коде.",
     "Утечка credentials. Любой может использовать ваш ngrok-аккаунт.",
     "Читать из <code>process.env.NGROK_AUTH_TOKEN</code>; немедленно ротировать утёкший token."),

    ("R2", "JWT в plain AsyncStorage",
     "mobile/src/store/authStore.ts:43-44, 55, 78, 87",
     "<code>AsyncStorage.setItem('auth_token', token)</code>. AsyncStorage — нешифрованное SQLite/plist.",
     "Token disclosure → account takeover.",
     "Использовать <code>expo-secure-store</code> (<code>SecureStore.setItemAsync</code> с <code>WHEN_UNLOCKED</code>)."),

    ("R3", "DRM-куки Netflix/Кинопоиск в AsyncStorage",
     "mobile/src/services/DrmSessionManager.ts:91, 179",
     "Session cookies платных сервисов в нешифрованном хранилище.",
     "Утечка сессий платных сервисов — кто угодно с доступом к filesystem может использовать ваш Netflix.",
     "Перенести куки в SecureStore keyed per serviceID; в AsyncStorage держать только metadata."),

    ("R4", "Offline-guest fallback — обход auth gate",
     "mobile/src/screens/AppAuthScreen.tsx:108-118",
     "При network blip: stores synthetic <code>offline_*</code> token, flips <code>isAuthenticated: true</code>.",
     "Полный обход auth gate на любой сетевой проблеме. Любой может «войти» офлайн.",
     "Удалить fallback; показывать «Network unavailable» error."),

    ("R5", "Demo exchange — trivial auth bypass",
     "mobile/src/screens/AppAuthScreen.tsx:144, 212",
     "Alert OK button: <code>exchange(\"google\", \"google\", { idToken: \"demo_google_token\" })</code>. То же для VK.",
     "Тривиальный auth bypass — любой может залогиниться как google-юзер с demo-токеном.",
     "Удалить demo exchange; показывать configuration error."),

    ("R6", "console.log URL с JWT — утечка в logcat",
     "mobile/src/services/wsService.ts:165",
     "<code>console.log('[WS] Connecting to', url)</code> где <code>url</code> содержит <code>?token=&lt;JWT&gt;</code>.",
     "JWT утекает в logcat (Android) / Xcode console (iOS). Любой с доступом к logs может угнать аккаунт.",
     "Логировать только host: <code>console.log('[WS] Connecting to', WS_URL)</code>."),

    ("R7", "Deep-link scheme raveclone://* без host/path — phishing",
     "mobile/android/app/src/main/AndroidManifest.xml:25-30 + ios/RaveClone/Info.plist:25-34",
     "Scheme <code>raveclone://</code> зарегистрирован без host/path. Любая <code>raveclone://*</code> ссылка открывает приложение.",
     "Phishing-вектор — злоумышленник может прислать ссылку, которая откроет приложение в произвольном состоянии.",
     "Ограничить: <code>&lt;data android:scheme=\"raveclone\" android:host=\"room\" android:pathPrefix=\"/join\"/&gt;</code>."),

    ("R8", "GOOGLE_CLIENT_ID = placeholder YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com",
     "mobile/src/screens/AppAuthScreen.tsx:35, 38",
     "И client ID, и redirect URI используют literal placeholder. Google OAuth не может работать в принципе.",
     "Google sign-in полностью неработоспособен.",
     "Читать из <code>Constants.expoConfig.extra.googleClientId</code>."),
]

for bid, title, fref, what, impact, fix in rn_crit:
    story.append(bug_entry("CRIT", SEV_CRIT, bid, title, fref, what, impact, fix))

story.append(PageBreak())

story.append(Paragraph("🟠 HIGH (21) — leaks / non-functional features", S["h3"]))
story.append(Spacer(0, 4))

rn_high = [
    ("R9", "navigateBack читает несуществующий route.params.navigation",
     "RoomScreen.tsx:193-197",
     "<code>route.params.navigation</code> не существует. Alert OK no-op.",
     "Кикнутые/закрытые пользователи застревают на комнате.",
     "Использовать <code>useNavigation</code> hook."),

    ("R10", "RoomPlayer кормит YouTube watch URL в expo-av Video",
     "RoomPlayer.tsx:138",
     "<code>NativePlayer</code> feeds <code>https://www.youtube.com/watch?v=…</code> в <code>expo-av Video</code>.",
     "YouTube не играет — expo-av не умеет YouTube watch URLs.",
     "Использовать WebView для YouTube или YouTube IFrame API."),

    ("R11", "WebViewPlayer грузит media.streamURL вместо webviewBaseURL",
     "RoomPlayer.tsx:218",
     "Загружается прямой URL видеофайла вместо webviewBaseURL.",
     "DRM-сервисы 404 / блокируют запрос.",
     "Грузить <code>webviewBaseURL</code>, не <code>media.streamURL</code>."),

    ("R12", "injectedJavaScript только на page load — guest не получает seek-команды",
     "RoomPlayer.tsx:219, 233-234",
     "<code>injectedJavaScript</code> выполняется только при load. Последующие seek-команды не доходят до guest.",
     "Гость постоянно десинхронизирован после первой перемотки.",
     "Использовать <code>webviewRef.injectJavaScript(code)</code> для runtime-команд."),

    ("R13", "Host шлёт WebSocket seek flood каждые 500ms",
     "RoomPlayer.tsx:118-123",
     "<code>onPlaybackStatusUpdate</code> вызывает <code>onPositionChange</code> каждые ~500 ms → WebSocket seek flood.",
     "Сервер заваливается seek-командами; гости дёргаются.",
     "Throttle на 2-3s, либо слать только при реальном seek."),

    ("R14", "pc.connectionState === 'disconnected' триггерит handlePeerLeft",
     "VoiceChatService.ts:226-231",
     "Transient network blip permanently mute peers.",
     "Кратковременная потеря сети навсегда мьютит пира — голос не восстанавливается.",
     "Act only on <code>\"failed\"</code>, не на <code>\"disconnected\"</code>."),

    ("R15", "Mute button — TODO no-op",
     "VoiceChatPanel.tsx:64-70",
     "<code>setIsMuted</code> flips UI, но никогда не вызывает <code>voiceChat.toggleMute()</code>.",
     "Микрофон остаётся горячим. Юзер думает, что замьютился — на самом деле нет.",
     "Вызывать <code>voiceChat.toggleMute()</code> в обработчике."),

    ("R16", "webrtc_leave шлёт roomID: '' — server не может разорвать p2p",
     "VoiceChatService.ts:175-179",
     "<code>emit('webrtc_leave', { roomID: '' })</code> — пустой roomID.",
     "Remote peer's pc никогда не teardown-ится при выходе из комнаты.",
     "Передавать реальный roomID."),

    ("R17", "ScreenShareService — мёртвый код",
     "ScreenShareService.ts (весь файл)",
     "Нет <code>wsService.on(...)</code> listeners; <code>handleSignaling</code> unreachable. RoomScreen button просто alert-ит.",
     "Фича демонстрации экрана полностью неработоспособна.",
     "Wire up signaling listeners, либо удалить фичу."),

    ("R18", "ICE config без TURN server",
     "ScreenShareService.ts:24-33",
     "TURN закомментирован как placeholder.",
     "Screen share fails behind symmetric NAT.",
     "Добавить реальный TURN server (Twilio/coturn)."),

    ("R19", "WS effect deps [roomID] only — stale closures",
     "RoomScreen.tsx:60-190",
     "<code>useEffect(..., [roomID])</code> — voiceChat, user, navigateBack в closure устаревают.",
     "Stale state, неверные handlers после re-render.",
     "Добавить все используемые переменные в deps, либо refactor."),

    ("R20", "Sync effect missing isHost и applyPosition deps",
     "RoomPlayer.tsx:73-79",
     "Effect не перезапускается при смене хоста.",
     "Host-transfer ломает sync.",
     "Добавить isHost, applyPosition в deps."),

    ("R21", "applyPosition async после unmount — native crash",
     "RoomPlayer.tsx:81-92",
     "<code>video.playAsync()</code> вызывается после unmount.",
     "Native crash risk на React Native 0.74+.",
     "Использовать <code>isMountedRef</code> или AbortController."),

    ("R22", "WS onclose всегда реконнектит — kicked users в цикле",
     "wsService.ts:191-200",
     "<code>onclose</code> всегда schedules reconnect, без проверки code.",
     "Кикнутые пользователи переподключаются и re-joinят в цикле — DDoS собственного сервера.",
     "Проверять close code; не реконнектить при 4001 (kicked) / 4003 (banned)."),

    ("R23", "send() молча дропает сообщения если WS не OPEN",
     "wsService.ts:264-269",
     "Нет queue, нет retry. Если WS connecting/closing, сообщение теряется.",
     "Join/chat/sync команды потеряны при reconnect.",
     "Implement message queue с flush на connected event."),

    ("R24", "setTimeout 500ms race для joinRoom",
     "RoomScreen.tsx:179-181",
     "<code>setTimeout(() =&gt; wsService.joinRoom(roomID), 500)</code>. Если WS занимает &gt;500ms, join дропается (см. R23).",
     "Юзер не joinит комнату при медленном коннекте.",
     "Subscribe на <code>connected</code> event вместо таймера."),

    ("R25", "JSON.parse(event.nativeEvent.data) без try/catch",
     "DrmOverlay.tsx:171-176",
     "Любой non-JSON postMessage из загруженной страницы крашит React tree.",
     "Crash от любого malformed message из WebView.",
     "Wrap в try/catch, логировать raw data."),

    ("R26", "Нет global ErrorBoundary",
     "App.tsx",
     "Любой render exception → белый экран без recovery.",
     "Юзеры видят белый экран при любом рендер-баге, без возможности сообщить.",
     "Добавить ErrorBoundary с fallback UI."),

    ("R27", "ContentBrowserScreen fetch-ит результаты, но не отображает",
     "ContentBrowserScreen.tsx:61-78",
     "Search fetch-ит results и <code>console.log</code> count, но FlatList рендерит mocks.",
     "Поиск не работает — юзер видит static mocks вместо реальных результатов.",
     "Сохранять results в state, рендерить в FlatList."),

    ("R28", "CreateRoomModal — showCreate никогда не true",
     "HomeScreen.tsx:70, 242",
     "<code>CreateRoomModal</code> отрендерен, но <code>showCreate</code> никогда не выставляется в true.",
     "Dead code, unreachable UI element.",
     "Либо удалить, либо добавить trigger."),

    ("R29", "DEV_URL = localhost:3000 — недостижим с эмулятора/устройства",
     "src/config/index.ts:20",
     "<code>http://localhost:3000</code> — Android emulator требует 10.0.2.2, физические устройства — IP хоста.",
     "Backend unreachable в dev на Android.",
     "Использовать <code>10.0.2.2</code> для Android emulator, IP хоста для устройств."),
]

for bid, title, fref, what, impact, fix in rn_high:
    story.append(bug_entry("HIGH", SEV_HIGH, bid, title, fref, what, impact, fix))

story.append(PageBreak())

story.append(Paragraph("🟡 MEDIUM (17) + 🟢 LOW (15)", S["h3"]))
story.append(Spacer(0, 4))

rn_med_low = [
    ("R30", "🟡 Опасные permissions в AndroidManifest",
     "AndroidManifest.xml:4,6,8",
     "READ_EXTERNAL_STORAGE, SYSTEM_ALERT_WINDOW, WRITE_EXTERNAL_STORAGE — неиспользуемые и опасные.",
     "Google Play отклонит за лишние permissions.",
     "Удалить unused permissions."),

    ("R31", "🟡 Deprecated BLUOTH permission, missing BLUETOOTH_CONNECT/SCAN",
     "app.json:33",
     "BLUETOOTH deprecated. Нет BLUETOOTH_CONNECT/BLUETOOTH_SCAN для Android 12+.",
     "Bluetooth-функции не работают на Android 12+.",
     "Заменить на BLUETOOTH_CONNECT, BLUETOOTH_SCAN."),

    ("R32", "🟡 Share message «Plink!» вместо «RaveClone»",
     "RoomScreen.tsx:203",
     "Copy-paste leftover.",
     "Несогласованный брендинг.",
     "Унифицировать имя."),

    ("R33", "🟡 showScreenShareBtn state, никогда не читается/пишется",
     "RoomScreen.tsx:46",
     "Dead state.",
     "Wasted memory, confusing code.",
     "Удалить или использовать."),

    ("R34", "🟡 Empty catch {} everywhere",
     "HomeScreen.tsx:78, MyRoomsScreen.tsx:32, ContentBrowserScreen.tsx:73,106,125, ProfileScreen.tsx:57, RoomScreen.tsx:205",
     "<code>catch {}</code> без обработки.",
     "Юзер не видит ошибок; debugging невозможно.",
     "Логировать + показывать toast."),

    ("R35", "🟡 Public OpenRelay TURN credentials захардкожены",
     "VoiceChatService.ts:50-52",
     "Публичные TURN creds — abuse-prone, unreliable, не для prod.",
     "TURN server абьюзят, unreliable в prod.",
     "Self-hosted coturn или Twilio TURN."),

    ("R36", "🟡 useAuthStore() подписывается на весь store",
     "AppNavigator.tsx:48, HomeScreen.tsx:66, ProfileScreen.tsx:20",
     "<code>useAuthStore()</code> без selector — ре-рендер на любое изменение store.",
     "Unnecessary re-renders, perf degradation.",
     "Использовать selectors: <code>useAuthStore(s =&gt; s.user)</code>."),

    ("R37", "🟡 JSON.parse(userValue) as AppUser — без runtime validation",
     "authStore.ts:60",
     "<code>JSON.parse(userValue) as AppUser</code> — cast без проверки.",
     "Corrupted storage crashes app on hydrate.",
     "Использовать zod schema для validation."),

    ("R38", "🟡 JSON.parse(value) as DrmSession — то же",
     "DrmSessionManager.ts:142",
     "Corrupted cookie blob crashes hydrate.",
     "Crash on bad storage.",
     "Zod validation."),

    ("R39", "🟡 Email validation !email.includes(\"@\") принимает \"a@b\"",
     "AppAuthScreen.tsx:225",
     "Слабая валидация. Password min 6 ниже NIST recommendation (8).",
     "Слабые пароли, фейковые emails.",
     "Строгая regex + min 8 chars."),

    ("R40", "🟡 FlatList renderItem не memoized, ChatBubble не React.memo",
     "ChatView.tsx:122-129",
     "Re-render всех сообщений на каждое новое.",
     "Perf degradation в длинных чатах.",
     "<code>React.memo</code> для ChatBubble, <code>useCallback</code> для renderItem."),

    ("R41", "🟡 Pan gesture без activeOffsetX/failOffsetY — hijacks vertical scroll",
     "ChatView.tsx:68-87",
     "Horizontal pan hijacks vertical scroll message list.",
     "Скролл сообщений блокируется свайпом.",
     "Добавить <code>activeOffsetX</code>, <code>failOffsetY</code>."),

    ("R42", "🟡 KeyboardAvoidingView behavior={undefined} на Android",
     "AppAuthScreen.tsx:252",
     "Behavior undefined на Android — клавиатура перекрывает inputs.",
     "Юзер не видит email/password под клавиатурой.",
     "<code>behavior={Platform.OS === 'ios' ? 'padding' : 'height'}</code>."),

    ("R43", "🟡 onError={(e) =&gt; setError(`…${e}`)} рендерит [object Object]",
     "RoomPlayer.tsx:145",
     "String template с object — <code>[object Object]</code>.",
     "Бессмысленное error message.",
     "<code>JSON.stringify(e)</code> или extract message."),

    ("R44", "🟡 Operator precedence: '…' + true ? 'HOST' : 'GUEST'",
     "RoomPlayer.tsx:320",
     "Всегда вычисляется в 'HOST'.",
     "Неверная бизнес-логика.",
     "Добавить скобки: <code>('…' + true) ? 'HOST' : 'GUEST'</code>."),

    ("R45", "🟡 useEffect для googleResponse missing exchange в deps",
     "AppAuthScreen.tsx:80-84",
     "Stale closure для exchange function.",
     "Старая версия функции вызывается.",
     "Добавить exchange в deps."),

    ("R46", "🟡 new MediaStream() — polyfill missing в Expo Go",
     "VoiceChatService.ts:191, 273",
     "<code>new MediaStream()</code> полагается на global, который Expo Go mock не polyfill-ит.",
     "Latent ReferenceError в Expo Go.",
     "Импортировать из react-native-webrtc."),

    ("R47", "🟢 Hardcoded prod URL xpkcakpkfewp-ofewk-pkv-production.up.railway.app",
     "config/index.ts:17",
     "URL Railway в коде.",
     "Если Railway domain изменится — сломается.",
     "Читать из env."),

    ("R48", "🟢 appleId/appleTeamId placeholders в eas.json",
     "eas.json:32,34",
     "Placeholders в build config.",
     "Build упадёт на CI.",
     "Подставить реальные значения."),

    ("R49", "🟢 Google/VK client ID placeholders",
     "AppAuthScreen.tsx:35,201",
     "То же, что R8.",
     "OAuth не работает.",
     "Подставить реальные client IDs."),

    ("R50", "🟢 owner: \"rageultimate\" в app.json",
     "app.json:49",
     "Лишний handle в Expo config.",
     "Expo project ownership раскрыт.",
     "Убрать или заменить."),

    ("R51", "🟢 expo-av deprecated в SDK 54+",
     "package.json:21",
     "expo-av deprecated → migrate to expo-video.",
     "Будущие SDK не поддержат.",
     "Мигрировать на expo-video."),

    ("R52", "🟢 offerToReceiveAudio/Video deprecated",
     "VoiceChatService.ts:234, ScreenShareService.ts:253",
     "Deprecated WebRTC API.",
     "Будущие версии react-native-webrtc не поддержат.",
     "Использовать <code>addTransceiver</code>."),

    ("R53", "🟢 import { ScrollView } в конце файла",
     "ChatView.tsx:202",
     "Импорт после первого использования.",
     "Confusing code style.",
     "Переместить наверх."),

    ("R54", "🟢 Inconsistent React.useEffect vs imported useEffect",
     "HomeScreen.tsx:85, MyRoomsScreen.tsx:40",
     "Mixed style.",
     "Inconsistent code style.",
     "Унифицировать."),

    ("R55", "🟢 console.log/console.warn в production paths",
     "Multiple",
     "Логи в prod путях.",
     "Performance + info leak.",
     "Удалить или заменить на __DEV__ check."),

    ("R56", "🟢 as any casts на navigation",
     "HomeScreen.tsx:170, ServicePickerScreen.tsx:46, ContentBrowserScreen.tsx:123,137, RoomScreen.tsx:194",
     "<code>as any</code> casts.",
     "Type safety lost.",
     "Правильно типизировать navigation."),

    ("R57", "🟢 text.length * fontSize * 0.65 — wrong for Cyrillic/emoji",
     "AnimatedGradientText.tsx:56",
     "Width estimate неверный для кириллицы и emoji.",
     "Marquee glitch на non-Latin текстах.",
     "Использовать text measurement."),

    ("R58", "🟢 Unused loop var userID",
     "VoiceChatService.ts:112",
     "Loop variable не используется.",
     "Dead code.",
     "Удалить."),

    ("R59", "🟢 tsconfig без strict, без path aliases",
     "tsconfig.json",
     "<code>strict</code> не включён, нет path aliases.",
     "Type safety ниже возможного, относительные импорты.",
     "Включить strict, добавить paths."),

    ("R60", "🟢 Hardcoded v1.0.0 в ProfileScreen, app.json говорит 1.1.0",
     "ProfileScreen.tsx:106",
     "Несогласованность версий.",
     "Юзер видит неправильную версию.",
     "Читать из app.json."),

    ("R61", "🟢 off() method определён, но не используется",
     "wsService.ts:286-288",
     "Dead code.",
     "Wasted lines.",
     "Удалить или использовать."),
]

for bid, title, fref, what, impact, fix in rn_med_low:
    if title.startswith("🟡"):
        bg = SEV_MED
    else:
        bg = SEV_LOW
    sev_label = title[:3].strip()
    clean_title = title[3:].strip()
    story.append(bug_entry(sev_label, bg, bid, clean_title, fref, what, impact, fix))

story.append(PageBreak())

# ── ROADMAP ───────────────────────────────────────────────────────────────
story.append(section_header("06", "Дорожная карта исправлений"))
story.append(Paragraph(
    "Рекомендуемый порядок фиксов. Каждый этап — independently shippable: можно релизить после каждого.",
    S["body"]
))
story.append(Spacer(0, 10))

roadmap_data = [
    ["Этап", "Срок", "Что", "Баги", "Результат"],
    ["1. Realtime unlock",
     "1-2 дня",
     "iOS C1 (WebSocket lifecycle) + Backend B1+B2 (user.id + admin auth)",
     "iOS C1, B1, B2",
     "Чат, sync, signaling начинают работать. Admin panel доступен."],
    ["2. Auth security",
     "2-3 дня",
     "JWT в Keychain (iOS C2), SecureStore (RN R2). Удалить demo-bypass (RN R4+R5). Реализовать refresh (iOS C3).",
     "iOS C2,C3; RN R2,R3,R4,R5",
     "Auth модель trustworthy. App Store pre-review passed."],
    ["3. Service DI",
     "2-3 дня",
     "Внедрить общий authenticated APIClient в DM/Friends/Admin (iOS C4+C5+C6). Прокинуть currentUserId и hostIsPremium (iOS C7+C8).",
     "iOS C4-C8",
     "DM, друзья, админка работают. Sync-движок запускается от хоста."],
    ["4. IAP & premium",
     "3-4 дня",
     "Удалить setPremium (iOS C9). Реализовать серверный /iap/verify. Починить restorePurchases (iOS M5). Удалить B5 (free premium bypass).",
     "iOS C9, M5; B5",
     "Premium-модель безопасна. App Store Guideline 3.1.1 satisfied."],
    ["5. iOS infra",
     "3-4 дня",
     "Один AVPlayer (iOS H3), удалить утечки таймеров (H4,H5,H8), unbounded messages (H13), Sendable APIClient (H10).",
     "iOS H3,H4,H5,H8,H10,H13",
     "Стабильный iOS, нет memory leaks, sync работает визуально."],
    ["6. RN playback",
     "3-5 дней",
     "WebViewPlayer правильный URL (R11), runtime JS injection (R12), YouTube через WebView (R10).",
     "RN R10,R11,R12",
     "Видео проигрывается на RN, sync работает."],
    ["7. RN WebRTC",
     "3-4 дня",
     "Mute button (R15), webrtc_leave с roomID (R16), TURN server (R18), не мьютить на transient disconnect (R14).",
     "RN R14,R15,R16,R18",
     "Voice chat стабилен."],
    ["8. Backend security",
     "2-3 дня",
     "SSRF protection (B10), yt-dlp arg injection (B12), chat impersonation (B3), ban enforcement (B4).",
     "B3,B4,B10,B12",
     "Backend hardened. Готов к public exposure."],
    ["9. Polish",
     "1-2 недели",
     "Все Medium и Low баги. Localizations, dead code cleanup, RN strict mode,",
     "Все M/L",
     "Production-ready v1.0."],
]

# render as table
body_rows = []
for i, row in enumerate(roadmap_data):
    if i == 0:
        body_rows.append([Paragraph(f'<b>{c}</b>', S["tbl_h"]) for c in row])
    else:
        cells = [Paragraph(c, S["tbl_c"]) for c in row]
        body_rows.append(cells)

t = Table(body_rows, colWidths=[3.0*cm, 1.8*cm, 5.5*cm, 3.2*cm, 4.5*cm])
t.setStyle(TableStyle([
    ("BACKGROUND", (0,0), (-1,0), HEADER_FILL),
    ("VALIGN", (0,0), (-1,-1), "TOP"),
    ("LEFTPADDING", (0,0), (-1,-1), 6),
    ("RIGHTPADDING", (0,0), (-1,-1), 6),
    ("TOPPADDING", (0,0), (-1,-1), 6),
    ("BOTTOMPADDING", (0,0), (-1,-1), 6),
    ("BOX", (0,0), (-1,-1), 0.5, BORDER),
    ("INNERGRID", (0,0), (-1,-1), 0.2, BORDER),
]))
for i in range(1, len(body_rows)):
    if i % 2 == 0:
        t.setStyle(TableStyle([("BACKGROUND", (0,i), (-1,i), TABLE_STRIPE)]))
story.append(t)
story.append(Spacer(0, 14))

# Final notes
story.append(Paragraph("Финальные заметки для GLM-5.2", S["h3"]))
story.append(Paragraph(
    "Этот отчёт — снимок состояния кодовой базы RaveClone на 3 июля 2026 года. Все 155 багов подтверждены "
    "чтением исходного кода. Bug IDs стабильны: <code>C1-H14-M1-L16</code> (iOS), <code>B1-B34</code> (Backend), "
    "<code>R1-R61</code> (React Native). При обсуждении фиксов ссылайтесь на ID — это однозначно идентифицирует баг.",
    S["body"]
))
story.append(Spacer(0, 6))
story.append(Paragraph(
    "<b>Приоритезация для v1.0 MVP:</b> этапы 1-4 дорожной карты обязательны до релиза. Этапы 5-9 можно делать "
    "постепенно, но этап 5 (iOS infra) желателен до App Store submission — иначе review-команда Apple точно найдёт "
    "утечки памяти и crash-баги.",
    S["body"]
))
story.append(Spacer(0, 6))
story.append(Paragraph(
    "<b>Спец-задача с фоном</b> (раздел 02) не блокирует релиз, но влияет на user experience. Рекомендуется fix "
    "в этапе 9 (Polish), либо сразу после этапа 1, поскольку fix простой (один файл, ~50 строк).",
    S["body"]
))
story.append(Spacer(0, 6))
story.append(Paragraph(
    "<b>Дальнейшие шаги:</b> после фикса этапов 1-4 провести повторный audit только критических подсистем "
    "(auth, sync, IAP) — они самые рискованные. Использовать этот отчёт как baseline для регрессии.",
    S["body"]
))


# ─── Build ─────────────────────────────────────────────────────────────────
out_path = "/home/z/my-project/download/RaveClone_Audit_Report.pdf"
os.makedirs(os.path.dirname(out_path), exist_ok=True)

doc = SimpleDocTemplate(
    out_path,
    pagesize=A4,
    leftMargin=MARGIN_L,
    rightMargin=MARGIN_R,
    topMargin=MARGIN_T,
    bottomMargin=MARGIN_B,
    title="RaveClone — Отчёт об аудите (155 багов)",
    author="Super Z (GLM-4.6) · code review",
    subject="Полный аудит безопасности и качества кода: iOS · Backend · React Native",
    creator="Z.ai",
)

def first_page(canvas, doc):
    draw_cover(canvas, doc)

def later_pages(canvas, doc):
    draw_page_chrome(canvas, doc)

doc.build(story, onFirstPage=first_page, onLaterPages=later_pages)

# stat
size_kb = os.path.getsize(out_path) / 1024
print(f"\n✓ PDF saved: {out_path}")
print(f"  Size: {size_kb:.1f} KB")
