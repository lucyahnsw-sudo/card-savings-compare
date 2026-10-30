-- =====================================================================
-- 실제 적금 13개의 우대조건 원문을 한 줄씩 쪼개서 product_pref_conditions에 넣기
-- 원문: 금융상품한눈에 API pref_text (2026-10-16 수집)
-- product_id는 내 finance_db 번호 그대로 사용
-- 여러 번 실행해도 되도록 이 상품들의 조건을 먼저 지우고 다시 넣음
-- =====================================================================
USE finance_db;

-- ===== 1. 필요한 조건 유형 · 카드사 준비 (이미 있으면 건너뜀) =====
INSERT IGNORE INTO pref_condition_types (name) VALUES
('급여이체'), ('카드실적'), ('자동이체'), ('첫거래'), ('비대면가입'), ('마케팅동의'),
('청약보유'),   -- 주택청약 · 펀드 보유
('기타');       -- 관광지 인증, 목표금액 달성처럼 유형으로 묶기 어려운 조건

INSERT IGNORE INTO fin_companies (name, company_type, group_name) VALUES
('신한카드',   '카드사', '신한'),
('KB국민카드', '카드사', 'KB'),
('우리카드',   '카드사', '우리');

-- 이름으로 번호 찾아 두기 (번호를 외우지 않아도 되게)
SET @salary   = (SELECT type_id FROM pref_condition_types WHERE name = '급여이체');
SET @card     = (SELECT type_id FROM pref_condition_types WHERE name = '카드실적');
SET @autopay  = (SELECT type_id FROM pref_condition_types WHERE name = '자동이체');
SET @first    = (SELECT type_id FROM pref_condition_types WHERE name = '첫거래');
SET @online   = (SELECT type_id FROM pref_condition_types WHERE name = '비대면가입');
SET @mkt      = (SELECT type_id FROM pref_condition_types WHERE name = '마케팅동의');
SET @sub      = (SELECT type_id FROM pref_condition_types WHERE name = '청약보유');
SET @etc      = (SELECT type_id FROM pref_condition_types WHERE name = '기타');

-- 카드실적 조건이 가리킬 카드사
-- 지방은행 · 농협 · 수협 · 케이뱅크는 은행이 직접 카드를 발급하므로 은행 자신을 가리킴
SET @shinhan_card = (SELECT company_id FROM fin_companies WHERE name = '신한카드');
SET @kb_card      = (SELECT company_id FROM fin_companies WHERE name = 'KB국민카드');
SET @woori_card   = (SELECT company_id FROM fin_companies WHERE name = '우리카드');
SET @kyongnam     = (SELECT company_id FROM fin_companies WHERE name = '경남은행');
SET @gwangju      = (SELECT company_id FROM fin_companies WHERE name = '광주은행');
SET @nh           = (SELECT company_id FROM fin_companies WHERE name = '농협은행주식회사');
SET @suhyup       = (SELECT company_id FROM fin_companies WHERE name = '수협은행');
SET @jeju         = (SELECT company_id FROM fin_companies WHERE name = '제주은행');


-- ===== 2. 다시 실행할 때를 위해 이 상품들의 기존 조건 삭제 =====
DELETE FROM product_pref_conditions
WHERE product_id IN (1, 10, 11, 14, 18, 23, 31, 34, 39, 47, 49, 50);


-- ===== 3. 우대조건 넣기 =====
-- 컬럼 순서: 상품번호, 유형, 가산금리(%p), 카드사(카드실적일 때만), 기준금액(원/월), 원문 조각
-- 카드 기준금액: 원문이 "기간 누적"이면 12개월로 나눠 월 금액으로 환산 (description에 표시)
-- 카드 기준금액이 원문에 없으면 0 (= 그 카드를 쓰기만 하면 충족으로 계산)

INSERT INTO product_pref_conditions
    (product_id, type_id, bonus_rate, card_company_id, required_amount, description) VALUES

-- [1] 우리은행 우리SUPER주거래적금
(1,  @salary,  0.70, NULL,        NULL,   '급여/연금 이체 (계약기간 1/2 이상)'),
(1,  @autopay, 0.30, NULL,        NULL,   '공과금 자동이체 출금'),
(1,  @card,    0.30, @woori_card, 100000, '우리카드 신용/체크 결제 10만원 이상'),
(1,  @mkt,     0.10, NULL,        NULL,   '마케팅 동의(전화·SMS) 만기까지 유지'),
-- 금리쿠폰은 가산금리 수치가 없어 제외

-- [10] 광주은행 해피라이프_여행스케치적금V
(10, @etc,     0.50, NULL,     NULL,   '여행스케치외화적금V 동일자 가입'),
(10, @etc,     0.20, NULL,     NULL,   '해지원금 500만원 이상 (최고)'),
(10, @card,    0.30, @gwangju, 250000, '카드 사용실적 300만원 이상 → 월 25만원 환산'),
(10, @mkt,     0.20, NULL,     NULL,   '개인(신용)정보 동의'),

-- [11] 광주은행 여행스케치_남도투어적금
(11, @etc,     1.50, NULL,     NULL,   '전라남도 관광지 방문 인증 (최고)'),
(11, @card,    0.30, @gwangju, 250000, '카드 사용실적 300만원 이상 → 월 25만원 환산'),
(11, @mkt,     0.10, NULL,     NULL,   '개인(신용)정보 동의'),

-- [14] 제주은행 MZ 플랜적금
(14, @etc,     0.50, NULL,  NULL,   '매월 1회 이상 지속 납입 (1년제)'),
(14, @etc,     0.50, NULL,  NULL,   '목표 금액 달성'),
(14, @card,    0.50, @jeju, 100000, '신용·체크카드 합산 월 10만원 이상'),
(14, @etc,     0.50, NULL,  NULL,   '청년이니까응원합니다 이벤트'),

