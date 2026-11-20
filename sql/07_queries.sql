-- =====================================================================
-- 07_queries.sql · 기본 조회 / 집계 분석 / 테이블 연결
-- 과제 항목: SELECT·WHERE·ORDER BY, COUNT·GROUP BY 등 집계함수, INNER·LEFT JOIN
--
-- 실행: Workbench에서 열고 쿼리 하나에 커서를 둔 뒤 Ctrl+Enter (맥은 Cmd+Enter)
--       전체 결과 이미지는 scripts/capture_results.py 로 한 번에 만든다.
-- 규칙: "-- [A1] 제목" 줄이 쿼리 하나의 시작이다. 캡처 스크립트가 이 줄로 나눈다.
-- =====================================================================
USE finance_db;


-- =====================================================================
-- A. 기본 조회 (SELECT, WHERE, ORDER BY, LIMIT, LIKE, IS NULL)
-- =====================================================================

-- [A1] 적금을 파는 은행 목록 (가나다순)
-- Q. 어떤 은행 데이터가 들어와 있나?
SELECT company_id, name AS 은행, group_name AS 금융그룹
FROM fin_companies
WHERE company_type = '은행'
ORDER BY name;

-- [A2] 12개월 정액적립 금리 옵션, 최고금리 높은 순 10개
-- Q. 1년 적금 중 최고금리가 가장 높은 옵션은?
SELECT option_id, product_id, save_term AS 기간, intr_rate_type AS 이자방식,
       base_rate AS 기본금리, max_rate AS 최고금리
FROM rate_options
WHERE save_term = 12
  AND rsrv_type = '정액'
ORDER BY max_rate DESC, base_rate DESC
LIMIT 10;

-- [A3] 기본금리와 최고금리 차이(우대폭)가 큰 옵션
-- Q. 우대조건을 채우면 금리가 가장 많이 오르는 옵션은? 계산 컬럼에 별칭을 붙여 정렬
SELECT option_id, product_id, save_term AS 기간,
       base_rate AS 기본금리, max_rate AS 최고금리,
       max_rate - base_rate AS 우대폭
FROM rate_options
ORDER BY 우대폭 DESC
LIMIT 10;

-- [A4] 전월실적 조건이 없는 카드, 연회비 낮은 순
-- Q. 지출이 적은 사람이 쓸 수 있는 카드는?
SELECT card_id, card_name AS 카드, card_type AS 종류, annual_fee AS 연회비
FROM cards
WHERE min_spending = 0
  AND is_active = TRUE
ORDER BY annual_fee, card_name;

-- [A5] 연회비 2만 원 이하 신용카드, 전월실적 낮은 순
-- Q. 사회초년생이 부담 없이 만들 수 있는 신용카드는? (AND 조건 두 개)
SELECT card_name AS 카드, min_spending AS 전월실적, annual_fee AS 연회비
FROM cards
WHERE card_type = '신용'
  AND annual_fee <= 20000
ORDER BY min_spending, annual_fee;

-- [A6] 이름에 '트래블' 또는 '여행'이 들어간 카드 (LIKE)
-- Q. 여행 특화 카드는 몇 장인가?
SELECT card_name AS 카드, annual_fee AS 연회비
FROM cards
WHERE card_name LIKE '%트래블%'
   OR card_name LIKE '%여행%'
   OR card_name LIKE '%트립%'
ORDER BY annual_fee;

-- [A7] 혜택률 20% 이상인데 월 한도가 비어 있는 혜택 (NULL 점검)
-- Q. 계산이 부풀려질 수 있는 데이터는 어디인가? → 전처리 대상
SELECT benefit_id, card_id, rate AS 혜택률, monthly_limit AS 월한도, description AS 설명
FROM card_benefits
WHERE monthly_limit IS NULL
  AND rate >= 20
ORDER BY rate DESC;


-- =====================================================================
-- B. 집계 분석 (COUNT, SUM, AVG, MAX, MIN, GROUP BY, HAVING, CASE)
-- =====================================================================

-- [B1] 데이터 규모 한눈에 보기 (COUNT)
-- Q. 테이블마다 몇 줄이 들어 있나? → 과제 조건 '전체 30행 이상' 확인
SELECT '은행·카드사' AS 테이블, COUNT(*) AS 행수 FROM fin_companies
UNION ALL SELECT '적금 상품',   COUNT(*) FROM deposit_products
UNION ALL SELECT '금리 옵션',   COUNT(*) FROM rate_options
UNION ALL SELECT '우대조건',    COUNT(*) FROM product_pref_conditions
UNION ALL SELECT '카드',        COUNT(*) FROM cards
UNION ALL SELECT '카드 혜택',   COUNT(*) FROM card_benefits
UNION ALL SELECT '회원 지출',   COUNT(*) FROM user_spending;

