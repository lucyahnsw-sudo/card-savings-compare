-- =====================================================================
-- 카드 + 예적금 묶음 추천 서비스 · 테이블 13개
-- 처음부터 다시 만들 때 실행 (기존 finance_db는 지워짐)
-- 계산 VIEW는 02_views.sql
-- =====================================================================

-- ===== setup =====
DROP DATABASE IF EXISTS finance_db;            -- 다시 실행할 때 깨끗하게 시작
CREATE DATABASE finance_db DEFAULT CHARACTER SET utf8mb4;
USE finance_db;


-- =====================================================================
-- Create
-- 다른 테이블이 가리키는(FK 대상) 테이블부터 만든다
-- =====================================================================

-- 1. 금융사: 은행과 카드사를 한 테이블에
CREATE TABLE fin_companies (
    company_id    INT AUTO_INCREMENT PRIMARY KEY,   -- 번호 (자동)
    fin_co_no     VARCHAR(20) UNIQUE,               -- 금융상품한눈에 API 금융사 코드 (카드사는 없어서 NULL 가능)
    name          VARCHAR(30) NOT NULL UNIQUE,      -- 신한은행, 신한카드 ...
    company_type  VARCHAR(10) NOT NULL,             -- 은행 / 카드사
    group_name    VARCHAR(30),                      -- 금융그룹 (신한, KB ...)
    CHECK (company_type IN ('은행', '카드사'))
);

-- 2. 우대조건 유형 (코드표)
CREATE TABLE pref_condition_types (
    type_id  INT AUTO_INCREMENT PRIMARY KEY,
    name     VARCHAR(20) NOT NULL UNIQUE            -- 급여이체, 카드실적, 자동이체 ...
);

-- 3. 카드 혜택 카테고리 (코드표)
CREATE TABLE benefit_categories (
    category_id  INT AUTO_INCREMENT PRIMARY KEY,
    name         VARCHAR(20) NOT NULL UNIQUE        -- 교통, 커피, 쇼핑 ...
);

-- 4. 회원
CREATE TABLE users (
    user_id         INT AUTO_INCREMENT PRIMARY KEY,
    email           VARCHAR(100) NOT NULL UNIQUE,
    nickname        VARCHAR(30)  NOT NULL,
    birth_year      SMALLINT,
    monthly_saving  INT NOT NULL DEFAULT 0,         -- 적금에 매달 넣을 금액 (원)
    CHECK (monthly_saving >= 0)
);

-- 5. 예적금 상품 (금융사 1 : 상품 N)
CREATE TABLE deposit_products (
    product_id    INT AUTO_INCREMENT PRIMARY KEY,
    company_id    INT NOT NULL,                     -- 어느 은행 상품인지
    fin_prdt_cd   VARCHAR(30) NOT NULL,             -- API 상품코드 (은행끼리 겹칠 수 있음)
    product_name  VARCHAR(100) NOT NULL,
    product_type  VARCHAR(10) NOT NULL,             -- 예금 / 적금
    pref_text     VARCHAR(300),                     -- 우대조건 원문 (쪼개기 전, 검증용)
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    CHECK (product_type IN ('예금', '적금')),
    UNIQUE (company_id, fin_prdt_cd),               -- 은행 + 상품코드로 묶어야 유일
    FOREIGN KEY (company_id) REFERENCES fin_companies(company_id)
);

-- 6. 금리 옵션 (상품 1 : 옵션 N) — 기간·적립방식마다 금리가 다름
CREATE TABLE rate_options (
    option_id       INT AUTO_INCREMENT PRIMARY KEY,
    product_id      INT NOT NULL,
    save_term       TINYINT NOT NULL,               -- 저축 기간 (개월)
    rsrv_type       VARCHAR(10) NOT NULL DEFAULT '정액',  -- 정액적립 / 자유적립
    intr_rate_type  VARCHAR(10) NOT NULL DEFAULT '단리',  -- 단리 / 복리
    base_rate       DECIMAL(4,2) NOT NULL,          -- 기본금리 (%)
    max_rate        DECIMAL(4,2) NOT NULL,          -- 최고금리 (%)
    CHECK (save_term > 0),
    CHECK (base_rate >= 0 AND base_rate <= max_rate AND max_rate <= 100),
    CHECK (rsrv_type IN ('정액', '자유')),
    CHECK (intr_rate_type IN ('단리', '복리')),
    UNIQUE (product_id, save_term, rsrv_type, intr_rate_type),
    FOREIGN KEY (product_id) REFERENCES deposit_products(product_id)
);

