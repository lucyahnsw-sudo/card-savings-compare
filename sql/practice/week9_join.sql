-- =====================================================================
-- 9주차 실습(JOIN, GROUP BY, HAVING)을 내 DB(finance_db)에 적용
-- 수업 자료의 출석부 예제와 같은 순서로, 내 서비스에서 실제로 궁금한 질문을 SQL로 풀어 봄
-- 실습 번호마다 하나씩 실행(커서를 문장 안에 두고 ⌘+Enter)해서 결과를 캡처
-- =====================================================================
USE finance_db;


-- ---------------------------------------------------------------------
-- 실습 1. JOIN 없이 보기  (수업: 출석표만 보면 2번이 누군지 모름)
-- Q. 우대조건 표만 보면 어떤 상품의 어떤 조건인지 알 수 있나?
-- ---------------------------------------------------------------------
SELECT product_id, type_id, bonus_rate, card_company_id
FROM product_pref_conditions
ORDER BY product_id
LIMIT 10;
-- → 번호만 있어서 상품명·조건명·카드사를 알 수 없음


-- ---------------------------------------------------------------------
-- 실습 2. 표 2개 JOIN  (수업: 출석 기록에 이름 붙이기)
-- Q. 우대조건 번호 대신 조건 이름을 보고 싶다
-- ---------------------------------------------------------------------
SELECT pc.product_id, t.name AS 조건, pc.bonus_rate AS 가산금리
FROM product_pref_conditions pc
JOIN pref_condition_types t
  ON pc.type_id = t.type_id
ORDER BY pc.product_id
LIMIT 10;


-- ---------------------------------------------------------------------
-- 실습 3. 표 4개 JOIN + 같은 표를 두 번 붙이기
-- Q. "어느 은행 적금이, 어느 카드사 카드를 월 얼마 이상 쓰면, 금리를 얼마 더 주나?"
--    fin_companies를 은행용(bank)·카드사용(cardco) 두 번 붙임 → 별명(alias)이 꼭 필요한 이유
-- ---------------------------------------------------------------------
SELECT bank.name       AS 은행,
       p.product_name  AS 적금,
       cardco.name     AS 카드사,
       pc.required_amount AS 월기준액,
       pc.bonus_rate   AS 가산금리
FROM product_pref_conditions pc
JOIN deposit_products p     ON pc.product_id = p.product_id
JOIN fin_companies bank     ON p.company_id = bank.company_id
JOIN fin_companies cardco   ON pc.card_company_id = cardco.company_id
ORDER BY pc.bonus_rate DESC;


-- ---------------------------------------------------------------------
-- 실습 4. JOIN + GROUP BY  (수업: 학생별 지각·결석 횟수)
-- Q. 카드사별로 카드가 몇 장이고, 평균 연회비는? 실적 조건 없는 카드는 몇 장?
-- ---------------------------------------------------------------------
SELECT f.name                       AS 카드사,
       COUNT(*)                     AS 카드수,
       ROUND(AVG(c.annual_fee))     AS 평균연회비,
       SUM(c.min_spending = 0)      AS 실적없는카드
FROM cards c
JOIN fin_companies f ON c.company_id = f.company_id
GROUP BY f.company_id, f.name
ORDER BY 카드수 DESC;


-- ---------------------------------------------------------------------
-- 실습 5. GROUP BY + HAVING  (수업: 결석 2회 이상 경고 명단)
-- Q. 우대조건을 다 채우면 가산금리 합이 1%p 이상인 적금은? (조건이 까다로운 상품 찾기)
-- ---------------------------------------------------------------------
SELECT p.product_name     AS 적금,
       COUNT(*)           AS 조건수,
       SUM(pc.bonus_rate) AS 가산금리합계
FROM product_pref_conditions pc
JOIN deposit_products p ON pc.product_id = p.product_id
GROUP BY p.product_id, p.product_name
HAVING SUM(pc.bonus_rate) >= 1
ORDER BY 가산금리합계 DESC;