-- [18] 경남은행 행복 DREAM 적금
(18, @first,   0.20, NULL,      NULL,   '신규일 6개월 전까지 당행 적금 미보유'),
(18, @etc,     0.20, NULL,      NULL,   '월부금 50만원 이상'),
(18, @autopay, 0.20, NULL,      NULL,   '이 예금 자동이체 납입'),
(18, @card,    0.20, @kyongnam, 100000, '익월 말까지 카드 최초 발급 + 10만원 이상 이용'),
(18, @mkt,     0.20, NULL,      NULL,   '가입 전 마케팅 동의'),

-- [23] 경남은행 오면우대! 하면우대! 정기적금 — 신규고객 조건만 반영
(23, @first,   3.00, NULL,      NULL,   '[신규고객] 적금 가입 시'),
(23, @mkt,     0.10, NULL,      NULL,   '[신규고객] 가입 전 마케팅 동의'),
(23, @card,    2.00, @kyongnam, 100000, '[신규고객] 3개월간 10만원 이상 경남은행 카드 결제'),

-- [31] KB국민은행 KB내맘대로적금 — 9개 중 6개 선택, 항목당 0.1%p (최고 0.6%p)
(31, @salary,  0.10, NULL,     NULL, '급여이체'),
(31, @card,    0.10, @kb_card, 0,    '카드결제계좌 지정'),
(31, @autopay, 0.10, NULL,     NULL, '자동이체 저축'),
(31, @first,   0.10, NULL,     NULL, '첫 거래'),
(31, @sub,     0.10, NULL,     NULL, '주택청약종합저축'),
(31, @etc,     0.10, NULL,     NULL, '아파트관리비 이체 / KB스타뱅킹 이체 / 장기거래 / 소중한 날 중'),

-- [34] 신한은행 신한 알.쏠 적금 (최고 1.30%)
(34, @salary,  0.60, NULL,          NULL, '소득이체'),
(34, @card,    0.30, @shinhan_card, 0,    '카드이용 (기준금액은 상품설명서 확인)'),
(34, @etc,     0.60, NULL,          NULL, '오픈뱅킹'),
(34, @sub,     0.30, NULL,          NULL, '청약보유'),
(34, @mkt,     0.10, NULL,          NULL, '마케팅 동의'),

-- [39] 농협은행 NH직장인월복리적금
(39, @salary,  0.30, NULL, NULL,  '가입기간 중 3개월 이상 급여이체'),
(39, @sub,     0.20, NULL, NULL,  '주택청약종합저축 또는 펀드 가입'),
(39, @card,    0.20, @nh,  85000, 'NH채움카드 결제실적 100만원 이상 → 월 약 8.5만원 환산'),
(39, @online,  0.10, NULL, NULL,  '인터넷(스마트)뱅킹 또는 올원뱅크로 가입'),

-- [47] 수협은행 Sh해양플라스틱Zero!적금 (정액적립식)
(47, @etc,     0.10, NULL, NULL, '해양플라스틱감축서약 (신규 시)'),
(47, @etc,     0.20, NULL, NULL, '봉사활동 또는 상품홍보 (만기 시)'),
(47, @first,   0.20, NULL, NULL, '입출금통장 최초 신규 (만기 시)'),
(47, @autopay, 0.20, NULL, NULL, '자동이체 출금실적: 수협카드/펀드 (만기 시)'),

-- [49] 수협은행 Sh월복리자유적금 (최고 0.7%)
(49, @first,   0.30, NULL,    NULL, '첫거래고객'),
(49, @card,    0.30, @suhyup, 0,    '카드거래 (최대, 기준은 상품설명서 확인)'),
(49, @etc,     0.10, NULL,    NULL, '복수거래'),
(49, @etc,     0.20, NULL,    NULL, '요구불거래 (최대)'),
(49, @online,  0.10, NULL,    NULL, '인터넷뱅킹고객'),
(49, @autopay, 0.10, NULL,    NULL, '자동이체실적'),

-- [50] 수협은행 Sh해양플라스틱Zero!적금 (자유적립식) — 47번과 조건 같음
(50, @etc,     0.10, NULL, NULL, '해양플라스틱감축서약 (신규 시)'),
(50, @etc,     0.20, NULL, NULL, '봉사활동 또는 상품홍보 (만기 시)'),
(50, @first,   0.20, NULL, NULL, '입출금통장 최초 신규 (만기 시)'),
(50, @autopay, 0.20, NULL, NULL, '자동이체 출금실적: 수협카드/펀드 (만기 시)');

-- [46] 케이뱅크 주거래우대 자유적금은 제외:
--      원문에 "최고 연 0.6%"만 있고 항목별 금리가 없어서 쪼갤 수 없음


-- ===== 4. 확인 =====
-- 상품별로 몇 줄로 쪼개졌는지, 가산금리 합계
SELECT p.product_id, p.product_name, COUNT(*) AS 조건수, SUM(pc.bonus_rate) AS 가산금리합계
FROM product_pref_conditions pc
JOIN deposit_products p ON p.product_id = pc.product_id
GROUP BY p.product_id, p.product_name
ORDER BY p.product_id;

-- 카드실적 조건만: 어느 적금이 어느 카드사 카드를 월 얼마 이상 쓰면 금리를 더 주는지
SELECT p.product_name, f.name AS 카드사, pc.required_amount AS 월기준액, pc.bonus_rate
FROM product_pref_conditions pc
JOIN deposit_products p ON p.product_id = pc.product_id
JOIN fin_companies f    ON f.company_id = pc.card_company_id
ORDER BY pc.bonus_rate DESC;
