// 내금리 MVP 프론트: 화면 상태 하나로 돌리는 단일 페이지
// 데이터는 모두 /api/meta, /api/calc, /api/detail 에서 받는다 (server.py)

const $app = document.getElementById('app');
const won = n => Math.round(n).toLocaleString('ko-KR');
const man = n => (n % 10000 === 0 ? `${n / 10000}만` : `${(n / 10000).toFixed(1)}만`) + ' 원';
const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));

const ICON = {'교통':'🚌','통신':'📱','커피':'☕','쇼핑':'🛍️','해외결제':'✈️','배달':'🛵','디지털구독':'🎬','간편결제':'💳',
  '마트/편의점':'🛒','공과금':'🧾','주유':'⛽','음식점':'🍽️','뷰티/패션':'💄','영화':'🎟️'};
const COND_HELP = {'자동이체':'공과금이나 카드값을 이 통장에서 빠져나가게 할 수 있어요','첫거래':'처음 거래하는 은행이어도 괜찮아요',
  '비대면가입':'앱으로 가입할 수 있어요','마케팅동의':'은행 광고 수신에 동의할 수 있어요','청약보유':'주택청약 통장이 있어요'};

const state = {
  meta: null, screen: 'splash', onboard: 0,
  picked: [], spending: {}, bank: undefined, conditions: [],
  saving: 0, term: null, result: null, detail: null, selected: null,
};

const BACK = `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M15 18l-6-6 6-6"/></svg>`;
const topBar = (title, back) => `<div class="top">${back ? `<button class="icon-btn" data-go="${back}" aria-label="이전">${BACK}</button>` : ''}<span class="title">${title}</span></div>`;
const head = (step, title, sub) => `<div class="head">${step ? `<span class="step"><b>${step}</b> / 3</span>` : ''}<h1>${title}</h1>${sub ? `<p>${sub}</p>` : ''}</div>`;
const cardArt = (label) => `<div class="art" aria-hidden="true">
  <div class="blob" style="left:70px;top:70px;width:70px;height:70px"></div>
  <div class="card" style="left:calc(50% - 84px);top:60px;width:168px;height:108px;transform:rotate(-10deg)"><div class="chipgold"></div></div>
  <div class="coin" style="left:calc(50% + 40px);top:140px;width:58px;height:58px">${label || '%'}</div></div>`;

function go(screen) { state.screen = screen; render(); window.scrollTo(0, 0); }

// ---------------------------------------------------------------- API
async function api(path, body) {
  const res = await fetch(path, body ? {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body)} : {});
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw Object.assign(new Error(data.error || '서버 오류'), {status: res.status});
  return data;
}
const payload = () => ({
  spending: Object.fromEntries(state.picked.map(id => [id, state.spending[id] || 0])),
  salary_bank_id: state.bank || null, conditions: state.conditions,
  monthly_saving: state.saving, term: state.term,
});
const totalSpend = () => state.picked.reduce((s, id) => s + (state.spending[id] || 0), 0);

async function runCalc() {
  go('loading');
  try {
    const [r] = await Promise.all([api('/api/calc', payload()), new Promise(ok => setTimeout(ok, 700))]);
    state.result = r;
    go(r.status === 'no_result' ? 'noResult' : r.status === 'low_spend' ? 'lowSpend' : 'results');
  } catch (e) {
    state.error = e.message; go('fail');
  }
}
async function openDetail(i) {
  state.selected = state.result.combos[i]; state.detail = null; go('detail');
  try {
    state.detail = await api('/api/detail', {...payload(), card_id: state.selected.card_id, option_id: state.selected.option_id});
  } catch (e) { state.detail = {error: e.message}; }
  if (state.screen === 'detail') render();
}

