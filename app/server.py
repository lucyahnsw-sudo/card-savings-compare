"""
내금리 MVP 서버 (Flask + MySQL finance_db)

실행
    pip install -r requirements.txt
    python app/server.py
    → 브라우저에서 http://localhost:5000

DB 접속 정보는 저장소 루트의 .env에서 읽는다 (MYSQL_HOST, MYSQL_USER, MYSQL_PASSWORD).

로그인 없이 계산하는 방법
    요청마다 트랜잭션을 열고 users / user_spending / user_conditions에 게스트 1명을 넣은 뒤
    VIEW(v_card_benefit, v_my_rate)로 계산하고, 끝나면 ROLLBACK 한다.
    같은 트랜잭션 안에서는 방금 넣은 행이 VIEW에 보이고, ROLLBACK 하면 DB에는 아무것도 남지 않는다.
"""
import os
import uuid
from contextlib import contextmanager
from pathlib import Path

import pymysql
from flask import Flask, jsonify, request, send_from_directory

ROOT = Path(__file__).resolve().parent.parent
STATIC = Path(__file__).resolve().parent / "static"


def load_env(path=ROOT / ".env"):
    if path.exists():
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


load_env()
DB = dict(host=os.environ.get("MYSQL_HOST", "localhost"),
          user=os.environ.get("MYSQL_USER", "root"),
          password=os.environ.get("MYSQL_PASSWORD", ""),
          database=os.environ.get("MYSQL_DATABASE", "finance_db"),
          charset="utf8mb4",
          cursorclass=pymysql.cursors.DictCursor)

# 화면에서 직접 고르지 않는 조건 유형
HIDDEN_TYPES = ("급여이체", "카드실적", "기타")
LOW_SPEND_SHARE = 0.5      # 실적을 채우는 카드가 절반이 안 되면 '지출이 적을 때' 화면
PER_CARD_LIMIT = 2         # 결과 목록에서 같은 카드는 최대 2번까지

app = Flask(__name__, static_folder=None)


@contextmanager
def connect():
    conn = pymysql.connect(**DB)
    try:
        yield conn
    finally:
        conn.close()


def num(v):
    """DECIMAL → float, None은 그대로"""
    return None if v is None else float(v)


# ---------------------------------------------------------------- 화면용 기준 데이터
@app.get("/api/meta")
def meta():
    with connect() as conn, conn.cursor() as cur:
        cur.execute("SELECT category_id AS id, name FROM benefit_categories "
                    "WHERE name <> '국내전체' ORDER BY category_id")
        categories = cur.fetchall()

        # 적금을 파는 은행만
        cur.execute("""
            SELECT DISTINCT f.company_id AS id, f.name
            FROM fin_companies f
            JOIN deposit_products dp ON dp.company_id = f.company_id AND dp.is_active
            WHERE f.company_type = '은행'
            ORDER BY f.name""")
        banks = cur.fetchall()

        cur.execute(f"""
            SELECT type_id AS id, name FROM pref_condition_types
            WHERE name NOT IN ({','.join(['%s'] * len(HIDDEN_TYPES))})
            ORDER BY type_id""", HIDDEN_TYPES)
        conditions = cur.fetchall()

        cur.execute("""
            SELECT o.save_term AS term, COUNT(DISTINCT o.product_id) AS products
            FROM rate_options o
            JOIN deposit_products dp ON dp.product_id = o.product_id AND dp.is_active
            WHERE o.rsrv_type = '정액'
            GROUP BY o.save_term ORDER BY o.save_term""")
        terms = cur.fetchall()

    return jsonify(categories=categories, banks=banks, conditions=conditions, terms=terms)


# ---------------------------------------------------------------- 입력 검사
class InputError(Exception):
    pass


def read_input(body):
    spending = {}
    for k, v in (body.get("spending") or {}).items():
        amount = int(v or 0)
        if amount < 0:
            raise InputError("지출 금액은 0원 이상이어야 해요")
        if amount:
            spending[int(k)] = amount
    if not spending:
        raise InputError("지출을 한 곳 이상 입력해 주세요")

    saving = int(body.get("monthly_saving") or 0)
    if saving < 10000:
        raise InputError("매달 1만 원 이상 입력해 주세요")

    term = int(body.get("term") or 0)
    if term <= 0:
        raise InputError("저축 기간을 골라 주세요")

    bank = body.get("salary_bank_id")
    bank = int(bank) if bank else None
    conditions = [int(x) for x in (body.get("conditions") or [])]
    return dict(spending=spending, saving=saving, term=term, bank=bank, conditions=conditions)


