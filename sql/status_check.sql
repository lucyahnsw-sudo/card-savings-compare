-- =====================================================================
-- finance_db 진행 상황 점검 (Workbench에서 실행 → 결과 표를 그대로 복사해서 보내기)
-- 아무것도 바꾸지 않고 숫자만 읽어옴
-- =====================================================================
USE finance_db;

SELECT '1. 테이블 수 (목표 13)' AS 항목,
       (SELECT COUNT(*) FROM information_schema.tables
         WHERE table_schema = 'finance_db' AND table_type = 'BASE TABLE') AS 값
UNION ALL SELECT '2. VIEW 수 (목표 4)',
       (SELECT COUNT(*) FROM information_schema.tables
         WHERE table_schema = 'finance_db' AND table_type = 'VIEW')
UNION ALL SELECT '3. 은행 수',            (SELECT COUNT(*) FROM fin_companies WHERE company_type = '은행')
UNION ALL SELECT '4. 카드사 수',          (SELECT COUNT(*) FROM fin_companies WHERE company_type = '카드사')
UNION ALL SELECT '5. 적금 상품 수 (API 59)', (SELECT COUNT(*) FROM deposit_products)
UNION ALL SELECT '6. 금리 옵션 수 (API 178)', (SELECT COUNT(*) FROM rate_options)
UNION ALL SELECT '7. 우대조건 줄 수 (목표 54)', (SELECT COUNT(*) FROM product_pref_conditions)
UNION ALL SELECT '8. 우대조건 입력된 상품 수 (목표 12)',
       (SELECT COUNT(DISTINCT product_id) FROM product_pref_conditions)
UNION ALL SELECT '9. 카드사 연결된 카드실적 조건 수',
       (SELECT COUNT(*) FROM product_pref_conditions WHERE card_company_id IS NOT NULL)
UNION ALL SELECT '10. 카드 수 (전체)',     (SELECT COUNT(*) FROM cards)
UNION ALL SELECT '11. 그중 샘플 카드 (지울 것)', (SELECT COUNT(*) FROM cards WHERE card_name LIKE '%샘플%')
UNION ALL SELECT '12. 카드 혜택 줄 수',    (SELECT COUNT(*) FROM card_benefits)
UNION ALL SELECT '13. 혜택 카테고리 수 (cards_insert 실행 시 15)',
       (SELECT COUNT(*) FROM benefit_categories)
UNION ALL SELECT '14. 월 한도 채울 혜택 (20% 이상, 한도 없음)',
       (SELECT COUNT(*) FROM card_benefits WHERE rate >= 20 AND monthly_limit IS NULL)
UNION ALL SELECT '15. 우대조건 카드사와 실제 카드가 연결된 수',
       (SELECT COUNT(DISTINCT pc.card_company_id) FROM product_pref_conditions pc
          JOIN cards c ON c.company_id = pc.card_company_id)
UNION ALL SELECT '16. 회원 수',            (SELECT COUNT(*) FROM users)
UNION ALL SELECT '17. 회원 소비패턴 줄 수', (SELECT COUNT(*) FROM user_spending)
UNION ALL SELECT '18. 회원 충족조건 줄 수', (SELECT COUNT(*) FROM user_conditions)
UNION ALL SELECT '19. 만들어진 VIEW 이름',
       (SELECT IFNULL(GROUP_CONCAT(table_name ORDER BY table_name), '없음')
          FROM information_schema.tables
         WHERE table_schema = 'finance_db' AND table_type = 'VIEW');
