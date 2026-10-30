-- =====================================================================
-- 계산 VIEW 4개 만들기 (finance_db.sql 맨 아래 부분만 따로 뺀 것)
-- 이미 있으면 새 내용으로 덮어씀. 테이블·데이터는 건드리지 않음
-- 카드 혜택 VIEW는 '국내전체' 카테고리를 반영한 최신 버전
-- =====================================================================
USE finance_db;

-- 1. 회원별 월 총지출
CREATE OR REPLACE VIEW v_user_total AS
SELECT user_id, SUM(monthly_amount) AS total_spending
FROM user_spending
GROUP BY user_id;

-- 2. 회원 × 카드: 월 카드 혜택액 (실적 미달 0원, 한도 적용, 국내전체는 총지출 기준)
CREATE OR REPLACE VIEW v_card_benefit AS
SELECT u.user_id,
       c.card_id,
       CASE
         WHEN t.total_spending < c.min_spending THEN 0
         ELSE
           -- 카테고리별 혜택
           IFNULL((
             SELECT SUM(LEAST(s.monthly_amount * b.rate / 100,
                              IFNULL(b.monthly_limit, s.monthly_amount * b.rate / 100)))
             FROM card_benefits b
             JOIN user_spending s ON s.category_id = b.category_id
             WHERE b.card_id = c.card_id AND s.user_id = u.user_id
           ), 0)
           -- 국내전체 혜택: 총지출 × 혜택률
         + IFNULL((
             SELECT SUM(LEAST(t.total_spending * b.rate / 100,
                              IFNULL(b.monthly_limit, t.total_spending * b.rate / 100)))
             FROM card_benefits b
             JOIN benefit_categories bc ON bc.category_id = b.category_id
             WHERE b.card_id = c.card_id AND bc.name = '국내전체'
           ), 0)
       END AS card_benefit
FROM users u
JOIN v_user_total t ON t.user_id = u.user_id
CROSS JOIN cards c
WHERE c.is_active = TRUE;

-- 3. 회원 × 카드 × 적금옵션: 내가 받을 금리
CREATE OR REPLACE VIEW v_my_rate AS
SELECT u.user_id,
       c.card_id,
       o.option_id,
       o.base_rate,
       o.max_rate,
       LEAST(o.max_rate, o.base_rate + IFNULL((
         SELECT SUM(pc.bonus_rate)
         FROM product_pref_conditions pc
         JOIN pref_condition_types ty ON ty.type_id = pc.type_id
         WHERE pc.product_id = o.product_id
           AND (
                 (ty.name = '카드실적'
                  AND pc.card_company_id = c.company_id
                  AND t.total_spending >= pc.required_amount)
              OR (ty.name <> '카드실적'
                  AND EXISTS (SELECT 1 FROM user_conditions uc
                              WHERE uc.user_id = u.user_id
                                AND uc.type_id = pc.type_id
                                AND (uc.company_id = dp.company_id OR uc.company_id IS NULL)))
               )
       ), 0)) AS my_rate
FROM users u
JOIN v_user_total t ON t.user_id = u.user_id
CROSS JOIN cards c
CROSS JOIN rate_options o
JOIN deposit_products dp ON dp.product_id = o.product_id
WHERE c.is_active = TRUE AND dp.is_active = TRUE;

-- 4. 조합 순위: 카드 혜택 + 적금 세후이자 ÷ 기간
CREATE OR REPLACE VIEW v_combo_ranking AS
SELECT r.user_id,
       u.nickname,
       c.card_name,
       dp.product_name,
       o.save_term,
       r.my_rate,
       ROUND(cb.card_benefit)                                             AS card_benefit,
       ROUND(u.monthly_saving * (r.my_rate / 100 / 12)
             * o.save_term * (o.save_term + 1) / 2 * 0.846)               AS interest_after_tax,
       ROUND(cb.card_benefit
             + u.monthly_saving * (r.my_rate / 100 / 12)
               * o.save_term * (o.save_term + 1) / 2 * 0.846 / o.save_term) AS monthly_gain
FROM v_my_rate r
JOIN users u            ON u.user_id   = r.user_id
JOIN cards c            ON c.card_id   = r.card_id
JOIN rate_options o     ON o.option_id = r.option_id
JOIN deposit_products dp ON dp.product_id = o.product_id
JOIN v_card_benefit cb  ON cb.user_id = r.user_id AND cb.card_id = r.card_id;

-- 확인: 4개가 보이면 성공
SELECT table_name AS 만들어진_VIEW
FROM information_schema.tables
WHERE table_schema = 'finance_db' AND table_type = 'VIEW';
