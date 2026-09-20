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

    // Por cada tabla: 'all' (entera), 'rows' (solo las filas marcadas) o 'none'.
    state.selection = new Map();
    for (const table of preview.tables) {
        state.selection.set(table.table, {
            mode: (table.selected || table.locked) ? 'all' : 'none',
            ids: new Set(),
        });
    }

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

function tableState(name) {
    if (!state.selection.has(name)) state.selection.set(name, { mode: 'none', ids: new Set() });
    return state.selection.get(name);
}

function selectedCount(table) {
    const selection = tableState(table.table);
    if (selection.mode === 'all') return table.count;
    if (selection.mode === 'rows') return selection.ids.size;
    return 0;
}

function renderTables() {
    const container = $('tables');
    container.innerHTML = '';

    for (const table of state.preview.tables) {
        container.appendChild(renderTable(table));
    }

    updateTotal();
}

function renderTable(table) {
    const selection = tableState(table.table);
    const selected = selectedCount(table);
    const row = document.createElement('div');
    row.className = 'table-row' + (selected === 0 ? ' off' : '') + (table.open ? ' open' : '');

    const countText = selection.mode === 'rows'
        ? t('rows_selected', '%s de %s filas').replace('%s', selected).replace('%s', table.count)
        : `${table.count} ${table.count === 1 ? t('row', '') : t('rows', '')}`;
    const countClass = selected === 0 ? '' : (table.mode === 'update' ? ' soft' : ' has');

    const notes = [table.table];
    if (table.discovered && (table.links || []).length) notes.push(table.links.join(' / '));
    if (table.locked) notes.push(t('locked', ''));
    if (table.discovered) notes.push(t('detected', ''));
    if (table.mode === 'update') notes.push(t('soft_delete', ''));
    if (!table.key && !table.locked) notes.push(t('no_key', ''));

    row.innerHTML = `
        <div class="table-main">
            <div class="check${selection.mode === 'all' ? ' on' : ''}${selection.mode === 'rows' ? ' partial' : ''}${table.locked ? ' locked' : ''}">${selection.mode === 'rows' ? '–' : '✓'}</div>
            <div class="table-name">
                <div class="table-label">${escapeHtml(table.label)}</div>
                <div class="table-sub">${escapeHtml(notes.join(' · '))}</div>
            </div>
            <span class="count${countClass}">${escapeHtml(countText)}</span>
            <span class="caret">${table.count ? '›' : ''}</span>
        </div>
        <div class="rows">${rowsHtml(table)}</div>`;

    row.querySelector('.check').addEventListener('click', (event) => {
        event.stopPropagation();
        if (table.locked) return;
        selection.mode = selection.mode === 'all' ? 'none' : 'all';
        selection.ids.clear();
        replaceTable(row, table);
    });

    if (table.count) {
        row.querySelector('.table-main').addEventListener('click', () => {
            table.open = !table.open;
            row.classList.toggle('open', table.open);
        });
    }

    for (const box of row.querySelectorAll('.row-check[data-id]')) {
        box.addEventListener('click', (event) => {
            event.stopPropagation();
            toggleRow(table, box.dataset.id);
            replaceTable(row, table);
        });
    }

    const loader = row.querySelector('.load-rows');
    if (loader) {
        loader.addEventListener('click', (event) => {
            event.stopPropagation();
            loader.textContent = t('loading_rows', '');
            post('rows', { table: table.table, charId: state.preview.charId });
        });
    }

    return row;
}

// Repinta solo la tabla tocada: con cientos de filas abiertas repintarlo todo se nota.
function replaceTable(node, table) {
    const fresh = renderTable(table);
    node.replaceWith(fresh);
    updateTotal();
}

function toggleRow(table, id) {
    const selection = tableState(table.table);

    if (selection.mode === 'all') {
        // Al desmarcar una fila de una tabla entera, se pasa a "solo estas filas":
        // las que no estén cargadas dejan de estar seleccionadas, y el contador lo enseña.
        selection.mode = 'rows';
        selection.ids = new Set(table.rows.map((row) => row.id).filter(Boolean));
    }

    if (selection.ids.has(id)) {
        selection.ids.delete(id);
    } else {
        selection.ids.add(id);
        selection.mode = 'rows';
    }

    if (selection.ids.size === 0) selection.mode = 'none';
    if (selection.mode === 'rows' && selection.ids.size === table.count) selection.mode = 'all';
}

function rowsHtml(table) {
    if (!table.rows.length) {
        return `<div class="rows-empty">${escapeHtml(t('empty_table', ''))}</div>`;
    }

    const selection = tableState(table.table);
    const selectable = !!table.key && !table.locked;

    const head = `<tr><th class="pick"></th>${table.columns.map((column) => `<th>${escapeHtml(column)}</th>`).join('')}</tr>`;

    const body = table.rows.map((row) => {
        const checked = selection.mode === 'all' || (selection.mode === 'rows' && selection.ids.has(row.id));
        const box = selectable && row.id
            ? `<div class="row-check${checked ? ' on' : ''}" data-id="${escapeHtml(row.id)}">✓</div>`
            : `<div class="row-check disabled">${checked ? '✓' : ''}</div>`;
        const cells = row.cells.map((cell) => `<td title="${escapeHtml(cell)}">${escapeHtml(cell)}</td>`).join('');
        return `<tr class="${checked ? '' : 'unchecked'}"><td class="pick">${box}</td>${cells}</tr>`;
    }).join('');

    const hidden = table.count - table.rows.length;
    const footer = hidden > 0
        ? `<div class="rows-more">
               ${escapeHtml(t('showing', 'mostrando %s de %s').replace('%s', table.rows.length).replace('%s', table.count))}
               <button class="ghost-btn sm load-rows">${escapeHtml(t('load_rows', ''))}</button>
           </div>`
        : '';

    return `<table><thead>${head}</thead><tbody>${body}</tbody></table>${footer}`;
}

function updateTotal() {
    const total = state.preview.tables.reduce((sum, table) => sum + selectedCount(table), 0);
    $('total').textContent = total;
}

function anySelected() {
    return state.preview.tables.some((table) => selectedCount(table) > 0);
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

    if (!anySelected()) {
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

    const tables = [];
    for (const table of state.preview.tables) {
        const selection = tableState(table.table);
        if (selection.mode === 'all') {
            tables.push({ table: table.table });
        } else if (selection.mode === 'rows' && selection.ids.size) {
            tables.push({ table: table.table, ids: Array.from(selection.ids) });
        }
    }

    post('execute', {
        charId: state.preview.charId,
        reason: $('reason').value.trim(),
        tables,
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
    for (const table of state.preview.tables) {
        state.selection.set(table.table, { mode: 'all', ids: new Set() });
    }
    renderTables();
});

$('select-none').addEventListener('click', () => {
    for (const table of state.preview.tables) {
        state.selection.set(table.table, { mode: table.locked ? 'all' : 'none', ids: new Set() });
    }
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

    if (action === 'rows') {
        const table = (state.preview && state.preview.tables || []).find((entry) => entry.table === data.table);
        if (!table) return;
        table.columns = data.columns || table.columns;
        table.rows = data.rows || [];
        table.key = data.key || table.key;
        table.open = true;
        renderTables();
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
