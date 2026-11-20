-- 카드 이미지 출처 컬럼 추가와 공식 페이지 주소 입력
-- 이미지 파일은 카드사 저작물이라 저장소에 넣지 않고, 공식 주소와 확인일만 기록한다.
-- 수업 과제·포트폴리오 시안용. 공개 서비스 전에는 카드사 사용 허락이 필요하다.
USE finance_db;

ALTER TABLE cards
  ADD COLUMN image_url        VARCHAR(300) NULL COMMENT '카드사 공식 이미지 주소',
  ADD COLUMN source_url       VARCHAR(300) NULL COMMENT '확인한 공식 상품 페이지',
  ADD COLUMN image_checked_on DATE         NULL COMMENT '확인한 날짜';

-- 카드 이름은 cards.card_name과 같아야 한다. 맞는 줄이 없으면 0 rows affected로 끝난다.
UPDATE cards SET image_url = 'https://www.shinhancard.com/static/images/card/plate/AUAARH_00_v_f_s.png', source_url = 'https://www.shinhancard.com/pconts/html/card/apply/credit/1187937_2207.html', image_checked_on = '2026-11-20'
 WHERE card_name = '신한카드 Mr.Life';
UPDATE cards SET image_url = 'https://www.shinhancard.com/static/images/card/plate/POHDXD_G4_v_f_s.png', source_url = 'https://www.shinhancard.com/pconts/html/card/apply/credit/1237252_2207.html', image_checked_on = '2026-11-20'
 WHERE card_name = '신한카드 Simple Plan+';
UPDATE cards SET image_url = 'https://www.shinhancard.com/static/images/card/plate/BUBDWW_E5_v_f_s.png', source_url = 'https://www.shinhancard.com/pconts/html/card/apply/check/1237542_2206.html', image_checked_on = '2026-11-20'
 WHERE card_name = '신한카드 SOL트립앤J 체크';
UPDATE cards SET source_url = 'https://m.wooricard.com/ai-data/card_500044.html', image_checked_on = '2026-11-20'
 WHERE card_name = '카드의정석2 SUPER';
UPDATE cards SET source_url = 'https://www.samsungcard.com/personal/card/cardfinder/UHPPCA0102M0.jsp?code=AAP1483', image_checked_on = '2026-11-20'
 WHERE card_name = '삼성카드 taptap O';
UPDATE cards SET source_url = 'https://www.lottecard.co.kr/app/LPCDADB_V100.lc?vtCdKndC=P14028-A14028', image_checked_on = '2026-11-20'
 WHERE card_name = 'LOCA 365 카드';
UPDATE cards SET source_url = 'https://www.hyundaicard.com/HCSP/Alphabet_Life.html', image_checked_on = '2026-11-20'
 WHERE card_name = '알파벳카드O';
UPDATE cards SET source_url = 'https://www.hyundaicard.com/HCSP/Alphabet_Life.html', image_checked_on = '2026-11-20'
 WHERE card_name = '알파벳카드B';
UPDATE cards SET image_url = 'https://m.hanacard.co.kr/images/mymass/card-apply/img-crd-01.webp', source_url = 'https://m.hanacard.co.kr/MKCDCM1000M.web?CD_PD_SEQ=19159', image_checked_on = '2026-11-20'
 WHERE card_name = 'MOVING카드 ALLDAY모드';

-- 확인
SELECT card_name, image_url IS NOT NULL AS has_image, source_url, image_checked_on
FROM cards ORDER BY has_image DESC, card_name;
