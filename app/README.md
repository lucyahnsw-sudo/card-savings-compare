# 내금리 MVP 앱 (Flask + MySQL)

입력 3단계 → 계산 → 결과 → 조합 상세까지 실제 finance_db로 돌아가는 모바일 웹이다.

## 실행

```bash
cd card-savings-compare
pip install -r requirements.txt
python app/server.py
```

브라우저에서 http://localhost:5000 을 열고, 개발자 도구에서 휴대폰 크기(375px)로 보면 앱처럼 보인다.
DB 접속 정보는 저장소 루트의 `.env`(MYSQL_HOST, MYSQL_USER, MYSQL_PASSWORD)를 그대로 쓴다.

## API

| 메서드 | 주소 | 화면 | 하는 일 |
|---|---|---|---|
| GET | /api/meta | 1/3 소비처, 2/3 은행·조건, 3/3 기간 | benefit_categories, 적금 파는 은행(fin_companies), pref_condition_types, 기간별 적금 수(rate_options) |
| POST | /api/calc | 계산 중 → 결과 / 지출 적음 / 맞는 조합 없음 | 게스트로 넣고 v_my_rate, v_card_benefit으로 순위 계산 후 ROLLBACK |
| POST | /api/detail | 조합 상세 | 카테고리별 카드 혜택, 우대조건별 충족 여부 |

`/api/calc` 요청 예시

```json
{
  "spending": {"1": 100000, "3": 50000, "4": 200000},
  "salary_bank_id": 1,
  "conditions": [3, 6],
  "monthly_saving": 500000,
  "term": 12
}
```

응답의 `status`: `ok`(결과 목록), `low_spend`(실적을 채우는 카드가 절반 미만), `no_result`(그 기간 적금 없음).
입력이 잘못되면 400과 `error` 메시지를 돌려주고, 화면은 입력값 오류 상태를 보여준다.

## 로그인 없이 계산하는 방법

요청마다 트랜잭션 안에서 users / user_spending / user_conditions에 게스트 1명을 넣고,
같은 트랜잭션에서 VIEW로 계산한 뒤 ROLLBACK 한다. 입력값은 DB에 남지 않는다.
그래서 users.is_guest 컬럼 없이도 MVP가 돌아간다.

## 계산 기준

월 남는 돈 = 카드 혜택(v_card_benefit) − 연회비 ÷ 12 + 세후 이자 ÷ 기간
세후 이자는 정액적립 단리 공식, 이자소득세 15.4% 차감. 같은 카드는 결과에 최대 2번까지만 보여준다.