// ---------------------------------------------------------------- 화면
const screens = {
  splash: () => `<section class="screen splash"><div class="logo">내금리</div><p>카드와 적금, 한 번에 계산</p></section>`,

  onboard: () => {
    const slides = [
      ['카드 혜택, 실적을 못 채우면<br>0원이에요', '내 지출로 실제 받는 혜택만 계산해요', '0원'],
      ['적금 최고금리는<br>조건을 다 채워야 나와요', '내가 채울 수 있는 조건만 넣어서 계산해요', '%'],
      ['카드와 적금을 같이 보면<br>순위가 바뀌어요', '한 달에 실제로 남는 돈 순서로 보여드려요', '+'],
    ];
    const [t, s, c] = slides[state.onboard];
    return `<section class="screen">${topBar('', null)}${cardArt(c)}
      ${head('', t, s)}<div class="dots">${slides.map((_, i) => `<i class="${i === state.onboard ? 'on' : ''}"></i>`).join('')}</div>
      <div class="grow"></div><div class="foot"><button class="btn" data-act="onboardNext">${state.onboard < 2 ? '다음' : '시작하기'}</button></div></section>`;
  },

  intro: () => `<section class="screen">${topBar('정보 입력', 'onboard')}${cardArt('3')}
    ${head('', '세 가지만 알려주세요', '어디에 얼마 쓰는지, 월급 통장, 모을 금액이면 돼요.<br>입력한 내용은 계산에만 쓰고 저장하지 않아요.')}
    <div class="grow"></div><div class="foot"><button class="btn" data-go="pick">시작하기</button></div></section>`,

  pick: () => {
    const cats = state.meta.categories;
    return `<section class="screen">${topBar('정보 입력', 'intro')}
      ${head(1, '한 달에 어디에 돈을 쓰나요?', '자주 쓰는 곳을 모두 골라 주세요')}
      <div class="chips">${cats.map(c => `<button class="chip" data-pick="${c.id}" aria-pressed="${state.picked.includes(c.id)}"><span class="ico">${ICON[c.name] || '•'}</span>${esc(c.name)}</button>`).join('')}</div>
      <div class="grow"></div><div class="foot"><button class="btn" data-go="amount" ${state.picked.length ? '' : 'disabled'}>${state.picked.length ? `${state.picked.length}곳 고름 · 다음` : '다음'}</button></div></section>`;
  },

  amount: () => {
    const cats = state.meta.categories.filter(c => state.picked.includes(c.id));
    const total = totalSpend();
    return `<section class="screen">${topBar('정보 입력', 'pick')}
      ${head(1, '한 달에 얼마 쓰나요?', '대략적인 금액이면 충분해요')}
      <div class="fields">${cats.map(c => `<div class="field"><label for="amt-${c.id}">${ICON[c.name] || ''} ${esc(c.name)}</label>
        <input id="amt-${c.id}" data-amt="${c.id}" inputmode="numeric" placeholder="0" value="${state.spending[c.id] ? won(state.spending[c.id]) : ''}"><span class="unit">원</span></div>`).join('')}
        <div class="total"><span>월 합계</span><b id="sum">${won(total)}원</b></div>
        ${state.amountError ? `<span class="err" role="alert">${state.amountError}</span>` : ''}</div>
      <div class="grow"></div><div class="foot"><button class="btn" data-act="amountNext">다음</button></div></section>`;
  },

  bank: () => `<section class="screen">${topBar('정보 입력', 'amount')}
    ${head(2, '월급은 어느 은행으로 받나요?', '급여이체 우대금리를 계산할 때 써요')}
    <div class="list">${state.meta.banks.map(b => `<button class="row" data-bank="${b.id}" aria-pressed="${state.bank === b.id}">${esc(b.name)}</button>`).join('')}
      <button class="row" data-bank="0" aria-pressed="${state.bank === 0}">없어요 · 아직 정하지 않았어요</button></div>
    <div class="grow"></div><div class="foot"><button class="btn" data-go="cond" ${state.bank === undefined ? 'disabled' : ''}>다음</button></div></section>`,

  cond: () => `<section class="screen">${topBar('정보 입력', 'bank')}
    ${head(2, '할 수 있는 것을 골라 주세요', '고른 조건만 우대금리에 넣어요. 카드 실적은 고른 카드로 자동 계산해요.')}
    <div class="list">${state.meta.conditions.map(c => `<button class="row" role="checkbox" data-cond="${c.id}" aria-checked="${state.conditions.includes(c.id)}">
      <span>${esc(c.name)}<small>${COND_HELP[c.name] || ''}</small></span><span class="box" aria-hidden="true">${state.conditions.includes(c.id) ? '✓' : ''}</span></button>`).join('')}</div>
    <div class="grow"></div><div class="foot"><button class="btn" data-go="saving">${state.conditions.length ? `${state.conditions.length}개 고름 · 다음` : '해당 없음 · 다음'}</button></div></section>`,

  saving: () => `<section class="screen">${topBar('정보 입력', 'cond')}
    ${head(3, '매달 얼마씩 모을까요?', '')}
    <div class="big ${state.savingError ? 'invalid' : ''}"><label for="save" class="sr" style="position:absolute;width:1px;height:1px;overflow:hidden">매달 넣을 금액</label>
      <div class="wrap"><input id="save" inputmode="numeric" placeholder="0" value="${state.saving ? won(state.saving) : ''}" aria-invalid="${!!state.savingError}" ${state.savingError ? 'aria-describedby="save-err"' : ''}><span class="won">원</span></div>
      ${state.savingError ? `<span class="err" id="save-err" role="alert">${state.savingError}</span>` : ''}
      <div class="quick">${[100000, 300000, 500000, 1000000].map(v => `<button data-quick="${v}">${man(v)}</button>`).join('')}</div></div>
    <div class="grow"></div><div class="foot"><button class="btn" data-act="savingNext">다음</button></div></section>`,

  term: () => `<section class="screen">${topBar('정보 입력', 'saving')}
    ${head(3, '얼마 동안 모을까요?', '같은 기간 적금끼리만 비교해요')}
    <div class="list">${state.meta.terms.map(t => `<button class="row" data-term="${t.term}" aria-pressed="${state.term === t.term}">
      <span>${t.term}개월<small>적금 ${t.products}개</small></span><span style="font-size:13px">총 ${man(state.saving * t.term)}</span></button>`).join('')}</div>
    <div class="grow"></div><div class="foot"><span class="hint">월 ${man(state.saving)} · 세후 이자로 계산해요</span>
      <button class="btn" data-act="calc" ${state.term ? '' : 'disabled'}>결과 보기</button></div></section>`,

  loading: () => `<section class="screen" style="justify-content:center;gap:20px;text-align:center">
    <div class="spinner" role="progressbar" aria-label="계산 중"></div>
    <h1>카드와 적금을<br>하나씩 맞춰보고 있어요</h1><p class="lead">실적, 월 한도, 우대조건까지 계산 중이에요</p></section>`,

  results: () => {
    const r = state.result, [best, ...rest] = r.combos;
    const cardNet = best.card_benefit - best.fee_month, sum = Math.max(1, Math.max(0, cardNet) + best.interest_month);
    return `<section class="screen">${topBar('결과', 'term')}
      <p class="hint" style="padding:12px 24px 0">월 지출 ${man(r.total_spending)} · 매달 ${man(r.input.monthly_saving)} · ${r.input.term}개월 <button class="link" data-go="amount">수정</button></p>
      ${cardArt('1위').replace('class="art"', 'class="art small"').replace(/top:60px/, 'top:24px').replace(/top:140px/, 'top:84px').replace(/top:70px/, 'top:30px')}
      <div class="detail-hero" style="padding-top:0"><span class="lead">한 달에 남는 돈</span><span class="amt" style="color:var(--ink)">+${won(best.monthly_gain)}원</span>
        <span style="font-size:15px;font-weight:600;line-height:1.5">${esc(best.card_name)}<br><span style="color:var(--sub);font-weight:500">+ ${esc(best.product_name)} ${best.my_rate}%</span></span></div>
      <div class="bar" aria-hidden="true"><i style="width:${Math.max(0, cardNet) / sum * 100}%;background:var(--accent)"></i><i style="width:${best.interest_month / sum * 100}%;background:var(--orange)"></i></div>
      <div class="legend"><span><b style="background:var(--accent)"></b>카드 ${won(cardNet)}원</span><span><b style="background:var(--orange)"></b>적금 ${won(best.interest_month)}원</span></div>
      ${rest.length ? `<div class="box2"><h2>다른 조합 <small style="font-size:12px;font-weight:400;color:var(--mute)">한 달에 남는 돈</small></h2>
        ${rest.map((c, i) => `<button class="combo" data-detail="${i + 1}"><span class="rank">${i + 2}</span>
          <span class="txt"><span class="t1">${esc(c.card_name)}</span><span class="t2">${esc(c.bank)} ${esc(c.product_name)} · ${c.my_rate}%</span></span>
          <span class="gain">+${won(c.monthly_gain)}원</span></button>`).join('')}</div>` : ''}
      <p class="note">금융상품한눈에 공시 금리와 카드사 상품설명서 기준의 예상치예요. 실제 혜택은 세부 조건에 따라 달라질 수 있어요. 가입이나 신청은 각 금융사에서 직접 확인해 주세요.</p>
      <div class="grow"></div><div class="foot"><button class="btn" data-detail="0">1위 조합 자세히 보기</button></div></section>`;
  },

  detail: () => {
    const c = state.selected, d = state.detail;
    const cardNet = c.card_benefit - c.fee_month, sum = Math.max(1, cardNet + c.interest_month);
    let body = `<div style="padding:40px"><div class="spinner"></div></div>`;
    if (d && d.error) body = `<p class="note">상세 내용을 불러오지 못했어요. ${esc(d.error)}</p>`;
    else if (d) {
      const cardBox = `<div class="box2"><h2>카드 혜택 <span>${won(cardNet)}원</span></h2>
        <p class="sub">${esc(c.card_company)} · 전월실적 ${c.min_spending ? man(c.min_spending) : '없음'} · 연회비 월 ${won(c.fee_month)}원</p>
        ${d.met_min_spending ? '' : `<p class="warnline">월 지출이 전월실적보다 적어서 혜택이 0원이에요</p>`}
        ${d.benefits.map(b => `<div class="line ${b.amount ? '' : 'off'}"><span class="l">${esc(b.category)} ${b.rate}%<small>${esc(b.description || '')}${b.limit ? ` · 월 한도 ${won(b.limit)}원` : ''}</small></span>
          <span class="r">${b.amount ? `+${won(b.amount)}원` : (b.spend ? '0원' : '지출 없음')}</span></div>`).join('')}
        <div class="line"><span class="l">연회비 ÷ 12</span><span class="r">−${won(c.fee_month)}원</span></div></div>`;
      body = `<div class="box2"><h2>적금 이자 <span>월 ${won(c.interest_month)}원</span></h2>
        <p class="sub">${esc(c.bank)} · 기본 ${c.base_rate}% → 내 금리 ${c.my_rate}% (최고 ${c.max_rate}%) · 만기 세후 이자 ${won(c.interest)}원</p>
        ${d.conditions.length ? d.conditions.map(p => `<div class="line ${p.met ? '' : 'off'}"><span class="l"><span><span class="tag ${p.met ? 'ok' : 'no'}">${p.met ? '충족' : '미충족'}</span>${esc(p.type)}</span>
          <small>${esc(p.description || '')}</small></span><span class="r">+${p.bonus_rate}%p</span></div>`).join('')
          : `<p class="sub">이 상품은 우대조건이 아직 정리되지 않아 기본금리로 계산했어요.</p>`}</div>` + cardBox;
    }
    return `<section class="screen">${topBar('조합 상세', 'results')}
      <div class="detail-hero"><span class="lead" style="font-size:14px">${esc(c.card_name)} + ${esc(c.product_name)}</span><span class="amt">한 달 +${won(c.monthly_gain)}원</span></div>
      <div class="bar" aria-hidden="true"><i style="width:${Math.max(0, cardNet) / sum * 100}%;background:var(--accent)"></i><i style="width:${c.interest_month / sum * 100}%;background:var(--orange)"></i></div>
      <div class="legend"><span><b style="background:var(--accent)"></b>카드 ${won(cardNet)}원</span><span><b style="background:var(--orange)"></b>적금 ${won(c.interest_month)}원</span></div>
      ${body}<div style="height:32px"></div></section>`;
  },

  lowSpend: () => {
    const r = state.result;
    return `<section class="screen">${topBar('결과', 'term')}${cardArt('30만')}
      ${head('', '지금 지출로는<br>카드 혜택이 크지 않아요', `대부분 전월실적 30만 원부터라<br>월 <b style="color:var(--ink)">${man(r.needed_spending)}</b>을 더 써야 혜택이 시작돼요`)}
      ${r.no_min_cards.length ? `<div class="box2"><h2>실적 조건 없는 카드</h2><p class="sub">혜택 − 연회비, 월</p>
        ${r.no_min_cards.map(c => `<div class="line ${c.net < 0 ? 'off' : ''}"><span class="l">${esc(c.card_name)}<small>혜택 ${won(c.card_benefit)} · 연회비 ${c.fee_month ? won(c.fee_month) : '없음'}</small></span>
          <span class="r" style="color:${c.net < 0 ? 'var(--warn)' : 'var(--accent)'}">${c.net >= 0 ? '+' : '−'}${won(Math.abs(c.net))}원</span></div>`).join('')}</div>` : ''}
      <div class="grow"></div><div class="foot"><span class="hint">지금은 적금 우대조건을 챙기는 쪽이 더 이득이에요</span>
        <button class="btn" data-go="results">그래도 전체 조합 보기</button></div></section>`;
  },

  noResult: () => {
    const r = state.result, alt = r.other_terms[0];
    return `<section class="screen">${topBar('결과', 'term')}${cardArt('?')}
      ${head('', `${r.input.term}개월 적금 중에는<br>맞는 조합이 없어요`, '기간을 바꾸거나 고른 조건을 바꾸면 다시 찾아볼게요')}
      <div class="grow"></div><div class="foot">${alt ? `<button class="btn" data-retry-term="${alt}">${alt}개월로 다시 보기</button>` : ''}
        <button class="btn ghost" data-go="cond">조건 다시 고르기</button></div></section>`;
  },

  fail: () => `<section class="screen">${topBar('결과', 'term')}${cardArt('↻')}
    ${head('', '계산을 마치지 못했어요', '잠시 후 다시 시도해 주세요.<br>입력한 내용은 그대로 남아 있어요.')}
    <p class="hint" style="padding-top:8px">${esc(state.error || '')}</p>
    <div class="grow"></div><div class="foot"><button class="btn" data-act="calc">다시 시도</button><button class="btn ghost" data-go="amount">입력 내용 확인</button></div></section>`,

  metaFail: () => `<section class="screen" style="justify-content:center;text-align:center;gap:12px;padding:24px">
    <h1>서버에 연결하지 못했어요</h1><p class="lead">python app/server.py 가 켜져 있는지, .env의 MySQL 정보가 맞는지 확인해 주세요.</p>
    <p class="hint">${esc(state.error || '')}</p></section>`,
};

