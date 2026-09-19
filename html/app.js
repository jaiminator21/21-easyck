/* 21-easyck · interfaz NUI ------------------------------------------------
   Solo pinta y pide datos: todo lo que decide (permisos, que tablas existen,
   que se borra) lo resuelve el servidor.
------------------------------------------------------------------------- */

const RESOURCE = (typeof GetParentResourceName === 'function') ? GetParentResourceName() : 'easy-ck';

const HOLD_MS = 1800; // lo que hay que mantener pulsado para lanzar el CK

const state = {
    locale: {},
    requireReason: false,
    tab: 'online',
    players: [],
    characters: [],
    offset: 0,
    more: false,
    search: '',
    target: null,     // charId seleccionado
    preview: null,
    selection: new Set(),
    running: false,
};

const $ = (id) => document.getElementById(id);
const t = (key, fallback) => state.locale[key] || fallback || key;

function post(name, data) {
    return fetch(`https://${RESOURCE}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {}),
    }).catch(() => {});
}

function initials(name) {
    return (name || '?')
        .split(/\s+/)
        .filter(Boolean)
        .slice(0, 2)
        .map((word) => word[0].toUpperCase())
        .join('') || '?';
}

function escapeHtml(value) {
    return String(value == null ? '' : value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
}

/* ── Textos ─────────────────────────────────────────────────────────── */

function applyLocale() {
    $('t-title').textContent = t('title', 'Character Kill');
    $('t-subtitle').textContent = t('subtitle', '');
    $('t-tab-online').textContent = t('tab_online', 'En línea');
    $('t-tab-all').textContent = t('tab_all', 'Todos');
    $('t-empty-title').textContent = t('empty_title', '');
    $('t-empty-text').textContent = t('empty_text', '');
    $('t-data').textContent = t('data', '');
    $('t-reason').textContent = t('reason', '') + (state.requireReason ? ' · ' + t('reason_req', '') : '');
    $('t-total').textContent = t('total', '');
    $('select-all').textContent = t('select_all', '');
    $('select-none').textContent = t('select_none', '');
    $('kill-label').textContent = t('kill', '');
    $('warning').textContent = t('irreversible', '');
    $('more').textContent = t('load_more', '');
    $('reason').placeholder = t('reason_ph', '');
    $('close').title = t('close', 'ESC');
    updateSearchPlaceholder();
}

function updateSearchPlaceholder() {
    $('search').placeholder = state.tab === 'online' ? t('search', '') : t('search_all', '');
}

/* ── Lista lateral ──────────────────────────────────────────────────── */

function renderList() {
    const list = $('list');
    list.innerHTML = '';

    const entries = state.tab === 'online' ? onlineEntries() : characterEntries();

    if (!entries.length) {
        const empty = document.createElement('div');
        empty.className = 'list-empty';
        empty.textContent = state.tab === 'online'
            ? t('no_players', '')
            : (state.search ? t('no_results', '') : t('offline_hint', ''));
        list.appendChild(empty);
    }

    for (const entry of entries) {
        const el = document.createElement('div');
        el.className = 'entry' + (entry.charId && entry.charId === state.target ? ' active' : '');
        el.innerHTML = `
            <div class="avatar">${escapeHtml(initials(entry.name))}</div>
            <div class="entry-info">
                <div class="entry-name">${escapeHtml(entry.name)}</div>
                <div class="entry-meta">${escapeHtml(entry.meta)}</div>
            </div>
            <span class="dot${entry.online ? ' on' : ''}"></span>`;

        if (entry.target) {
            el.addEventListener('click', () => selectTarget(entry.target, entry.charId));
        }
        list.appendChild(el);
    }

    $('more').classList.toggle('hidden', state.tab !== 'all' || !state.more);
}

function onlineEntries() {
    const search = state.search.toLowerCase();
    return state.players
        .filter((player) => {
            if (!search) return true;
            return [player.name, player.steam, player.charId, String(player.id)]
                .some((value) => value && String(value).toLowerCase().includes(search));
        })
        .map((player) => ({
            name: player.name || player.steam || ('ID ' + player.id),
            meta: `ID ${player.id} · ${player.charId || t('no_char', '')}${player.job ? ' · ' + player.job : ''}`,
            online: true,
            charId: player.charId || null,
            target: player.charId ? ('cid:' + player.charId) : String(player.id),
        }));
}

function characterEntries() {
    return state.characters.map((character) => ({
        name: character.name,
        meta: `${character.charId}${character.sub ? ' · ' + character.sub : ''}`,
        online: !!character.online,
        charId: character.charId,
        target: 'cid:' + character.charId,
    }));
}

/* ── Vista previa ───────────────────────────────────────────────────── */

function selectTarget(target, charId) {
    state.target = charId || null;
    state.preview = null;
    renderList();
    $('empty').classList.remove('hidden');
    $('t-empty-title').textContent = t('loading', '');
    $('t-empty-text').textContent = '';
    $('preview').classList.add('hidden');
    $('actions').classList.add('hidden');
    $('warning').classList.add('hidden');
    post('preview', { target });
}

function renderPreview() {
    const preview = state.preview;
    if (!preview) return;

    state.target = preview.charId;
    state.selection = new Set(preview.tables.filter((tbl) => tbl.selected || tbl.locked).map((tbl) => tbl.table));

    $('empty').classList.add('hidden');
    $('preview').classList.remove('hidden');
    $('actions').classList.remove('hidden');
    $('warning').classList.remove('hidden');

    $('char-name').textContent = preview.name;
    $('char-id').textContent = preview.charId;

    const status = $('char-status');
    status.textContent = preview.online ? `${t('status_online', '')} · ID ${preview.online}` : t('status_offline', '');
    status.className = 'chip' + (preview.online ? ' on' : '');

    const fields = $('char-fields');
    fields.innerHTML = '';
    for (const field of preview.summary || []) {
        const el = document.createElement('div');
        el.innerHTML = `<div class="field-label">${escapeHtml(t(field.key, field.key))}</div>
                        <div class="field-value">${escapeHtml(field.value)}</div>`;
        fields.appendChild(el);
    }
    fields.classList.toggle('hidden', !(preview.summary || []).length);

    renderTables();
    renderList();
}

function renderTables() {
    const container = $('tables');
    container.innerHTML = '';

    for (const table of state.preview.tables) {
        const selected = state.selection.has(table.table);
        const row = document.createElement('div');
        row.className = 'table-row' + (selected ? '' : ' off');

        const rowsLabel = `${table.count} ${table.count === 1 ? t('row', '') : t('rows', '')}`;
        const countClass = table.count === 0 ? '' : (table.mode === 'update' ? ' soft' : ' has');
        const sub = table.locked
            ? `${table.table} · ${t('locked', '')}`
            : (table.mode === 'update' ? `${table.table} · ${t('soft_delete', '')}` : table.table);

        row.innerHTML = `
            <div class="table-main">
                <div class="check${selected ? ' on' : ''}${table.locked ? ' locked' : ''}">✓</div>
                <div class="table-name">
                    <div class="table-label">${escapeHtml(table.label)}</div>
                    <div class="table-sub">${escapeHtml(sub)}</div>
                </div>
                <span class="count${countClass}">${escapeHtml(rowsLabel)}</span>
                <span class="caret">${table.count ? '›' : ''}</span>
            </div>
            <div class="rows">${rowsHtml(table)}</div>`;

        const check = row.querySelector('.check');
        check.addEventListener('click', (event) => {
            event.stopPropagation();
            if (table.locked) return;
            if (state.selection.has(table.table)) {
                state.selection.delete(table.table);
            } else {
                state.selection.add(table.table);
            }
            renderTables();
        });

        if (table.count) {
            row.querySelector('.table-main').addEventListener('click', () => row.classList.toggle('open'));
        }

        container.appendChild(row);
    }

    updateTotal();
}

function rowsHtml(table) {
    if (!table.rows.length) {
        return `<div class="rows-empty">${escapeHtml(t('empty_table', ''))}</div>`;
    }

    const head = table.columns.map((column) => `<th>${escapeHtml(column)}</th>`).join('');
    const body = table.rows
        .map((cells) => `<tr>${cells.map((cell) => `<td title="${escapeHtml(cell)}">${escapeHtml(cell)}</td>`).join('')}</tr>`)
        .join('');

    const hidden = table.count - table.rows.length;
    const more = hidden > 0
        ? `<div class="rows-more">${escapeHtml((t('more_rows', 'y %s filas más')).replace('%s', hidden))}</div>`
        : '';

    return `<table><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table>${more}`;
}

function updateTotal() {
    const total = state.preview.tables
        .filter((table) => state.selection.has(table.table))
        .reduce((sum, table) => sum + table.count, 0);
    $('total').textContent = total;
}

/* ── Ejecutar ───────────────────────────────────────────────────────── */

let holdStart = null;
let holdFrame = null;

function stopHold() {
    holdStart = null;
    if (holdFrame) cancelAnimationFrame(holdFrame);
    holdFrame = null;
    $('kill-fill').style.width = '0';
    $('kill').classList.remove('holding');
    if (!state.running) $('kill-label').textContent = t('kill', '');
}

function tickHold() {
    if (holdStart === null) return;
    const progress = Math.min((performance.now() - holdStart) / HOLD_MS, 1);
    $('kill-fill').style.width = (progress * 100) + '%';
    if (progress >= 1) {
        stopHold();
        execute();
        return;
    }
    holdFrame = requestAnimationFrame(tickHold);
}

function startHold() {
    if (state.running || !state.preview) return;

    if (!state.selection.size) {
        return toast(t('nothing_selected', ''), false);
    }
    if (state.requireReason && !$('reason').value.trim()) {
        return toast(t('reason_req', ''), false);
    }

    $('kill').classList.add('holding');
    holdStart = performance.now();
    holdFrame = requestAnimationFrame(tickHold);
}

function execute() {
    state.running = true;
    $('kill').disabled = true;
    $('kill-label').textContent = t('killing', '');

    post('execute', {
        charId: state.preview.charId,
        reason: $('reason').value.trim(),
        tables: Array.from(state.selection),
    });
}

function toast(message, ok) {
    const el = $('toast');
    el.textContent = message;
    el.className = 'toast ' + (ok ? 'ok' : 'err');
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => el.classList.add('hidden'), 6000);
}

/* ── Eventos de la interfaz ─────────────────────────────────────────── */

$('close').addEventListener('click', close);

document.addEventListener('keyup', (event) => {
    if (event.key === 'Escape') close();
});

$('search').addEventListener('input', (event) => {
    state.search = event.target.value;
    if (state.tab === 'online') {
        renderList();
    } else {
        clearTimeout($('search').timer);
        $('search').timer = setTimeout(() => {
            state.offset = 0;
            post('list', { search: state.search, offset: 0 });
        }, 250);
    }
});

$('refresh').addEventListener('click', () => {
    if (state.tab === 'online') {
        post('players');
    } else {
        state.offset = 0;
        post('list', { search: state.search, offset: 0 });
    }
});

$('more').addEventListener('click', () => {
    state.offset += 30;
    post('list', { search: state.search, offset: state.offset });
});

for (const tab of document.querySelectorAll('.tab')) {
    tab.addEventListener('click', () => {
        state.tab = tab.dataset.tab;
        state.search = '';
        $('search').value = '';
        for (const other of document.querySelectorAll('.tab')) {
            other.classList.toggle('active', other === tab);
        }
        updateSearchPlaceholder();
        if (state.tab === 'all') {
            state.offset = 0;
            state.characters = [];
            post('list', { search: '', offset: 0 });
        }
        renderList();
    });
}

$('select-all').addEventListener('click', () => {
    for (const table of state.preview.tables) state.selection.add(table.table);
    renderTables();
});

$('select-none').addEventListener('click', () => {
    state.selection = new Set(state.preview.tables.filter((table) => table.locked).map((table) => table.table));
    renderTables();
});

const kill = $('kill');
kill.addEventListener('mousedown', startHold);
kill.addEventListener('mouseup', stopHold);
kill.addEventListener('mouseleave', stopHold);

function close() {
    stopHold();
    document.getElementById('app').classList.add('hidden');
    post('close');
}

/* ── Mensajes del cliente ───────────────────────────────────────────── */

window.addEventListener('message', (event) => {
    const { action, data } = event.data || {};

    if (action === 'open') {
        state.locale = data.locale || {};
        state.requireReason = !!data.requireReason;
        state.players = data.players || [];
        state.characters = [];
        state.tab = 'online';
        state.search = '';
        state.target = null;
        state.preview = null;
        state.running = false;

        applyLocale();
        $('framework').textContent = data.framework || '';
        $('search').value = '';
        $('reason').value = '';
        $('kill').disabled = false;
        $('toast').classList.add('hidden');
        $('empty').classList.remove('hidden');
        $('t-empty-title').textContent = t('empty_title', '');
        $('t-empty-text').textContent = t('empty_text', '');
        $('preview').classList.add('hidden');
        $('actions').classList.add('hidden');
        $('warning').classList.add('hidden');
        for (const tab of document.querySelectorAll('.tab')) {
            tab.classList.toggle('active', tab.dataset.tab === 'online');
        }
        renderList();
        $('app').classList.remove('hidden');
        return;
    }

    if (action === 'close') {
        stopHold();
        $('app').classList.add('hidden');
        return;
    }

    if (action === 'players') {
        state.players = data || [];
        if (state.tab === 'online') renderList();
        return;
    }

    if (action === 'list') {
        if (data.offset > 0) {
            state.characters = state.characters.concat(data.characters || []);
        } else {
            state.characters = data.characters || [];
        }
        state.more = !!data.more;
        state.offset = data.offset || 0;
        if (state.tab === 'all') renderList();
        return;
    }

    if (action === 'preview') {
        if (data.error) {
            $('t-empty-title').textContent = t('empty_title', '');
            $('t-empty-text').textContent = data.error;
            return toast(data.error, false);
        }
        state.preview = data;
        renderPreview();
        return;
    }

    if (action === 'result') {
        state.running = false;
        $('kill').disabled = false;
        $('kill-label').textContent = t('kill', '');
        toast(data.message, data.ok);

        if (data.ok) {
            state.preview = null;
            state.target = null;
            $('preview').classList.add('hidden');
            $('actions').classList.add('hidden');
            $('warning').classList.add('hidden');
            $('empty').classList.remove('hidden');
            $('t-empty-title').textContent = t('empty_title', '');
            $('t-empty-text').textContent = t('empty_text', '');
            $('reason').value = '';
            post('players');
            if (state.tab === 'all') post('list', { search: state.search, offset: 0 });
        }
    }
});
