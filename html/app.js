/* qb-pedplacer NUI, RR Ped Placer */

const RES = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'qb-pedplacer';
const IN_GAME = window.invokeNative !== undefined || navigator.userAgent.includes('CitizenFX');

const $  = (sel) => document.querySelector(sel);
const $$ = (sel) => document.querySelectorAll(sel);

const state = {
    data: null,          // payload from client
    activeCat: -1,       // -1 = All Peds
    search: '',
    selected: null,      // { model, label }
    scenarioIdx: 0,      // index into data.scenarios
    scenSearch: '',
    manageSearch: '',
    recents: [],
    peds: [],
    coords: { x: 0, y: 0, z: 0 },
};

function post(cb, data) {
    return fetch(`https://${RES}/${cb}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {}),
    }).then(r => r.json()).catch(() => ({}));
}

/* strip leading emoji/symbols from config category labels */
function cleanLabel(s) {
    return String(s || '').replace(/^[^\w]+/, '').trim();
}

function initials(model) {
    const parts = String(model).split('_');
    const last = parts[parts.length - 1].replace(/\d+/g, '');
    return (last.slice(0, 2) || model.slice(0, 2)).toUpperCase();
}

/* Add-on (streamed) peds have no docs.fivem.net portrait, that URL 404s and the
   tile renders as an empty avatar. Map each add-on model onto the vanilla ped it
   was built from so it still gets a real picture. */
const PORTRAIT_ALIAS = {
    k9_retriever: 'a_c_retriever',   // Police K9, add-on retexture of a_c_retriever
};

function avatarHTML(model) {
    const fb = initials(model);
    const src = PORTRAIT_ALIAS[model] || model;
    return `<img src="https://docs.fivem.net/peds/${src}.webp" loading="lazy"
        onerror="this.parentElement.textContent='${fb}'">`;
}

/*  recents (localStorage)*/
function loadRecents() {
    try { state.recents = JSON.parse(localStorage.getItem('pedplacer_recents') || '[]'); }
    catch (e) { state.recents = []; }
}
function pushRecent(model, label) {
    state.recents = state.recents.filter(r => r.model !== model);
    state.recents.unshift({ model, label });
    state.recents = state.recents.slice(0, 6);
    localStorage.setItem('pedplacer_recents', JSON.stringify(state.recents));
    renderRecents();
}
function renderRecents() {
    const el = $('#recentList');
    if (!state.recents.length) {
        el.innerHTML = '<div class="recent-empty">Nothing placed yet</div>';
        return;
    }
    el.innerHTML = state.recents.map((r, i) => `
        <div class="recent-item" data-i="${i}">
            <div class="recent-thumb">${avatarHTML(r.model)}</div>
            <div class="recent-meta">
                <div class="recent-label">${r.label}</div>
                <div class="recent-model">${r.model}</div>
            </div>
        </div>`).join('');
    el.querySelectorAll('.recent-item').forEach(item => {
        item.addEventListener('click', () => {
            const r = state.recents[+item.dataset.i];
            selectModel(r.model, r.label);
        });
    });
}

/*  categories*/
function allModels() {
    const out = [];
    state.data.categories.forEach(c => c.models.forEach(m => out.push(m)));
    return out;
}
function renderCats() {
    const nav = $('#catNav');
    const total = allModels().length;
    let html = `
        <button class="nav-btn ${state.activeCat === -1 ? 'active' : ''}" data-cat="-1">
            <span class="nv-ic">&#129485;</span> All Peds <span class="nav-count">${total}</span>
        </button>`;
    state.data.categories.forEach((c, i) => {
        html += `
        <button class="nav-btn ${state.activeCat === i ? 'active' : ''}" data-cat="${i}">
            <span class="nv-ic">&#9656;</span> ${cleanLabel(c.label)} <span class="nav-count">${c.models.length}</span>
        </button>`;
    });
    nav.innerHTML = html;
    nav.querySelectorAll('.nav-btn').forEach(b => {
        b.addEventListener('click', () => {
            state.activeCat = +b.dataset.cat;
            renderCats();
            renderGrid();
        });
    });
}

/*  model grid*/
function visibleModels() {
    let models = state.activeCat === -1 ? allModels() : state.data.categories[state.activeCat].models;
    if (state.search) {
        const q = state.search.toLowerCase();
        models = models.filter(m => m.label.toLowerCase().includes(q) || m.model.toLowerCase().includes(q));
    }
    return models;
}
function renderGrid() {
    const models = visibleModels();
    $('#gridTitle').textContent = state.activeCat === -1 ? 'All Peds' : cleanLabel(state.data.categories[state.activeCat].label);
    $('#gridCount').textContent = `${models.length} model${models.length === 1 ? '' : 's'}`;
    const grid = $('#modelGrid');
    if (!models.length) {
        grid.innerHTML = '<div class="grid-empty">No models match your search.</div>';
        return;
    }
    grid.innerHTML = models.map(m => `
        <div class="model-card ${state.selected && state.selected.model === m.model ? 'selected' : ''}"
             data-model="${m.model}" data-label="${m.label.replace(/"/g, '&quot;')}">
            <div class="model-avatar">${avatarHTML(m.model)}</div>
            <div class="model-label">${m.label}</div>
            <div class="model-name">${m.model}</div>
        </div>`).join('');
    grid.querySelectorAll('.model-card').forEach(card => {
        card.addEventListener('click', () => selectModel(card.dataset.model, card.dataset.label));
    });
}

function selectModel(model, label) {
    state.selected = { model, label };
    $('#customModel').value = '';
    $('#mcAvatar').innerHTML = avatarHTML(model);
    $('#mcLabel').textContent = label;
    $('#mcModel').textContent = model;
    $$('.model-card').forEach(c => c.classList.toggle('selected', c.dataset.model === model));
    // jump to settings tab so the flow reads left -> right
    switchPanel('settings');
}

/*  right panel tabs*/
function switchPanel(name) {
    $$('.rp-tab').forEach(t => t.classList.toggle('active', t.dataset.panel === name));
    $$('.rp-panel').forEach(p => p.classList.toggle('active', p.id === 'panel-' + name));
    if (name === 'manage') refreshPeds();
}

/*  scenarios*/
function renderScenarios() {
    const q = state.scenSearch.toLowerCase();
    const list = $('#scenList');
    list.innerHTML = state.data.scenarios.map((s, i) => {
        if (q && !s.label.toLowerCase().includes(q) && !(s.scenario || '').toLowerCase().includes(q)) return '';
        const sub = s.animDict ? `${s.animDict}` : (s.scenario || 'idle');
        return `<div class="scen-item ${i === state.scenarioIdx ? 'selected' : ''}" data-i="${i}">
            ${s.label}<span class="scen-sub">${sub}</span>
        </div>`;
    }).join('') || '<div class="list-empty">No scenarios match.</div>';
    list.querySelectorAll('.scen-item').forEach(el => {
        el.addEventListener('click', () => {
            state.scenarioIdx = +el.dataset.i;
            const s = state.data.scenarios[state.scenarioIdx];
            $('#scenarioBtn').textContent = s.label;
            // picking a real scenario implies scenario behavior; "None" implies idle
            const sel = $('#behaviorSel');
            if ((s.scenario && s.scenario !== '') || s.animDict) {
                if (sel.value === 'idle') sel.value = 'scenario';
            } else if (sel.value === 'scenario') {
                sel.value = 'idle';
            }
            onBehaviorChange();
            renderScenarios();
            switchPanel('settings');
        });
    });
}

/*  behavior fields*/
function onBehaviorChange() {
    const v = $('#behaviorSel').value;
    $('#wanderField').classList.toggle('hidden', v !== 'wander');
    $('#patrolField').classList.toggle('hidden', v !== 'patrol');
    $('#interactField').classList.toggle('hidden', v !== 'interact');
}

/*  manage*/
function fmtDist(d) {
    return d >= 1000 ? (d / 1000).toFixed(1) + 'km' : Math.round(d) + 'm';
}
function renderPeds() {
    const q = state.manageSearch.toLowerCase();
    const px = state.coords;
    let peds = state.peds.map(p => ({
        ...p,
        dist: Math.hypot(p.x - px.x, p.y - px.y, p.z - px.z),
    }));
    if (q) {
        peds = peds.filter(p =>
            String(p.id).includes(q) ||
            (p.label || '').toLowerCase().includes(q) ||
            (p.model || '').toLowerCase().includes(q) ||
            (p.group_name || '').toLowerCase().includes(q));
    }
    peds.sort((a, b) => a.dist - b.dist);
    const list = $('#pedList');
    if (!peds.length) {
        list.innerHTML = '<div class="list-empty">No placed peds found.</div>';
        return;
    }
    list.innerHTML = peds.slice(0, 200).map(p => `
        <div class="ped-item" data-id="${p.id}" data-behavior="${p.behavior || 'idle'}">
            <div class="ped-top">
                <span class="ped-id">#${p.id}</span>
                <span class="ped-name">${p.label || p.model}</span>
                <span class="ped-dist">${fmtDist(p.dist)}</span>
            </div>
            <div class="ped-sub">${p.model} &middot; ${p.behavior || 'idle'}${p.group_name ? ' &middot; ' + p.group_name : ''}</div>
            <div class="ped-actions">
                <button class="pa-btn" data-act="teleport">&#128205; Teleport</button>
                <button class="pa-btn" data-act="move">&#128260; Move Here</button>
                ${(p.behavior === 'patrol') ? '<button class="pa-btn" data-act="record">&#128506; Record Route</button>' : ''}
                <button class="pa-btn danger" data-act="delete">&#128465; Delete</button>
            </div>
        </div>`).join('');
    if (peds.length > 200) list.innerHTML += '<div class="list-empty">Showing nearest 200 - use search to narrow down.</div>';

    list.querySelectorAll('.ped-item').forEach(item => {
        item.addEventListener('click', (e) => {
            if (e.target.closest('.pa-btn')) return;
            const wasOpen = item.classList.contains('open');
            list.querySelectorAll('.ped-item').forEach(i => i.classList.remove('open'));
            if (!wasOpen) item.classList.add('open');
        });
        item.querySelectorAll('.pa-btn').forEach(btn => {
            btn.addEventListener('click', () => {
                const id = +item.dataset.id;
                const act = btn.dataset.act;
                if (act === 'delete' && !btn.classList.contains('confirm')) {
                    btn.classList.add('confirm');
                    btn.textContent = 'Sure?';
                    setTimeout(() => { btn.classList.remove('confirm'); btn.innerHTML = '&#128465; Delete'; }, 2500);
                    return;
                }
                post('managePed', { id, action: act });
                if (act === 'delete') {
                    state.peds = state.peds.filter(p => p.id !== id);
                    renderPeds();
                }
            });
        });
    });
}
function refreshPeds() {
    if (!IN_GAME) { renderPeds(); return; }
    post('getState', {}).then(res => {
        if (res && res.peds) {
            state.peds = res.peds;
            if (res.coords) state.coords = res.coords;
            setPosFields();
        }
        renderPeds();
    });
}

function setPosFields() {
    $('#posX').value = state.coords.x.toFixed(2);
    $('#posY').value = state.coords.y.toFixed(2);
    $('#posZ').value = state.coords.z.toFixed(2);
}

/*  place*/
function doPlace() {
    const custom = $('#customModel').value.trim();
    const model = custom || (state.selected && state.selected.model);
    if (!model) {
        $('#modelChip').style.borderColor = 'var(--red)';
        setTimeout(() => { $('#modelChip').style.borderColor = ''; }, 1200);
        return;
    }
    const label = $('#pedLabel').value.trim() || (custom ? custom : state.selected.label);
    const s = state.data.scenarios[state.scenarioIdx] || {};
    const behavior = $('#behaviorSel').value;
    const payload = {
        model,
        label,
        scenario: s.scenario || '',
        animDict: s.animDict || '',
        animName: s.animName || '',
        behavior,
        weapon: $('#weaponSel').value,
        invincible: $('#chkInvincible').checked,
        frozen: $('#chkFrozen').checked,
        wanderRadius: parseFloat($('#wanderRadius').value) || 15.0,
        patrolSpeed: parseFloat($('#patrolSpeed').value) || 1.0,
        interactType: $('#interactSel').value,
        groupName: $('#groupName').value.trim(),
        heading: parseInt($('#headingSlider').value, 10),
    };
    pushRecent(model, label);
    post('placePed', payload);
    hideApp();
}

/*  open / close*/
function hideApp() { $('#app').classList.add('hidden'); }
function closeUI() { hideApp(); post('close'); }

function openApp(data) {
    state.data = data;
    if (data.coords) state.coords = data.coords;
    state.peds = data.peds || [];
    setPosFields();
    if (typeof data.heading === 'number') {
        $('#headingSlider').value = Math.round(data.heading);
        $('#headingVal').textContent = Math.round(data.heading) + '°';
    }
    // weapons
    $('#weaponSel').innerHTML = data.weapons.map(w => `<option value="${w.weapon}">${w.label}</option>`).join('');
    // interactions
    $('#interactSel').innerHTML = data.interactions.map(i => `<option value="${i.scenario}">${i.label}</option>`).join('');
    renderCats();
    renderGrid();
    renderScenarios();
    renderRecents();
    renderPeds();
    $('#app').classList.remove('hidden');
    $('#searchInput').focus();
}

/*  events*/
window.addEventListener('message', (e) => {
    const msg = e.data || {};
    if (msg.action === 'open') openApp(msg.data);
    if (msg.action === 'close') hideApp();
});

document.addEventListener('keyup', (e) => {
    if (e.key === 'Escape') closeUI();
});

document.addEventListener('DOMContentLoaded', () => {
    loadRecents();

    $('#closeBtn').addEventListener('click', closeUI);
    $('#placeBtn').addEventListener('click', doPlace);
    $('#behaviorSel').addEventListener('change', onBehaviorChange);
    $('#scenarioBtn').addEventListener('click', () => switchPanel('scenario'));
    $('#refreshBtn').addEventListener('click', refreshPeds);

    $$('.rp-tab').forEach(t => t.addEventListener('click', () => switchPanel(t.dataset.panel)));

    $('#searchInput').addEventListener('input', (e) => { state.search = e.target.value; renderGrid(); });
    $('#scenarioSearch').addEventListener('input', (e) => { state.scenSearch = e.target.value; renderScenarios(); });
    $('#manageSearch').addEventListener('input', (e) => { state.manageSearch = e.target.value; renderPeds(); });

    $('#headingSlider').addEventListener('input', (e) => {
        $('#headingVal').textContent = e.target.value + '°';
    });

    $('#emoteBtn').addEventListener('click', () => {
        const custom = $('#customModel').value.trim();
        const model = custom || (state.selected && state.selected.model);
        if (!model) return;
        const label = $('#pedLabel').value.trim() || (custom ? custom : state.selected.label);
        post('openEmotes', {
            model, label,
            weapon: $('#weaponSel').value,
            invincible: $('#chkInvincible').checked,
            frozen: $('#chkFrozen').checked,
            groupName: $('#groupName').value.trim(),
        });
        hideApp();
    });

    $('#btnGroups').addEventListener('click', () => { post('openTool', { tool: 'groups' }); hideApp(); });
    $('#btnRadios').addEventListener('click', () => { post('openTool', { tool: 'radios' }); hideApp(); });
    $('#btnDetectors').addEventListener('click', () => { post('openTool', { tool: 'detectors' }); hideApp(); });
    $('#btnClassic').addEventListener('click', () => { post('openTool', { tool: 'classic' }); hideApp(); });

    $('#deleteAllBtn').addEventListener('click', () => {
        const btn = $('#deleteAllBtn');
        if (!btn.classList.contains('confirm')) {
            btn.classList.add('confirm');
            btn.textContent = 'Click again to wipe EVERY ped';
            setTimeout(() => { btn.classList.remove('confirm'); btn.innerHTML = '&#128465; Delete ALL Peds'; }, 3000);
            return;
        }
        post('deleteAllPeds', {});
        state.peds = [];
        renderPeds();
        btn.classList.remove('confirm');
        btn.innerHTML = '&#128465; Delete ALL Peds';
    });

    // clock
    const tick = () => {
        const d = new Date();
        $('#tbClock').textContent = d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    };
    tick();
    setInterval(tick, 15000);

    // Browser dev preview (never runs inside cef)
    if (!IN_GAME) {
        openApp({
            categories: [
                { label: '👮 Police', models: [
                    { label: 'LSPD Male', model: 's_m_y_cop_01' }, { label: 'LSPD Female', model: 's_f_y_cop_01' },
                    { label: 'Sheriff Male', model: 's_m_y_sheriff_01' }, { label: 'SWAT', model: 's_m_y_swat_01' },
                    { label: 'Ranger', model: 's_m_y_ranger_01' }, { label: 'FIB Suit', model: 's_m_m_fiboffice_01' },
                ]},
                { label: '💼 Business', models: [
                    { label: 'Business Suit M', model: 'a_m_y_business_01' }, { label: 'Business Woman', model: 'a_f_y_business_01' },
                    { label: 'Exec Male', model: 'a_m_m_bevhills_01' },
                ]},
                { label: '🎭 Gangs', models: [
                    { label: 'Ballas Male', model: 'g_m_y_ballaeast_01' }, { label: 'Lost MC', model: 'g_m_y_lost_01' },
                    { label: 'Vagos Male', model: 'g_m_y_mexgoon_01' },
                ]},
                { label: '🧜 Animals', models: [
                    { label: 'Police K9 (Retriever)', model: 'k9_retriever' },
                    { label: 'Rottweiler', model: 'a_c_rottweiler' }, { label: 'Cat', model: 'a_c_cat_01' },
                ]},
            ],
            scenarios: [
                { label: 'None (Idle)', scenario: '' },
                { label: 'Guard - Stand', scenario: 'WORLD_HUMAN_GUARD_STAND' },
                { label: 'Smoking', scenario: 'WORLD_HUMAN_SMOKING' },
                { label: 'Clipboard', scenario: 'WORLD_HUMAN_CLIPBOARD' },
                { label: 'Stripper - Pole Dance 1', scenario: '', animDict: 'mini@strip_club@pole_dance@pole_dance1', animName: 'pd_dance_01' },
            ],
            weapons: [
                { label: 'None', weapon: '' }, { label: 'Pistol', weapon: 'WEAPON_PISTOL' },
                { label: 'Carbine Rifle', weapon: 'WEAPON_CARBINERIFLE' },
            ],
            interactions: [
                { label: 'Conversation', scenario: 'WORLD_HUMAN_STAND_IMPATIENT' },
                { label: 'Argue', scenario: 'WORLD_HUMAN_HANG_OUT_STREET' },
            ],
            peds: [
                { id: 101, label: 'Front Door Guard', model: 's_m_m_security_01', behavior: 'idle', group_name: 'casino', x: 255.4, y: -1420.3, z: 28.4 },
                { id: 102, label: 'Patrol Cop', model: 's_m_y_cop_01', behavior: 'patrol', group_name: '', x: 300.1, y: -1500.9, z: 28.4 },
                { id: 103, label: 'Bartender', model: 's_f_y_bartender_01', behavior: 'bartender', group_name: 'unicorn', x: 120.0, y: -1300.0, z: 29.2 },
            ],
            coords: { x: 255.45, y: -1420.32, z: 28.45 },
            heading: 180,
        });
    }
});

/*  RR-drag v1 begin, managed block, edit _tools/rr-drag/rr-drag.js and re-run install-drag.ps1*/
/*
 * rr-drag, click-and-drag repositioning for FiveM NUI panels.
 *
 *   - Drag by a panel's header/top bar (anywhere that isn't a button or input)
 *   - Hold alt and drag from anywhere on the panel
 *   - alt + double-click a panel, or alt+R, to snap back to default
 *   - Position is remembered per resource in localStorage
 *
 * Self-contained, dependency-free, safe to run twice. Set window.RRDRAG_DISABLE
 * = true before this block to turn it off for a page, or window.RRDRAG_CONFIG =
 * {...} to override the tuning below.
 */
(function () {
    'use strict';

    if (window.__rrDrag || window.RRDRAG_DISABLE) return;

    /*  which resource are we? (NUI urls look like https://cfx-nui-rr-phone/...)*/
    var RES = 'nui';
    var m = /cfx-nui-([a-z0-9_\-\.]+)/i.exec(location.href || '');
    if (m) RES = m[1];
    else if (location.hostname) RES = location.hostname.replace(/^cfx-nui-/, '');
    var PFX = 'rrdrag:' + RES + ':';

    /*  per-resource tuning*/
    /* Phone/tablet frames grab by the side bezels only. Their top strip is
       Control Center / Notification Center swipe territory and the bottom holds
       the home indicator, a grab band over either one eats the tap. alt+drag
       still works from anywhere on the frame. */
    var OVERRIDES = {
        'rr-phone': { panel: '#phone', edge: 14, edges: 'lr', topStrip: 0, headers: false, keepX: 200, keepY: 260 },
        'rr-ipad':  { panel: '#ipad',  edge: 14, edges: 'lr', topStrip: 0, headers: false, keepX: 240, keepY: 240 }
    };

    var CFG = {
        panel: null,     // force the moved element (css selector); null = auto-detect
        edge: 0,         // px band around the panel's outer edge that drags (0 = off)
        edges: 'ltrb',   // which of those edges are live: l/t/r/b
        topStrip: 44,    // px from the panel's top that drags, on window-sized panels
        headers: true,   // let header/topbar elements act as the drag handle
        minW: 80,        // ignore anything smaller than this as a drag target
        minH: 40,
        keepX: 120,      // px of the panel that must stay on screen horizontally
        keepY: 36
    };
    var over = OVERRIDES[RES] || {}, k;
    for (k in over) CFG[k] = over[k];
    if (window.RRDRAG_CONFIG) for (k in window.RRDRAG_CONFIG) CFG[k] = window.RRDRAG_CONFIG[k];

    var HANDLE_SEL = 'header,.topbar,.top-bar,.titlebar,.title-bar,.header,.hdr,' +
        '.panel-header,.modal-header,.app-header,.win-header,.window-header,' +
        '.mac-titlebar,.mac-header,.safari-bar,.safari-top,.safari-chrome,' +
        '.browser-bar,.browser-chrome,.nav-top,.topnav,[data-drag-handle]';

    var INTERACTIVE_SEL = 'button,a,input,select,textarea,label,summary,option,' +
        '[contenteditable],[onclick],[role="button"],[role="tab"],' +
        '.btn,.button,.nav-btn,.tab,.tb-ic,.tb-search,.chip,.toggle,.switch';

    /*  helpers*/
    function vw() { return window.innerWidth || document.documentElement.clientWidth; }
    function vh() { return window.innerHeight || document.documentElement.clientHeight; }

    function esc(s) {
        if (window.CSS && CSS.escape) return CSS.escape(s);
        return String(s).replace(/([^\w-])/g, '\\$1');
    }

    /* Full-viewport wrappers are backdrops, not windows, never move those. */
    function isBackdrop(r) { return r.width >= vw() * 0.97 && r.height >= vh() * 0.97; }

    /* Outermost element under the pointer that looks like a floating window. */
    function findPanel(target) {
        if (CFG.panel) {
            /* Only claim the pointer when it is genuinely over that panel. A
               querySelector fallback here used to hand back the frame for
               clicks on the transparent page background, so every click in
               empty space dragged the phone. */
            return target.closest ? target.closest(CFG.panel) : null;
        }
        var chain = [], n = target;
        while (n && n.nodeType === 1 && n !== document.body && n !== document.documentElement) {
            chain.unshift(n);
            n = n.parentElement;
        }
        for (var i = 0; i < chain.length; i++) {
            var el = chain[i];
            if (el.hasAttribute('data-rrdrag-ignore')) continue;
            var cs = getComputedStyle(el);
            if (cs.display === 'contents' || cs.visibility === 'hidden') continue;
            var r = el.getBoundingClientRect();
            if (r.width < CFG.minW || r.height < CFG.minH) continue;
            if (isBackdrop(r)) continue;
            return el;
        }
        return null;
    }

    function interactive(t, panel) {
        if (!t || !t.closest) return false;
        var hit = t.closest(INTERACTIVE_SEL);
        return !!(hit && panel.contains(hit) && hit !== panel);
    }

    function edgeLive(c) { return CFG.edges.indexOf(c) >= 0; }

    function isHandle(e, panel) {
        var r = panel.getBoundingClientRect(), x = e.clientX, y = e.clientY;

        /* The band tests below are signed distances, so a point outside the
           panel scores as comfortably "within the edge", bail first. */
        if (x < r.left || x > r.right || y < r.top || y > r.bottom) return false;

        if (CFG.edge > 0 &&
            ((edgeLive('l') && x - r.left <= CFG.edge) ||
             (edgeLive('r') && r.right - x <= CFG.edge) ||
             (edgeLive('t') && y - r.top <= CFG.edge) ||
             (edgeLive('b') && r.bottom - y <= CFG.edge))) return true;

        if (CFG.headers && e.target.closest) {
            var h = e.target.closest(HANDLE_SEL);
            /* A real title bar spans the panel and sits at the top, this
               filters out the ".card-header" of some widget buried inside. */
            if (h && h !== panel && panel.contains(h)) {
                var hr = h.getBoundingClientRect();
                if (hr.width >= r.width * 0.55 && hr.top - r.top <= r.height * 0.28) return true;
            }
        }

        /* Bare top strip, but only on things big enough to read as a window
           keeps small overlays and meters from moving by accident. */
        if (CFG.topStrip > 0 && r.width >= 320 && r.height >= 260 && y - r.top <= CFG.topStrip) return true;

        return false;
    }

    /*  move state*/
    /* Two ways to shift a panel:
         inset, already positioned; nudge its left/top (leaves transform alone
                  which matters for frames that centre with translate(-50%,-50%))
         xform, in normal flow (flex-centred shells); append a translate3d
       `sc` is a calibration factor: CSS zoom or a scaled ancestor means one
       style pixel isn't one screen pixel, so we measure the first real move and
       correct. */
    function ensureState(el) {
        if (el.__rrd) return el.__rrd;
        var cs = getComputedStyle(el);
        var st = { mode: 'xform', ox: 0, oy: 0, sc: 1, base: '' };

        if (cs.position === 'fixed' || cs.position === 'absolute') {
            st.mode = 'inset';
            var r = el.getBoundingClientRect();
            st.bl = parseFloat(cs.left) || 0;
            st.bt = parseFloat(cs.top) || 0;
            el.style.left = st.bl + 'px';
            el.style.top = st.bt + 'px';
            el.style.right = 'auto';
            el.style.bottom = 'auto';
            /* If it had been stretched between opposing insets, dropping
               right/bottom collapses it, pin the size we measured instead. */
            var r2 = el.getBoundingClientRect();
            if (Math.abs(r2.width - r.width) > 2 || Math.abs(r2.height - r.height) > 2) {
                el.style.width = r.width + 'px';
                el.style.height = r.height + 'px';
            }
        } else {
            st.base = (cs.transform && cs.transform !== 'none') ? cs.transform : '';
        }

        el.__rrd = st;
        el.setAttribute('data-rrdrag-panel', '');
        return st;
    }

    function apply(el, st, ox, oy) {
        st.ox = ox;
        st.oy = oy;
        if (st.mode === 'inset') {
            el.style.left = (st.bl + ox * st.sc) + 'px';
            el.style.top = (st.bt + oy * st.sc) + 'px';
        } else {
            el.style.transform = (st.base ? st.base + ' ' : '') +
                'translate3d(' + (ox * st.sc) + 'px,' + (oy * st.sc) + 'px,0)';
        }
    }

    /* Keep a grabbable sliver on screen. Takes a requested delta, returns the
       allowed one. */
    function clamp(rect, dx, dy) {
        var left = rect.left + dx, top = rect.top + dy;
        var minLeft = -(rect.width - CFG.keepX), maxLeft = vw() - CFG.keepX;
        var minTop = 0, maxTop = vh() - CFG.keepY;
        if (left < minLeft) left = minLeft;
        if (left > maxLeft) left = maxLeft;
        if (top < minTop) top = minTop;
        if (top > maxTop) top = maxTop;
        return { dx: left - rect.left, dy: top - rect.top };
    }

    /*  persistence*/
    function selectorFor(el) {
        var parts = [], node = el;
        while (node && node.nodeType === 1 && node !== document.body) {
            if (node.id) { parts.unshift('#' + esc(node.id)); break; }
            var sel = node.tagName.toLowerCase();
            var cls = (node.getAttribute('class') || '').trim().split(/\s+/).filter(function (c) {
                /* skip state classes that flip at runtime, or the selector rots */
                return c && !/^(hidden|open|active|show|shown|visible|closed|collapsed)$/.test(c) &&
                    c.indexOf('rrdrag') !== 0;
            }).slice(0, 3);
            if (cls.length) sel += '.' + cls.map(esc).join('.');
            var p = node.parentElement;
            if (p) {
                var same = [], i;
                for (i = 0; i < p.children.length; i++) {
                    if (p.children[i].tagName === node.tagName) same.push(p.children[i]);
                }
                if (same.length > 1) sel += ':nth-of-type(' + (same.indexOf(node) + 1) + ')';
            }
            parts.unshift(sel);
            node = node.parentElement;
        }
        return parts.join('>');
    }

    var saved = {};
    try {
        for (var i = 0; i < localStorage.length; i++) {
            var key = localStorage.key(i);
            if (key && key.indexOf(PFX) === 0) {
                try { saved[key.slice(PFX.length)] = JSON.parse(localStorage.getItem(key)); } catch (_) {}
            }
        }
    } catch (_) {}

    function save(el, st) {
        var sel = el.__rrdSel || (el.__rrdSel = selectorFor(el));
        if (!sel) return;
        var v = { m: st.mode, ox: Math.round(st.ox), oy: Math.round(st.oy), sc: st.sc };
        saved[sel] = v;
        try { localStorage.setItem(PFX + sel, JSON.stringify(v)); } catch (_) {}
    }

    /* After any programmatic move, measure where the panel really ended up and
       walk it back on screen. Style pixels aren't always screen pixels (CSS
       zoom, scaled ancestors), so a clamp computed before apply() can still
       land the panel offscreen, this corrects against the measured rect and
       iterates, which converges even when the scale factor is unknown. */
    function settle(el, st) {
        /* Only inset-mode panels are safe to measure: the engine never puts a
           transform on them, so any non-identity transform is the page's own
           doing (the phone's slide-in, the notification peek that deliberately
           parks it below the screen edge) and the rect is a lie, correcting
           against it would bake the transient offset into the base position.
           Skip; the 600ms restore tick lands again once the element is at rest. */
        if (st.mode !== 'inset') return;
        try {
            if (el.getAnimations && el.getAnimations({ subtree: false }).some(function (a) { return a.playState === 'running'; })) return;
            var tf = getComputedStyle(el).transform;
            if (tf && tf !== 'none' && tf !== 'matrix(1, 0, 0, 1, 0, 0)') return;
        } catch (_) {}
        for (var i = 0; i < 4; i++) {
            var r = el.getBoundingClientRect();
            if (r.width < 1) return;                    // hidden, nothing to measure
            var c = clamp(r, 0, 0);
            if (Math.abs(c.dx) < 1 && Math.abs(c.dy) < 1) return;
            apply(el, st, st.ox + c.dx, st.oy + c.dy);
        }
    }

    /* Panels are often built or unhidden long after load, so keep looking. */
    function restore() {
        for (var sel in saved) {
            var v = saved[sel];
            if (!v || (!v.ox && !v.oy)) continue;
            var el;
            try { el = document.querySelector(sel); } catch (_) { delete saved[sel]; continue; }
            if (!el) continue;
            if (el.__rrd && el.__rrd.ox === v.ox && el.__rrd.oy === v.oy) {
                /* Already in the saved spot, but that spot may itself be bad
                   (saved during an animation, or the viewport shrank). Keep
                   nudging it back on screen; settle() no-ops when it's fine. */
                var rr = el.getBoundingClientRect();
                if (rr.width >= CFG.minW && rr.height >= CFG.minH) {
                    settle(el, el.__rrd);
                    if (Math.round(el.__rrd.ox) !== v.ox || Math.round(el.__rrd.oy) !== v.oy) save(el, el.__rrd);
                }
                continue;
            }
            var r = el.getBoundingClientRect();
            if (r.width < CFG.minW || r.height < CFG.minH) continue; // not laid out yet
            var st = ensureState(el);
            if (v.sc) st.sc = v.sc;
            el.__rrdSel = sel;
            var c = clamp(el.getBoundingClientRect(), v.ox - st.ox, v.oy - st.oy);
            apply(el, st, st.ox + c.dx, st.oy + c.dy);
            settle(el, st);
            /* If the clamp/settle moved it, persist the corrected spot so a
               bad saved position heals once instead of re-fighting every load. */
            if (Math.round(st.ox) !== v.ox || Math.round(st.oy) !== v.oy) save(el, st);
        }
    }

    /*  drag*/
    var drag = null, suppressClick = false;

    document.addEventListener('pointerdown', function (e) {
        if (e.button !== 0 || drag) return;
        var t = e.target;
        if (!t || !t.closest) return;

        var panel = findPanel(t);
        if (!panel) return;
        if (!e.altKey && (interactive(t, panel) || !isHandle(e, panel))) return;

        /* Armed, not grabbed. Nothing is captured or cancelled yet: a press
           that never moves has to reach the page untouched, or tapping a title
           bar, or the phone's home indicator, gets eaten. The grab commits on
           the first real movement, in pointermove. */
        drag = {
            el: panel, st: null, id: e.pointerId,
            sx: e.clientX, sy: e.clientY,
            ox: 0, oy: 0, r: null,
            moved: false, calibrated: false
        };
    }, true);

    document.addEventListener('pointermove', function (e) {
        if (!drag || e.pointerId !== drag.id) return;
        var dx = e.clientX - drag.sx, dy = e.clientY - drag.sy;
        if (!drag.moved && Math.abs(dx) + Math.abs(dy) < 3) return;

        if (!drag.moved) {
            drag.moved = true;
            /* Commit: from here the page must not see the gesture, so its own
               pointermove handlers (phone swipe zones) are cut off below. */
            drag.st = ensureState(drag.el);
            drag.ox = drag.st.ox;
            drag.oy = drag.st.oy;
            drag.r = drag.el.getBoundingClientRect();
            document.documentElement.classList.add('rrdrag-dragging');
            try { drag.el.setPointerCapture(drag.id); } catch (_) {}
        }

        var c = clamp(drag.r, dx, dy);
        apply(drag.el, drag.st, drag.ox + c.dx, drag.oy + c.dy);

        /* One-time check that a requested pixel actually moved a pixel. Either
           axis will do, a purely vertical drag on a zoomed panel (the phone)
           used to skip this and overshoot, parking the panel offscreen. */
        if (!drag.calibrated && (Math.abs(c.dx) >= 8 || Math.abs(c.dy) >= 8)) {
            drag.calibrated = true;
            var rNow = drag.el.getBoundingClientRect();
            var req = Math.abs(c.dx) >= Math.abs(c.dy) ? c.dx : c.dy;
            var actual = Math.abs(c.dx) >= Math.abs(c.dy)
                ? rNow.left - drag.r.left
                : rNow.top - drag.r.top;
            if (Math.abs(actual) > 1 && Math.abs(actual - req) > 1) {
                var s0 = drag.st.sc, s1 = s0 * (req / actual);
                /* Rebase the accumulated offset too, ox/oy were laid down in
                   style pixels at the old scale, and multiplying them by the
                   new sc would teleport the panel mid-drag. */
                drag.st.sc = s1;
                drag.ox = drag.ox * (s0 / s1);
                drag.oy = drag.oy * (s0 / s1);
                apply(drag.el, drag.st, drag.ox + c.dx, drag.oy + c.dy);
            }
        }
        e.preventDefault();
        e.stopPropagation();
    }, true);

    function endDrag(e) {
        if (!drag || (e && e.pointerId !== drag.id)) return;
        var d = drag;
        drag = null;
        document.documentElement.classList.remove('rrdrag-dragging');
        try { d.el.releasePointerCapture(d.id); } catch (_) {}
        if (d.moved) {
            /* The in-drag clamp works off the rect captured at grab time, so a
               scale mismatch can still let the panel slip offscreen, measure
               and pull it back before persisting. */
            settle(d.el, d.st);
            save(d.el, d.st);
            suppressClick = true;
            setTimeout(function () { suppressClick = false; }, 0);
        }
    }
    document.addEventListener('pointerup', endDrag, true);
    document.addEventListener('pointercancel', endDrag, true);

    document.addEventListener('click', function (e) {
        if (!suppressClick) return;
        e.preventDefault();
        e.stopPropagation();
    }, true);

    /*  reset*/
    function resetEl(el) {
        var st = el.__rrd;
        if (!st) return;
        if (st.mode === 'inset') {
            el.style.left = ''; el.style.top = '';
            el.style.right = ''; el.style.bottom = '';
            el.style.width = ''; el.style.height = '';
        } else {
            el.style.transform = '';
        }
        var sel = el.__rrdSel || selectorFor(el);
        delete saved[sel];
        try { localStorage.removeItem(PFX + sel); } catch (_) {}
        el.removeAttribute('data-rrdrag-panel');
        delete el.__rrd;
    }

    function resetAll() {
        var els = document.querySelectorAll('[data-rrdrag-panel]');
        for (var i = 0; i < els.length; i++) resetEl(els[i]);
        for (var sel in saved) {
            delete saved[sel];
            try { localStorage.removeItem(PFX + sel); } catch (_) {}
        }
    }

    document.addEventListener('dblclick', function (e) {
        if (!e.altKey) return;
        var p = findPanel(e.target);
        if (!p) return;
        resetEl(p);
        e.preventDefault();
        e.stopPropagation();
    }, true);

    document.addEventListener('keydown', function (e) {
        if (e.altKey && (e.key === 'r' || e.key === 'R')) resetAll();
    }, true);

    /*  keep panels on screen when the window changes size*/
    window.addEventListener('resize', function () {
        var els = document.querySelectorAll('[data-rrdrag-panel]');
        for (var i = 0; i < els.length; i++) {
            var el = els[i], st = el.__rrd;
            if (!st) continue;
            var c = clamp(el.getBoundingClientRect(), 0, 0);
            if (c.dx || c.dy) { apply(el, st, st.ox + c.dx, st.oy + c.dy); save(el, st); }
        }
    });

    /*  boot*/
    var style = document.createElement('style');
    style.textContent =
        'html.rrdrag-dragging,html.rrdrag-dragging *{cursor:grabbing!important;user-select:none!important}' +
        'html.rrdrag-dragging [data-rrdrag-panel]{transition:none!important}';
    (document.head || document.documentElement).appendChild(style);

    restore();
    setInterval(restore, 600);
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', restore);

    window.__rrDrag = { version: 1, resource: RES, cfg: CFG, reset: resetAll, restore: restore };
})();
/*  RR-drag v1 end*/
