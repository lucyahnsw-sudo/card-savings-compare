"""
sql/07_queries.sql 의 쿼리를 내 DB(finance_db)에서 하나씩 실행하고,
쿼리마다 '질문 + SQL + 실행 결과 표'를 PNG 한 장으로 저장한다.

실행 (저장소 폴더에서)
    pip3 install -r requirements.txt
    python3 scripts/capture_results.py
    → results/ 폴더에 A1.png ~ C9.png 와 README.md(목차)가 생긴다

DB 접속 정보는 .env (MYSQL_HOST, MYSQL_USER, MYSQL_PASSWORD) 를 그대로 쓴다.
다른 SQL 파일을 캡처하려면:  python3 scripts/capture_results.py sql/다른파일.sql
"""
import os
import re
import sys
from datetime import datetime
from decimal import Decimal
from pathlib import Path

import pymysql
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SQL_FILE = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "sql" / "07_queries.sql"
OUT = ROOT / "results"
MAX_ROWS = 30  # 이보다 많으면 앞부분만 그리고 '외 N행' 표시

# 한글 글꼴: 맥 → 윈도우 → 리눅스 순서로 찾는다
FONT_CANDIDATES = [
    "/System/Library/Fonts/AppleSDGothicNeo.ttc",
    "/System/Library/Fonts/Supplemental/AppleGothic.ttf",
    "C:/Windows/Fonts/malgun.ttf",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/truetype/nanum/NanumGothic.ttf",
]
FONT_BOLD_CANDIDATES = [
    "/System/Library/Fonts/AppleSDGothicNeo.ttc",
    "C:/Windows/Fonts/malgunbd.ttf",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",
]

INK, SUB, LINE, HEAD_BG, CODE_BG, ACCENT = "#14171C", "#5B6470", "#E3E6EA", "#F1F3F6", "#F7F8FA", "#2457D6"


def load_env(path=ROOT / ".env"):
    if path.exists():
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def font(size, bold=False):
    for path in (FONT_BOLD_CANDIDATES if bold else []) + FONT_CANDIDATES:
        if os.path.exists(path):
            # AppleSDGothicNeo.ttc 는 index 6 근처가 Bold
            index = 6 if (bold and path.endswith("AppleSDGothicNeo.ttc")) else 0
            try:
                return ImageFont.truetype(path, size, index=index)
            except OSError:
                return ImageFont.truetype(path, size)
    raise SystemExit("한글 글꼴을 찾지 못했어요. FONT_CANDIDATES 에 글꼴 경로를 추가해 주세요.")


def split_queries(text):
    """'-- [A1] 제목' 줄로 나눠 (key, title, question, sql) 목록을 만든다"""
    parts = re.split(r"^-- \[([A-Z]\d+)\] (.*)$", text, flags=re.M)
    items = []
    for i in range(1, len(parts), 3):
        key, title, body = parts[i], parts[i + 1].strip(), parts[i + 2]
        body = re.split(r"^-- =+", body, flags=re.M)[0]  # 다음 구역 머리말 앞까지
        question = " ".join(m.strip() for m in re.findall(r"^-- Q\.\s*(.*)$", body, flags=re.M))
        sql = "\n".join(l for l in body.strip().splitlines() if not l.lstrip().startswith("--")).strip()
        items.append((key, title, question, sql))
    return items


def fmt(v):
    if v is None:
        return "NULL"
    if isinstance(v, bool):
        return str(v)
    if isinstance(v, int):
        return f"{v:,}"
    if isinstance(v, (Decimal, float)):
        if v == int(v) and (not isinstance(v, Decimal) or v.as_tuple().exponent >= 0):
            return f"{int(v):,}"          # 금액처럼 소수 없는 값
        return f"{v:,.2f}"                # 금리처럼 소수 있는 값
    return str(v)