-- ---------------------------------------------------------------------
-- 실습 6. LEFT JOIN + IS NULL  (수업: 수강 신청 안 한 학생 찾기)
-- Q. 우대조건을 아직 하나도 입력하지 않은 적금은? → 앞으로 내가 쪼개야 할 작업 목록
-- ---------------------------------------------------------------------
SELECT bank.name AS 은행, p.product_name AS 적금
FROM deposit_products p
JOIN fin_companies bank      ON p.company_id = bank.company_id
LEFT JOIN product_pref_conditions pc ON p.product_id = pc.product_id
WHERE pc.pc_id IS NULL
ORDER BY bank.name, p.product_name;


-- ---------------------------------------------------------------------
-- 실습 7. LEFT JOIN에서 조건을 ON에 쓰기 vs WHERE에 쓰기  (수업: 출석 체크 안 한 학생)
-- Q. 모든 카드 중 '커피' 혜택이 있는 카드와 없는 카드를 한 번에 보기
-- ---------------------------------------------------------------------
-- 7-1. 조건을 ON에: 커피 혜택 없는 카드도 NULL로 남음
SELECT c.card_name, b.rate AS 커피혜택률
FROM cards c
LEFT JOIN card_benefits b
  ON b.card_id = c.card_id
 AND b.category_id = (SELECT category_id FROM benefit_categories WHERE name = '커피')
ORDER BY b.rate DESC, c.card_name;

-- 7-2. 조건을 WHERE에: NULL 줄이 지워져서 커피 혜택 있는 카드만 남음
SELECT c.card_name, b.rate AS 커피혜택률
FROM cards c
LEFT JOIN card_benefits b ON b.card_id = c.card_id
WHERE b.category_id = (SELECT category_id FROM benefit_categories WHERE name = '커피')
ORDER BY b.rate DESC;


-- ---------------------------------------------------------------------
-- 실습 8. JOIN + CASE  (조건에 따라 다른 값)
-- Q. 은행별 적금 수와 최고금리 평균, 그리고 금리 수준 구분
-- ---------------------------------------------------------------------
SELECT bank.name                    AS 은행,
       COUNT(DISTINCT p.product_id) AS 적금수,
       ROUND(AVG(o.max_rate), 2)    AS 평균최고금리,
       CASE
         WHEN AVG(o.max_rate) >= 4   THEN '높음'
         WHEN AVG(o.max_rate) >= 3   THEN '보통'
         ELSE '낮음'
       END                          AS 수준
FROM deposit_products p
JOIN fin_companies bank ON p.company_id = bank.company_id
JOIN rate_options o     ON o.product_id = p.product_id
WHERE o.save_term = 12
GROUP BY bank.company_id, bank.name
ORDER BY 평균최고금리 DESC;


-- ---------------------------------------------------------------------
-- 실습 9. 내 서비스의 핵심 JOIN
-- Q. 사회초년생이 지금 상황으로 바로 채울 수 있는 우대조건은?
--    (회원 조건표 ↔ 상품 우대조건표를 '조건 유형'과 '은행'으로 짝 맞추기)
-- ---------------------------------------------------------------------
SELECT u.nickname       AS 회원,
       p.product_name   AS 적금,
       t.name           AS 충족조건,
       pc.bonus_rate    AS 가산금리
FROM users u
JOIN user_conditions uc          ON uc.user_id = u.user_id
JOIN product_pref_conditions pc  ON pc.type_id = uc.type_id
JOIN deposit_products p          ON p.product_id = pc.product_id
JOIN pref_condition_types t      ON t.type_id = pc.type_id
WHERE u.email = 'starter@test.com'
  AND (uc.company_id = p.company_id OR uc.company_id IS NULL)
ORDER BY p.product_name, pc.bonus_rate DESC;