-- 7. 상품별 우대조건 (상품 1 : 조건 N) — 원문 한 문장을 조건 하나당 한 줄로
CREATE TABLE product_pref_conditions (
    pc_id            INT AUTO_INCREMENT PRIMARY KEY,
    product_id       INT NOT NULL,
    type_id          INT NOT NULL,                  -- 어떤 유형의 조건인지
    bonus_rate       DECIMAL(4,2) NOT NULL,         -- 가산금리 (%p)
    card_company_id  INT NULL,                      -- 카드실적 조건일 때만: 어느 카드사 카드인지
    required_amount  INT NULL,                      -- 기준 금액 (원). 카드 월 30만원 등
    description      VARCHAR(200),                  -- 원문 조각
    CHECK (bonus_rate > 0),
    FOREIGN KEY (product_id)      REFERENCES deposit_products(product_id),
    FOREIGN KEY (type_id)         REFERENCES pref_condition_types(type_id),
    FOREIGN KEY (card_company_id) REFERENCES fin_companies(company_id)
);

-- 8. 카드 (카드사 1 : 카드 N)
CREATE TABLE cards (
    card_id       INT AUTO_INCREMENT PRIMARY KEY,
    company_id    INT NOT NULL,
    card_name     VARCHAR(100) NOT NULL,
    card_type     VARCHAR(10) NOT NULL,             -- 신용 / 체크
    min_spending  INT NOT NULL DEFAULT 0,           -- 전월실적 (원). 0이면 조건 없음
    annual_fee    INT NOT NULL DEFAULT 0,           -- 연회비 (원, 국내전용 기준)
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    CHECK (card_type IN ('신용', '체크')),
    UNIQUE (company_id, card_name),
    FOREIGN KEY (company_id) REFERENCES fin_companies(company_id)
);

-- 9. 카드 혜택 (카드 M : N 카테고리를 푸는 중간 테이블)
CREATE TABLE card_benefits (
    benefit_id     INT AUTO_INCREMENT PRIMARY KEY,
    card_id        INT NOT NULL,
    category_id    INT NOT NULL,
    rate           DECIMAL(5,2) NOT NULL,           -- 혜택률 (%)
    monthly_limit  INT NULL,                        -- 월 한도 (원). NULL이면 한도 없음
    description    VARCHAR(200),
    CHECK (rate > 0 AND rate <= 100),
    FOREIGN KEY (card_id)     REFERENCES cards(card_id),
    FOREIGN KEY (category_id) REFERENCES benefit_categories(category_id)
);

-- 10. 회원 소비 패턴 (회원 M : N 카테고리) — 복합키
CREATE TABLE user_spending (
    user_id         INT NOT NULL,
    category_id     INT NOT NULL,
    monthly_amount  INT NOT NULL,                   -- 월 평균 지출 (원)
    PRIMARY KEY (user_id, category_id),             -- 회원 × 카테고리 = 한 줄
    CHECK (monthly_amount >= 0),
    FOREIGN KEY (user_id)     REFERENCES users(user_id),
    FOREIGN KEY (category_id) REFERENCES benefit_categories(category_id)
);

-- 11. 회원이 충족하는 조건 — company_id가 비어 있을 수 있어서 복합 PK 대신 번호
CREATE TABLE user_conditions (
    uc_id       INT AUTO_INCREMENT PRIMARY KEY,
    user_id     INT NOT NULL,
    type_id     INT NOT NULL,
    company_id  INT NULL,                           -- 어느 금융사에서 (NULL = 어디서든 가능)
    UNIQUE (user_id, type_id, company_id),
    FOREIGN KEY (user_id)    REFERENCES users(user_id),
    FOREIGN KEY (type_id)    REFERENCES pref_condition_types(type_id),
    FOREIGN KEY (company_id) REFERENCES fin_companies(company_id)
);

-- 12. 저장한 조합 (회원 1 : 조합 N)
CREATE TABLE saved_combos (
    combo_id    INT AUTO_INCREMENT PRIMARY KEY,
    user_id     INT NOT NULL,
    card_id     INT NOT NULL,
    option_id   INT NOT NULL,
    created_at  DATETIME DEFAULT NOW(),
    UNIQUE (user_id, card_id, option_id),
    FOREIGN KEY (user_id)   REFERENCES users(user_id),
    FOREIGN KEY (card_id)   REFERENCES cards(card_id),
    FOREIGN KEY (option_id) REFERENCES rate_options(option_id)
);

-- 13. 금리 이력 (옵션 1 : 이력 N) — 매일 수집
CREATE TABLE rate_history (
    history_id    BIGINT AUTO_INCREMENT PRIMARY KEY,
    option_id     INT NOT NULL,
    collected_on  DATE NOT NULL,
    base_rate     DECIMAL(4,2) NOT NULL,
    max_rate      DECIMAL(4,2) NOT NULL,
    UNIQUE (option_id, collected_on),               -- 하루 한 번
    FOREIGN KEY (option_id) REFERENCES rate_options(option_id)
);