def render(key, title, question, sql, columns, rows, total, elapsed_ms, db_name, path):
    f_title, f_q, f_code, f_cell, f_head, f_foot = font(26, True), font(17), font(16), font(16), font(16, True), font(14)
    pad, cell_px, row_h = 32, 14, 34

    shown = rows[:MAX_ROWS]
    cells = [[fmt(v) for v in r] for r in shown]
    probe = ImageDraw.Draw(Image.new("RGB", (10, 10)))
    widths = []
    for j, c in enumerate(columns):
        w = probe.textlength(str(c), font=f_head)
        for r in cells:
            w = max(w, probe.textlength(r[j], font=f_cell))
        widths.append(int(min(w, 360)) + 4 + cell_px * 2)
    table_w = sum(widths) if widths else 300

    sql_lines = sql.splitlines()
    code_w = max([probe.textlength(l, font=f_code) for l in sql_lines] + [0]) + 32
    width = int(max(900, table_w + pad * 2, code_w + pad * 2))
    height = (pad + 40 + (30 if question else 0) + 16
              + len(sql_lines) * 24 + 32 + 24
              + row_h * (len(shown) + 1) + (row_h if total > len(shown) else 0)
              + (row_h if not rows else 0) + 20 + pad)

    img = Image.new("RGB", (width, height), "white")
    d = ImageDraw.Draw(img)
    y = pad
    d.text((pad, y), f"[{key}]", font=f_title, fill=ACCENT)
    d.text((pad + d.textlength(f"[{key}] ", font=f_title), y), title, font=f_title, fill=INK)
    y += 40
    if question:
        d.text((pad, y), f"Q. {question}", font=f_q, fill=SUB)
        y += 30
    y += 8

    # SQL
    code_h = len(sql_lines) * 24 + 24
    d.rounded_rectangle([pad, y, width - pad, y + code_h], radius=8, fill=CODE_BG, outline=LINE)
    for k, line in enumerate(sql_lines):
        d.text((pad + 16, y + 12 + k * 24), line, font=f_code, fill=INK)
    y += code_h + 24

    # 결과 표
    x0 = pad
    d.rectangle([x0, y, x0 + table_w, y + row_h], fill=HEAD_BG)
    x = x0
    for j, c in enumerate(columns):
        d.text((x + cell_px, y + 8), str(c), font=f_head, fill=INK)
        x += widths[j]
    y += row_h
    for r_i, r in enumerate(cells):
        d.line([x0, y, x0 + table_w, y], fill=LINE)
        x = x0
        for j, v in enumerate(r):
            text = v
            while d.textlength(text, font=f_cell) > widths[j] - cell_px * 2 and len(text) > 1:
                text = text[:-2] + "…"
            color = SUB if v == "NULL" else INK
            d.text((x + cell_px, y + 8), text, font=f_cell, fill=color)
            x += widths[j]
        y += row_h
    if not rows:
        d.text((x0 + cell_px, y + 8), "(결과 없음 · 0 rows)", font=f_cell, fill=SUB)
        y += row_h
    if total > len(shown):
        d.text((x0 + cell_px, y + 8), f"… 외 {total - len(shown)}행", font=f_cell, fill=SUB)
        y += row_h
    d.line([x0, y, x0 + table_w, y], fill=LINE)
    d.rectangle([x0, y - row_h * (len(shown) + 1) - (row_h if not rows else 0) - (row_h if total > len(shown) else 0),
                 x0 + table_w, y], outline=LINE)

    y += 20
    stamp = datetime.now().strftime("%Y-%m-%d %H:%M")
    d.text((pad, y), f"{total} rows · {elapsed_ms:.0f} ms · DB {db_name} · 실행 {stamp} · scripts/capture_results.py",
           font=f_foot, fill=SUB)
    img.save(path)


def main():
    load_env()
    db_name = os.environ.get("MYSQL_DATABASE", "finance_db")
    conn = pymysql.connect(host=os.environ.get("MYSQL_HOST", "localhost"),
                           user=os.environ.get("MYSQL_USER", "root"),
                           password=os.environ.get("MYSQL_PASSWORD", ""),
                           database=db_name, charset="utf8mb4")
    OUT.mkdir(exist_ok=True)
    items = split_queries(SQL_FILE.read_text(encoding="utf-8"))
    index = [f"# SQL 실행 결과 ({SQL_FILE.name})", "",
             f"실행: {datetime.now():%Y-%m-%d %H:%M} · DB `{db_name}` · `python3 scripts/capture_results.py`", "",
             "| 번호 | 내용 | 행 수 | 이미지 |", "| --- | --- | --- | --- |"]
    with conn.cursor() as cur:
        for key, title, question, sql in items:
            started = datetime.now()
            try:
                cur.execute(sql)
                columns = [c[0] for c in cur.description] if cur.description else []
                rows = cur.fetchall() if cur.description else []
            except pymysql.MySQLError as e:
                print(f"[{key}] 오류: {e}")
                index.append(f"| {key} | {title} | 오류 | {e.args[-1]} |")
                continue
            ms = (datetime.now() - started).total_seconds() * 1000
            render(key, title, question, sql, columns, rows, len(rows), ms, db_name, OUT / f"{key}.png")
            index.append(f"| {key} | {title} | {len(rows)} | ![{key}]({key}.png) |")
            print(f"[{key}] {title} · {len(rows)} rows")
    conn.close()
    (OUT / "README.md").write_text("\n".join(index) + "\n", encoding="utf-8")
    print(f"\n완료: {OUT} 에 이미지 {len(items)}장과 README.md")


if __name__ == "__main__":
    main()