def insert_guest(cur, inp):
    """게스트 회원 1명과 지출·조건을 넣고 user_id를 돌려준다 (호출한 쪽에서 ROLLBACK)"""
    cur.execute("INSERT INTO users (email, nickname, monthly_saving) VALUES (%s, '게스트', %s)",
                (f"guest-{uuid.uuid4().hex}@guest.local", inp["saving"]))
    user_id = cur.lastrowid

    cur.executemany("INSERT INTO user_spending (user_id, category_id, monthly_amount) VALUES (%s, %s, %s)",
                    [(user_id, c, a) for c, a in inp["spending"].items()])

    rows = []
    if inp["bank"]:
        cur.execute("SELECT type_id FROM pref_condition_types WHERE name = '급여이체'")
        rows.append((user_id, cur.fetchone()["type_id"], inp["bank"]))
    # 나머지 조건은 '어느 은행이든 가능'으로 저장 (company_id NULL)
    rows += [(user_id, t, None) for t in set(inp["conditions"])]
    if rows:
        cur.executemany("INSERT INTO user_conditions (user_id, type_id, company_id) VALUES (%s, %s, %s)", rows)
    return user_id


# ---------------------------------------------------------------- 결과 목록
RANK_SQL = """
SELECT c.card_id, c.card_name, c.card_type, c.annual_fee, c.min_spending,
       cc.name AS card_company,
       o.option_id, o.save_term, o.intr_rate_type, o.base_rate, o.max_rate,
       dp.product_id, dp.product_name, bank.name AS bank,
       r.my_rate, cb.card_benefit,
       %(saving)s * (r.my_rate / 100 / 12) * o.save_term * (o.save_term + 1) / 2 * 0.846 AS interest
FROM v_my_rate r
JOIN cards c             ON c.card_id = r.card_id
JOIN fin_companies cc    ON cc.company_id = c.company_id
JOIN rate_options o      ON o.option_id = r.option_id
JOIN deposit_products dp ON dp.product_id = o.product_id
JOIN fin_companies bank  ON bank.company_id = dp.company_id
JOIN v_card_benefit cb   ON cb.user_id = r.user_id AND cb.card_id = r.card_id
WHERE r.user_id = %(user_id)s
  AND o.save_term = %(term)s
  AND o.rsrv_type = '정액'
"""


def shape_combo(row, term):
    fee_month = row["annual_fee"] / 12
    interest = float(row["interest"])
    card_benefit = float(row["card_benefit"])
    return dict(
        card_id=row["card_id"], card_name=row["card_name"], card_company=row["card_company"],
        card_type=row["card_type"], annual_fee=row["annual_fee"], min_spending=row["min_spending"],
        option_id=row["option_id"], product_id=row["product_id"], product_name=row["product_name"],
        bank=row["bank"], term=row["save_term"], intr_rate_type=row["intr_rate_type"],
        base_rate=num(row["base_rate"]), max_rate=num(row["max_rate"]), my_rate=num(row["my_rate"]),
        card_benefit=round(card_benefit), fee_month=round(fee_month),
        interest=round(interest), interest_month=round(interest / term),
        monthly_gain=round(card_benefit - fee_month + interest / term),
    )


@app.post("/api/calc")
def calc():
    try:
        inp = read_input(request.get_json(force=True) or {})
    except (InputError, ValueError) as e:
        return jsonify(error=str(e)), 400

    with connect() as conn:
        try:
            with conn.cursor() as cur:
                conn.begin()
                user_id = insert_guest(cur, inp)
                total = sum(inp["spending"].values())

                cur.execute(RANK_SQL, dict(user_id=user_id, term=inp["term"], saving=inp["saving"]))
                rows = [shape_combo(r, inp["term"]) for r in cur.fetchall()]

                # 실적을 채우는 카드 비율
                cur.execute("SELECT COUNT(*) AS n, SUM(min_spending <= %s) AS ok FROM cards WHERE is_active", (total,))
                share = cur.fetchone()
                share = float(share["ok"] or 0) / share["n"] if share["n"] else 0

                # 실적 조건 없는 카드 (지출이 적을 때 화면)
                cur.execute("""
                    SELECT c.card_id, c.card_name, c.annual_fee, cb.card_benefit
                    FROM v_card_benefit cb JOIN cards c ON c.card_id = cb.card_id
                    WHERE cb.user_id = %s AND c.min_spending = 0""", (user_id,))
                no_min_cards = sorted(
                    [dict(card_id=r["card_id"], card_name=r["card_name"],
                          card_benefit=round(float(r["card_benefit"])),
                          fee_month=round(r["annual_fee"] / 12),
                          net=round(float(r["card_benefit"]) - r["annual_fee"] / 12)) for r in cur.fetchall()],
                    key=lambda x: -x["net"])

                # 다른 기간 (맞는 조합이 없을 때 안내용)
                cur.execute("""
                    SELECT DISTINCT o.save_term FROM rate_options o
                    JOIN deposit_products dp ON dp.product_id = o.product_id AND dp.is_active
                    WHERE o.rsrv_type = '정액' ORDER BY o.save_term""")
                other_terms = [r["save_term"] for r in cur.fetchall() if r["save_term"] != inp["term"]]
        finally:
            conn.rollback()   # 게스트 데이터는 남기지 않는다

    rows.sort(key=lambda x: -x["monthly_gain"])
    combos, seen_pair, per_card = [], set(), {}
    for r in rows:
        pair = (r["card_id"], r["product_id"])
        if pair in seen_pair or per_card.get(r["card_id"], 0) >= PER_CARD_LIMIT:
            continue
        seen_pair.add(pair)
        per_card[r["card_id"]] = per_card.get(r["card_id"], 0) + 1
        combos.append(r)
        if len(combos) == 20:
            break

    status = "ok"
    if not combos:
        status = "no_result"
    elif share < LOW_SPEND_SHARE:
        status = "low_spend"

    return jsonify(status=status, total_spending=total, card_share=round(share, 2),
                   input=dict(term=inp["term"], monthly_saving=inp["saving"]),
                   combos=combos, no_min_cards=no_min_cards[:5],
                   other_terms=other_terms,
                   needed_spending=max(0, 300000 - total))