-- [B2] 저축 기간별 옵션 수와 평균 금리
-- Q. 기간이 길수록 금리가 높은가?
SELECT save_term AS 기간,
       COUNT(*) AS 옵션수,
       ROUND(AVG(base_rate), 2) AS 평균기본금리,
       ROUND(AVG(max_rate), 2)  AS 평균최고금리,
       MAX(max_rate)            AS 가장높은최고금리
FROM rate_options
WHERE rsrv_type = '정액'
GROUP BY save_term
ORDER BY save_term;

-- [B3] 전월실적 구간별 카드 수와 평균 연회비 (CASE로 구간 나누기)
-- Q. 카드 대부분은 실적을 얼마나 요구하나?
SELECT CASE
         WHEN min_spending = 0       THEN '1) 조건 없음'
         WHEN min_spending <= 300000 THEN '2) 30만 원 이하'
         WHEN min_spending <= 500000 THEN '3) 30만 초과 50만 원 이하'
         ELSE                             '4) 50만 원 초과'
       END AS 전월실적구간,
       COUNT(*) AS 카드수,
       ROUND(AVG(annual_fee)) AS 평균연회비
FROM cards
GROUP BY 전월실적구간
ORDER BY 전월실적구간;

-- [B4] 카드 종류별 카드 수, 연회비 범위
-- Q. 신용카드와 체크카드의 연회비 차이는?
SELECT card_type AS 종류,
       COUNT(*) AS 카드수,
       MIN(annual_fee) AS 최저연회비,
       MAX(annual_fee) AS 최고연회비,
       ROUND(AVG(annual_fee)) AS 평균연회비
FROM cards
GROUP BY card_type;

-- [B5] 상품별 우대조건 개수와 가산금리 합, 합이 1%p 이상인 상품만 (HAVING)
-- Q. 조건을 다 채우면 금리가 1%p 넘게 오르는 상품은?
SELECT product_id,
       COUNT(*) AS 조건수,
       SUM(bonus_rate) AS 가산금리합
FROM product_pref_conditions
GROUP BY product_id
HAVING SUM(bonus_rate) >= 1.0
ORDER BY 가산금리합 DESC;

-- [B6] 혜택률 구간별 혜택 수, 월 한도가 비어 있는 비율
-- Q. 높은 혜택일수록 한도 데이터가 빠져 있나?
SELECT CASE
         WHEN rate >= 20 THEN '20% 이상'
         WHEN rate >= 10 THEN '10~20%'
         ELSE                 '10% 미만'
       END AS 혜택률구간,
       COUNT(*) AS 혜택수,
       SUM(monthly_limit IS NULL) AS 한도없음,
       ROUND(SUM(monthly_limit IS NULL) / COUNT(*) * 100) AS 한도없음비율
FROM card_benefits
GROUP BY 혜택률구간
ORDER BY MIN(rate) DESC;

-- [B7] 회원별 월 총지출과 지출 카테고리 수
-- Q. 테스트 회원마다 얼마를 어디에 쓰나?
SELECT user_id,
       COUNT(*) AS 카테고리수,
       SUM(monthly_amount) AS 월총지출,
       MAX(monthly_amount) AS 가장큰지출
FROM user_spending
GROUP BY user_id
ORDER BY 월총지출 DESC;


-- =====================================================================
-- C. 테이블 연결 (INNER JOIN, LEFT JOIN, 같은 테이블 두 번, VIEW)
-- =====================================================================

-- [C1] 적금 상품 + 은행 이름 + 12개월 금리 (INNER JOIN 3개 테이블)
-- Q. A2 결과에 은행과 상품 이름을 붙이면?
SELECT f.name AS 은행, p.product_name AS 상품,
       o.base_rate AS 기본금리, o.max_rate AS 최고금리
FROM rate_options o
JOIN deposit_products p ON p.product_id = o.product_id
JOIN fin_companies f    ON f.company_id = p.company_id
WHERE o.save_term = 12
  AND o.rsrv_type = '정액'
ORDER BY o.max_rate DESC
LIMIT 10;

-- [C2] 카드사별 카드 수와 평균 연회비 (JOIN + GROUP BY)
-- Q. 카드사마다 몇 장씩 들어 있나?
SELECT f.name AS 카드사,
       COUNT(c.card_id) AS 카드수,
       ROUND(AVG(c.annual_fee)) AS 평균연회비
