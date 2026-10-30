-- =====================================================================
-- 테스트 회원 3명 + 소비 패턴 + 충족 조건, 그리고 결과 확인 쿼리
-- cards_insert.sql을 먼저 실행한 뒤에 실행 (카테고리가 있어야 함)
-- 여러 번 실행해도 되도록 이 회원들의 데이터를 지우고 다시 넣음
-- =====================================================================
USE finance_db;
SET SQL_SAFE_UPDATES = 0;

-- ===== 1. 회원 =====
INSERT IGNORE INTO users (email, nickname, birth_year, monthly_saving) VALUES
('starter@test.com', '사회초년생', 2000, 300000),   -- 매달 30만원 저축
('student@test.com', '대학생',     2004, 100000),   -- 매달 10만원 저축
('worker@test.com',  '직장인',     1993, 500000);   -- 매달 50만원 저축

SET @u1 = (SELECT user_id FROM users WHERE email = 'starter@test.com');
SET @u2 = (SELECT user_id FROM users WHERE email = 'student@test.com');
SET @u3 = (SELECT user_id FROM users WHERE email = 'worker@test.com');

DELETE FROM user_spending   WHERE user_id IN (@u1, @u2, @u3);
DELETE FROM user_conditions WHERE user_id IN (@u1, @u2, @u3);


-- ===== 2. 소비 패턴 (카테고리별 월 평균 지출) =====
INSERT INTO user_spending (user_id, category_id, monthly_amount)
SELECT x.uid, bc.category_id, x.amount
FROM (
    -- 사회초년생: 월 46만원
              SELECT @u1 uid, '교통' cat, 80000 amount
    UNION ALL SELECT @u1, '통신',        60000
    UNION ALL SELECT @u1, '커피',        70000
    UNION ALL SELECT @u1, '쇼핑',       150000
    UNION ALL SELECT @u1, '배달',        80000
    UNION ALL SELECT @u1, '디지털구독',  20000
    -- 대학생: 월 15.5만원 (실적 30만원 카드는 대부분 0원이 나와야 정상)
    UNION ALL SELECT @u2, '교통',        50000
    UNION ALL SELECT @u2, '커피',        40000
    UNION ALL SELECT @u2, '디지털구독',  15000
    UNION ALL SELECT @u2, '마트/편의점', 50000
    -- 직장인: 월 103만원
    UNION ALL SELECT @u3, '교통',       100000
    UNION ALL SELECT @u3, '통신',        80000
    UNION ALL SELECT @u3, '마트/편의점',200000
    UNION ALL SELECT @u3, '음식점',     200000
    UNION ALL SELECT @u3, '공과금',     150000
    UNION ALL SELECT @u3, '주유',       100000
    UNION ALL SELECT @u3, '쇼핑',       200000
) x
JOIN benefit_categories bc ON bc.name = x.cat;


-- ===== 3. 충족 조건 (금융사가 NULL이면 "어느 은행에서든 가능") =====
INSERT INTO user_conditions (user_id, type_id, company_id)
SELECT x.uid, t.type_id, f.company_id
FROM (
    -- 사회초년생: 우리은행으로 월급 받음
              SELECT @u1 uid, '급여이체' cond, '우리은행' bank
    UNION ALL SELECT @u1, '마케팅동의', NULL
    UNION ALL SELECT @u1, '비대면가입', NULL
    -- 대학생: 아직 주거래 은행 없음
    UNION ALL SELECT @u2, '첫거래',     NULL
    UNION ALL SELECT @u2, '비대면가입', NULL
    UNION ALL SELECT @u2, '마케팅동의', NULL
    -- 직장인: 신한은행으로 월급 받음, 청약 보유
    UNION ALL SELECT @u3, '급여이체',   '신한은행'
    UNION ALL SELECT @u3, '청약보유',   NULL
    UNION ALL SELECT @u3, '자동이체',   NULL
    UNION ALL SELECT @u3, '마케팅동의', NULL
) x
JOIN pref_condition_types t ON t.name = x.cond
LEFT JOIN fin_companies f   ON f.name = x.bank;

SET SQL_SAFE_UPDATES = 1;


-- =====================================================================
-- 결과 확인 (과제 캡처용)
-- =====================================================================

-- [캡처 1] 같은 적금인데 카드에 따라 내 금리가 달라진다
-- 사회초년생 × 우리SUPER주거래적금 12개월
SELECT c.card_name                         AS 카드,
       f.name                              AS 카드사,
       r.base_rate                         AS 기본금리,
       r.my_rate                           AS 내금리,
       r.max_rate                          AS 최고금리
FROM v_my_rate r
JOIN cards c          ON c.card_id   = r.card_id
JOIN fin_companies f  ON f.company_id = c.company_id
JOIN rate_options o   ON o.option_id = r.option_id
JOIN deposit_products p ON p.product_id = o.product_id
WHERE r.user_id = @u1
  AND p.product_name = '우리SUPER주거래적금'
  AND o.save_term = 12
ORDER BY r.my_rate DESC, c.card_name
LIMIT 10;

-- [캡처 2] 회원별 카드 + 적금 조합 TOP 5
SELECT nickname, card_name, product_name, save_term, my_rate,
       card_benefit, interest_after_tax, monthly_gain
FROM (
    SELECT v.*,
           ROW_NUMBER() OVER (PARTITION BY v.user_id ORDER BY v.monthly_gain DESC) AS rn
    FROM v_combo_ranking v
    WHERE v.user_id IN (@u1, @u2, @u3)
) ranked
WHERE rn <= 5
ORDER BY user_id, rn;