# ---------------------------------------------------------------- 조합 상세
@app.post("/api/detail")
def detail():
    body = request.get_json(force=True) or {}
    try:
        inp = read_input(body)
        card_id, option_id = int(body["card_id"]), int(body["option_id"])
    except (InputError, ValueError, KeyError) as e:
        return jsonify(error=str(e)), 400

    with connect() as conn:
        try:
            with conn.cursor() as cur:
                conn.begin()
                user_id = insert_guest(cur, inp)
                total = sum(inp["spending"].values())

                cur.execute(RANK_SQL + " AND r.card_id = %(card_id)s AND r.option_id = %(option_id)s",
                            dict(user_id=user_id, term=inp["term"], saving=inp["saving"],
                                 card_id=card_id, option_id=option_id))
                row = cur.fetchone()
                if not row:
                    return jsonify(error="조합을 찾지 못했어요"), 404
                combo = shape_combo(row, inp["term"])

                # 카드 혜택: 카테고리별
                cur.execute("""
                    SELECT bc.name AS category, b.rate, b.monthly_limit, b.description,
                           CASE WHEN bc.name = '국내전체' THEN %(total)s ELSE IFNULL(s.monthly_amount, 0) END AS spend
                    FROM card_benefits b
                    JOIN benefit_categories bc ON bc.category_id = b.category_id
                    LEFT JOIN user_spending s ON s.category_id = b.category_id AND s.user_id = %(user_id)s
                    WHERE b.card_id = %(card_id)s
                    ORDER BY spend DESC""", dict(total=total, user_id=user_id, card_id=card_id))
                met_min = total >= row["min_spending"]
                benefits = []
                for b in cur.fetchall():
                    raw = b["spend"] * float(b["rate"]) / 100
                    amount = min(raw, b["monthly_limit"]) if b["monthly_limit"] is not None else raw
                    benefits.append(dict(category=b["category"], rate=num(b["rate"]), spend=int(b["spend"]),
                                         limit=b["monthly_limit"], description=b["description"],
                                         amount=round(amount) if met_min else 0))

                # 적금 우대조건: 하나씩 충족 여부
                cur.execute("""
                    SELECT ty.name AS type, pc.bonus_rate, pc.description, pc.required_amount,
                           card_co.name AS card_company,
                           CASE
                             WHEN ty.name = '카드실적' THEN
                               (pc.card_company_id = c.company_id AND %(total)s >= IFNULL(pc.required_amount, 0))
                             ELSE EXISTS (SELECT 1 FROM user_conditions uc
                                          WHERE uc.user_id = %(user_id)s AND uc.type_id = pc.type_id
                                            AND (uc.company_id = dp.company_id OR uc.company_id IS NULL))
                           END AS met
                    FROM product_pref_conditions pc
                    JOIN pref_condition_types ty ON ty.type_id = pc.type_id
                    JOIN deposit_products dp     ON dp.product_id = pc.product_id
                    JOIN cards c                 ON c.card_id = %(card_id)s
                    LEFT JOIN fin_companies card_co ON card_co.company_id = pc.card_company_id
                    WHERE pc.product_id = %(product_id)s
                    ORDER BY met DESC, pc.bonus_rate DESC""",
                            dict(total=total, user_id=user_id, card_id=card_id, product_id=row["product_id"]))
                conditions = [dict(type=c["type"], bonus_rate=num(c["bonus_rate"]), description=c["description"],
                                   required_amount=c["required_amount"], card_company=c["card_company"],
                                   met=bool(c["met"])) for c in cur.fetchall()]
        finally:
            conn.rollback()

    return jsonify(combo=combo, total_spending=total, met_min_spending=met_min,
                   benefits=benefits, conditions=conditions)


# ---------------------------------------------------------------- 정적 파일
@app.get("/")
def index():
    return send_from_directory(STATIC, "index.html")


@app.get("/<path:name>")
def static_files(name):
    return send_from_directory(STATIC, name)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 5000)), debug=True)