function render() { $app.innerHTML = screens[state.screen](); }

// ---------------------------------------------------------------- 이벤트
const digits = s => parseInt(String(s).replace(/[^0-9]/g, '') || '0', 10);

$app.addEventListener('click', e => {
  const t = e.target.closest('button'); if (!t) return;
  const d = t.dataset;
  if (d.go) return go(d.go);
  if (d.pick) { const id = +d.pick; state.picked = state.picked.includes(id) ? state.picked.filter(x => x !== id) : [...state.picked, id]; return render(); }
  if (d.bank !== undefined) { state.bank = +d.bank; return render(); }
  if (d.cond) { const id = +d.cond; state.conditions = state.conditions.includes(id) ? state.conditions.filter(x => x !== id) : [...state.conditions, id]; return render(); }
  if (d.quick) { state.saving = +d.quick; state.savingError = ''; return render(); }
  if (d.term) { state.term = +d.term; return render(); }
  if (d.detail) return openDetail(+d.detail);
  if (d.retryTerm) { state.term = +d.retryTerm; return runCalc(); }
  switch (d.act) {
    case 'onboardNext': if (state.onboard < 2) { state.onboard++; render(); } else go('intro'); break;
    case 'amountNext':
      state.amountError = totalSpend() > 0 ? '' : '금액을 한 곳 이상 입력해 주세요';
      state.amountError ? render() : go('bank'); break;
    case 'savingNext':
      state.savingError = state.saving >= 10000 ? '' : '1만 원 이상 입력해 주세요';
      state.savingError ? render() : go('term'); break;
    case 'calc': runCalc(); break;
  }
});

$app.addEventListener('input', e => {
  const el = e.target;
  if (el.dataset.amt) {
    state.spending[+el.dataset.amt] = digits(el.value);
    el.value = state.spending[+el.dataset.amt] ? won(state.spending[+el.dataset.amt]) : '';
    document.getElementById('sum').textContent = won(totalSpend()) + '원';
  }
  if (el.id === 'save') { state.saving = digits(el.value); el.value = state.saving ? won(state.saving) : ''; }
});

// ---------------------------------------------------------------- 시작
render();
Promise.all([api('/api/meta'), new Promise(ok => setTimeout(ok, 1000))])
  .then(([m]) => { state.meta = m; go('onboard'); })
  .catch(err => { state.error = err.message; go('metaFail'); });