FROM fin_companies f
JOIN cards c ON c.company_id = f.company_id
GROUP BY f.company_id, f.name
ORDER BY 카드수 DESC, 카드사;

-- [C3] 우대조건 유형별 개수와 평균 가산금리 (JOIN + GROUP BY)
-- Q. 적금 우대조건 중 가장 흔한 유형은?
SELECT t.name AS 조건유형,
       COUNT(*) AS 조건수,
       ROUND(AVG(pc.bonus_rate), 2) AS 평균가산금리
FROM product_pref_conditions pc
JOIN pref_condition_types t ON t.type_id = pc.type_id
GROUP BY t.type_id, t.name
ORDER BY 조건수 DESC;

-- [C4] 카드실적 조건: 적금 은행과 조건 카드사 (같은 테이블을 별칭 두 개로 JOIN)
-- Q. 어느 적금이 어느 카드사 카드를 얼마나 쓰면 금리를 더 주나?
SELECT bank.name AS 은행, p.product_name AS 적금,
       cardco.name AS 조건카드사,
       pc.required_amount AS 기준금액,
       pc.bonus_rate AS 가산금리
FROM product_pref_conditions pc
JOIN pref_condition_types t  ON t.type_id = pc.type_id
JOIN deposit_products p      ON p.product_id = pc.product_id
JOIN fin_companies bank      ON bank.company_id = p.company_id
JOIN fin_companies cardco    ON cardco.company_id = pc.card_company_id
WHERE t.name = '카드실적'
ORDER BY pc.bonus_rate DESC;

-- [C5] 우대조건을 아직 정리하지 않은 적금 (LEFT JOIN ... IS NULL)
-- Q. 분해 작업이 남은 상품은? → 다음 작업 목록
SELECT f.name AS 은행, p.product_name AS 상품
FROM deposit_products p
JOIN fin_companies f ON f.company_id = p.company_id
LEFT JOIN product_pref_conditions pc ON pc.product_id = p.product_id
WHERE pc.pc_id IS NULL
ORDER BY f.name, p.product_name;

-- [C6] 카테고리별 혜택 카드 수 (LEFT JOIN: 혜택 없는 카테고리도 0으로 보이게)
-- Q. 카드 혜택이 몰린 소비처와 비어 있는 소비처는?
SELECT bc.name AS 카테고리,
       COUNT(cb.benefit_id) AS 혜택수,
       ROUND(AVG(cb.rate), 1) AS 평균혜택률
FROM benefit_categories bc
LEFT JOIN card_benefits cb ON cb.category_id = bc.category_id
GROUP BY bc.category_id, bc.name
ORDER BY 혜택수 DESC, 카테고리;

-- [C7] '커피'에서 혜택이 큰 카드 (카드 + 혜택 + 카테고리 + 카드사)
-- Q. 카페를 자주 가는 사람에게 맞는 카드는?
SELECT co.name AS 카드사, c.card_name AS 카드, cb.rate AS 혜택률,
       cb.monthly_limit AS 월한도, c.min_spending AS 전월실적
FROM card_benefits cb
JOIN benefit_categories bc ON bc.category_id = cb.category_id
JOIN cards c               ON c.card_id = cb.card_id
JOIN fin_companies co      ON co.company_id = c.company_id
WHERE bc.name = '커피'
ORDER BY cb.rate DESC, c.min_spending;

-- [C8] 직장인 테스트 회원의 지출 내역 (회원 + 지출 + 카테고리)
-- Q. 계산에 들어가는 입력값은 무엇인가?
SELECT u.nickname AS 회원, bc.name AS 카테고리, us.monthly_amount AS 월지출
FROM users u
JOIN user_spending us      ON us.user_id = u.user_id
JOIN benefit_categories bc ON bc.category_id = us.category_id
WHERE u.email = 'worker@test.com'
ORDER BY us.monthly_amount DESC;

-- [C9] 회원별 1위 조합 (VIEW + 순위 함수)
-- Q. 사회초년생·대학생·직장인의 최적 조합은 각각 무엇인가?
SELECT nickname AS 회원, card_name AS 카드, product_name AS 적금,
       save_term AS 기간, my_rate AS 내금리, card_benefit AS 카드혜택,
       monthly_gain AS 월이득
FROM (
  SELECT r.*,
         ROW_NUMBER() OVER (PARTITION BY r.user_id ORDER BY r.monthly_gain DESC) AS 순위
  FROM v_combo_ranking r
) ranked
WHERE 순위 = 1
ORDER BY monthly_gain DESC;
