"""
금융상품한눈에 Open API → finance_db 적금 데이터 넣기

채우는 테이블: fin_companies(은행), deposit_products, rate_options

준비
    pip install requests pymysql
    1) sql/01_schema.sql 실행해서 테이블 만들기
    2) 금융상품한눈에 > 오픈 API > 인증키 신청
    3) .env.example을 복사해 .env를 만들고 키와 MySQL 비밀번호 입력

실행
    python scripts/load_finlife.py               # API에서 바로 받기
    python scripts/load_finlife.py saving.json   # 브라우저로 받아 저장한 JSON 파일 쓰기
"""
import json
import os
import sys
from pathlib import Path

import pymysql
import requests

# ===== 설정 =====
# 인증키와 비밀번호는 코드에 쓰지 않고 .env(저장소에 올라가지 않음)에서 읽음
def load_env(path=Path(__file__).resolve().parent.parent / ".env"):
    if path.exists():
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


load_env()
API_KEY = os.environ.get("FINLIFE_API_KEY", "")
DB = dict(host=os.environ.get("MYSQL_HOST", "localhost"),
          user=os.environ.get("MYSQL_USER", "root"),
          password=os.environ.get("MYSQL_PASSWORD", ""),
          database="finance_db", charset="utf8mb4")

API_URL = "https://finlife.fss.or.kr/finlifeapi/savingProductsSearch.json"
TOP_FIN_GRP_NO = "020000"   # 020000 은행 / 030300 저축은행


def fetch_from_api():
    """페이지를 끝까지 돌면서 baseList, optionList를 모은다."""
    if not API_KEY:
        sys.exit(".env에 FINLIFE_API_KEY가 없어요. .env.example을 참고하세요.")
    base_list, option_list, page = [], [], 1
    while True:
        res = requests.get(API_URL, params={
            "auth": API_KEY, "topFinGrpNo": TOP_FIN_GRP_NO, "pageNo": page,
        }, timeout=20)
        res.raise_for_status()
        result = res.json()["result"]
        if result.get("err_cd") not in (None, "000"):
            raise RuntimeError(f"API 에러: {result.get('err_cd')} {result.get('err_msg')}")
        base_list += result["baseList"]
        option_list += result["optionList"]
        if page >= int(result.get("max_page_no", 1)):
            return base_list, option_list
        page += 1


def load_from_file(path):
    with open(path, encoding="utf-8") as f:
        result = json.load(f)["result"]
    return result["baseList"], result["optionList"]


def short(value, mapping):
    """'정액적립식' → '정액' 처럼 API 표기를 우리 CHECK 값으로 바꾼다."""
    for key, short_name in mapping.items():
        if value and key in value:
            return short_name
    return None


def main():
    base_list, option_list = (load_from_file(sys.argv[1]) if len(sys.argv) > 1
                              else fetch_from_api())
    print(f"상품 {len(base_list)}개, 금리옵션 {len(option_list)}개 받음")

    conn = pymysql.connect(**DB)
    cur = conn.cursor()

    # 1) 은행: API 금융사 코드(fin_co_no)가 UNIQUE라서 이미 있으면 이름만 갱신
    company_id = {}
    for b in base_list:
        cur.execute(
            """INSERT INTO fin_companies (fin_co_no, name, company_type)
               VALUES (%s, %s, '은행')
               ON DUPLICATE KEY UPDATE name = VALUES(name),
                                       company_id = LAST_INSERT_ID(company_id)""",
            (b["fin_co_no"], b["kor_co_nm"]))
        company_id[b["fin_co_no"]] = cur.lastrowid

    # 2) 상품: (company_id, fin_prdt_cd) UNIQUE 기준으로 넣거나 갱신
    product_id = {}
    for b in base_list:
        cur.execute(
            """INSERT INTO deposit_products
                   (company_id, fin_prdt_cd, product_name, product_type, pref_text)
               VALUES (%s, %s, %s, '적금', %s)
               ON DUPLICATE KEY UPDATE product_name = VALUES(product_name),
                                       pref_text = VALUES(pref_text),
                                       product_id = LAST_INSERT_ID(product_id)""",
            (company_id[b["fin_co_no"]], b["fin_prdt_cd"], b["fin_prdt_nm"],
             (b.get("spcl_cnd") or "")[:300]))
        product_id[(b["fin_co_no"], b["fin_prdt_cd"])] = cur.lastrowid

    # 3) 금리옵션: 기간 · 적립방식 · 단리/복리마다 한 줄
    skipped = 0
    for o in option_list:
        pid = product_id.get((o["fin_co_no"], o["fin_prdt_cd"]))
        base_rate = o.get("intr_rate")
        max_rate = o.get("intr_rate2") or base_rate
        rsrv = short(o.get("rsrv_type_nm"), {"정액": "정액", "자유": "자유"})
        intr = short(o.get("intr_rate_type_nm"), {"단리": "단리", "복리": "복리"})
        if pid is None or base_rate is None or rsrv is None or intr is None:
            skipped += 1                       # 금리가 비어 있는 옵션 등은 건너뜀
            continue
        cur.execute(
            """INSERT INTO rate_options
                   (product_id, save_term, rsrv_type, intr_rate_type, base_rate, max_rate)
               VALUES (%s, %s, %s, %s, %s, %s)
               ON DUPLICATE KEY UPDATE base_rate = VALUES(base_rate),
                                       max_rate  = VALUES(max_rate)""",
            (pid, int(o["save_trm"]), rsrv, intr, base_rate, max(max_rate, base_rate)))

    conn.commit()
    print(f"완료: 은행 {len(set(company_id))}곳, 상품 {len(product_id)}개 반영 "
          f"(건너뛴 옵션 {skipped}개)")
    conn.close()


if __name__ == "__main__":
    main()
