/**
 * ADR (Architecture Decision Records) module
 * Grouped list with inline expand, sidebar counts, and create/edit modal.
 */

// ── State ─────────────────────────────────────────────────────────────────────

let _adrs          = [];
let _expandedAdrId = null;
let _editingAdrId  = null;   // null = create mode

// ── Init ──────────────────────────────────────────────────────────────────────

async function initAdrs() {
    _bindCreateButton();
    _bindModal();
    _bindListDelegation();
    await _loadAdrs();
}

function _bindListDelegation() {
    const container = document.getElementById('adr-list');
    if (!container) return;

    container.addEventListener('click', (e) => {
        const row = e.target.closest('.adr-row');
        if (!row) return;
        const adrId = row.dataset.adrId;
        if (!adrId || !isValidAdrId(adrId)) return;

        const actionEl = e.target.closest('[data-action]');
        if (!actionEl) return;
        const action = actionEl.dataset.action;

        if (action === 'accept') {
            e.stopPropagation();
            adrAccept(adrId);
        } else if (action === 'deprecate') {
            e.stopPropagation();
            adrDeprecate(adrId);
        } else if (action === 'edit') {
            e.stopPropagation();
            _openEditModal(adrId);
        } else if (action === 'toggle') {
            toggleAdrExpand(adrId);
        }
    });
}

// ── Data loading ──────────────────────────────────────────────────────────────

async function _loadAdrs() {
    try {
        const res  = await fetch(`${API_BASE}/api/adrs`);
        const data = await res.json();
        _adrs = data.adrs || [];
        _renderList();
        _updateAdrSidebar();
    } catch (e) {
        console.error('Failed to load ADRs', e);
    }
}

// ── List rendering ────────────────────────────────────────────────────────────

function _renderList() {
    const container = document.getElementById('adr-list');
    if (!container) return;

    if (!_adrs || _adrs.length === 0) {
        container.innerHTML = '<div class="empty-state">No ADRs yet. Create one or run the interview workflow to generate them automatically.</div>';
        return;
    }

    const statusOrder  = ['proposed', 'accepted', 'deprecated', 'superseded'];
    const statusLabels = { proposed: 'Proposed', accepted: 'Accepted', deprecated: 'Deprecated', superseded: 'Superseded' };

    const groups = {};
    for (const adr of _adrs) {
        const s = adr.status || 'proposed';
        if (!groups[s]) groups[s] = [];
        groups[s].push(adr);
    }

    let html = '';
    for (const status of statusOrder) {
        if (!groups[status] || groups[status].length === 0) continue;

        html += `<div class="adr-group">`;
        html += `<div class="adr-group-header">${statusLabels[status] || status}</div>`;

        for (const adr of groups[status]) {
            const isExpanded  = _expandedAdrId === adr.id;
            const statusClass = `adr-status-${adr.status}`;
            const date        = _friendlyDate(adr.updated_at ?? adr.created_at);
            const source      = adr.source ? escapeHtml(adr.source) : '';

            html += `<div class="adr-row${isExpanded ? ' expanded' : ''}" data-adr-id="${escapeAttr(adr.id)}">`;

            // ── Collapsed row (always visible) ────────────────────────
            html += `<div class="adr-row-main" data-action="toggle">`;
            html += `  <span class="adr-row-id">${escapeHtml(adr.id ?? '')}</span>`;
            html += `  <span class="adr-status-badge ${statusClass}">${escapeHtml(adr.status)}</span>`;
            html += `  <span class="adr-row-title">${escapeHtml(adr.title ?? '')}</span>`;
            if (source) {
                html += `  <span class="adr-row-source">${source}</span>`;
            }
            html += `  <span class="adr-row-date">${date}</span>`;
            html += `  <div class="adr-row-actions">`;
            if (adr.status === 'proposed') {
                html += `<button class="process-action-btn primary" data-action="accept">Accept</button>`;
            }
            if (adr.status === 'accepted') {
                html += `<button class="process-action-btn danger" data-action="deprecate">Deprecate</button>`;
            }
            html += `    <button class="process-action-btn" data-action="edit">Edit</button>`;
            html += `  </div>`;
            html += `</div>`; // .adr-row-main

            // ── Expanded detail (inline) ───────────────────────────────
            if (isExpanded) {
                const sections = adr.sections || {};
                const sectionOrder = ['Context', 'Decision', 'Rationale', 'Consequences', 'Alternatives Considered'];

                html += `<div class="adr-detail">`;

                // Meta bar
                const metaParts = [];
                if (adr.source)      metaParts.push(`<span class="adr-meta-item"><b>Source:</b> ${escapeHtml(adr.source)}</span>`);
                if (adr.created_at)  metaParts.push(`<span class="adr-meta-item"><b>Created:</b> ${_friendlyDate(adr.created_at)}</span>`);
                if (adr.related_adrs && adr.related_adrs !== '[]') {
                    metaParts.push(`<span class="adr-meta-item"><b>Related:</b> ${escapeHtml(adr.related_adrs)}</span>`);
                }
                if (adr.superseded_by && adr.superseded_by !== 'null') {
                    metaParts.push(`<span class="adr-meta-item"><b>Superseded by:</b> ${escapeHtml(adr.superseded_by)}</span>`);
                }
                if (metaParts.length > 0) {
                    html += `<div class="adr-detail-meta">${metaParts.join('')}</div>`;
                }

                // Sections
                for (const sec of sectionOrder) {
                    if (sections[sec]) {
                        html += `<div class="adr-section">`;
                        html += `  <div class="adr-section-title">${sec}</div>`;
                        html += `  <div class="adr-section-body">${escapeHtml(sections[sec])}</div>`;
                        html += `</div>`;
                    }
                }

                html += `</div>`; // .adr-detail
            }

            html += `</div>`; // .adr-row
        }

        html += `</div>`; // .adr-group
    }

    container.innerHTML = html;
}

function _friendlyDate(iso) {
    if (!iso) return '';
    try {
        return new Date(iso).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
    } catch { return iso; }
}

// ── Expand / collapse ─────────────────────────────────────────────────────────

async function toggleAdrExpand(adrId) {
    if (_expandedAdrId === adrId) {
        _expandedAdrId = null;
        _renderList();
        return;
    }

    // Fetch detail (sections) on first expand if not yet cached
    const existing = _adrs.find(a => a.id === adrId);
    if (existing && !existing.sections) {
        try {
            const res  = await fetch(`${API_BASE}/api/adrs/${adrId}`);
            const data = await res.json();
            if (data.success !== false) {
                Object.assign(existing, {
                    sections:      data.sections,
                    related_adrs:  data.related_adrs,
                    superseded_by: data.superseded_by,
                    source:        data.source,
                    created_at:    data.created_at
                });
            }
        } catch (e) { /* render without sections */ }
    }

    _expandedAdrId = adrId;
    _renderList();
}

// ── Sidebar counts ────────────────────────────────────────────────────────────

function _updateAdrSidebar() {
    const counts = { proposed: 0, accepted: 0, deprecated: 0, superseded: 0 };
    for (const adr of _adrs) {
        if (counts[adr.status] !== undefined) counts[adr.status]++;
    }
    const set = (id, val) => { const el = document.getElementById(id); if (el) el.textContent = val; };
    set('adr-count-proposed',   counts.proposed);
    set('adr-count-accepted',   counts.accepted);
    set('adr-count-deprecated', counts.deprecated);
    set('adr-count-superseded', counts.superseded);
    set('adr-count-total',      _adrs.length);
}

// ── Status transitions ────────────────────────────────────────────────────────

async function adrAccept(adrId) {
    await _transitionStatus(adrId, 'accepted');
}

async function adrDeprecate(adrId) {
    const reason = prompt('Reason for deprecation (optional):') ?? '';
    await _transitionStatus(adrId, 'deprecated', null, reason);
}

async function _transitionStatus(adrId, newStatus, supersededBy, reason) {
    try {
        const res = await fetch(`${API_BASE}/api/adrs/${adrId}/status`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-Dotbot-Request': '1' },
            body: JSON.stringify({ status: newStatus, superseded_by: supersededBy, reason })
        });
        const data = await res.json();
        if (data.success) {
            showToast(data.message || `ADR ${newStatus}`, 'success');
            _expandedAdrId = null;
            await _loadAdrs();
        } else {
            showToast(data.error || 'Transition failed', 'error');
        }
    } catch (e) {
        showToast('Request failed', 'error');
    }
}

// ── Create button ─────────────────────────────────────────────────────────────

function _bindCreateButton() {
    const btn = document.getElementById('adr-create-btn');
    if (btn) btn.addEventListener('click', _openCreateModal);
}

// ── Modal ─────────────────────────────────────────────────────────────────────

function _bindModal() {
    const cancelBtn = document.getElementById('adr-modal-cancel');
    const closeBtn  = document.getElementById('adr-modal-close');
    const saveBtn   = document.getElementById('adr-modal-save');
    if (cancelBtn) cancelBtn.addEventListener('click', _closeModal);
    if (closeBtn)  closeBtn.addEventListener('click', _closeModal);
    if (saveBtn)   saveBtn.addEventListener('click', _saveAdr);

    const overlay = document.getElementById('adr-modal-overlay');
    if (overlay) overlay.addEventListener('click', (e) => { if (e.target === overlay) _closeModal(); });
}

function _openCreateModal() {
    _editingAdrId = null;
    document.getElementById('adr-modal-title').textContent = 'New ADR';
    _clearForm();
    const statusEl = document.getElementById('adr-form-status');
    if (statusEl) statusEl.disabled = false;
    document.getElementById('adr-modal-overlay').classList.add('visible');
}

async function _openEditModal(adrId) {
    _editingAdrId = adrId;
    document.getElementById('adr-modal-title').textContent = `Edit ${adrId}`;
    try {
        const res  = await fetch(`${API_BASE}/api/adrs/${adrId}`);
        const data = await res.json();
        if (!data.success) { showToast(data.error || 'Failed to load ADR', 'error'); return; }

        document.getElementById('adr-form-title').value        = data.title ?? '';
        const statusEl = document.getElementById('adr-form-status');
        statusEl.value    = data.status ?? 'proposed';
        statusEl.disabled = true;  // Status changes go through dedicated transition buttons
        document.getElementById('adr-form-context').value      = data.sections?.['Context'] ?? '';
        document.getElementById('adr-form-decision').value     = data.sections?.['Decision'] ?? '';
        document.getElementById('adr-form-rationale').value    = data.sections?.['Rationale'] ?? '';
        document.getElementById('adr-form-consequences').value = data.sections?.['Consequences'] ?? '';
        document.getElementById('adr-form-alternatives').value = data.sections?.['Alternatives Considered'] ?? '';

        document.getElementById('adr-modal-overlay').classList.add('visible');
    } catch (e) {
        showToast('Failed to load ADR for editing', 'error');
    }
}

function _closeModal() {
    document.getElementById('adr-modal-overlay').classList.remove('visible');
    _editingAdrId = null;
}

function _clearForm() {
    ['title', 'context', 'decision', 'rationale', 'consequences', 'alternatives'].forEach(f => {
        const el = document.getElementById(`adr-form-${f}`);
        if (el) el.value = '';
    });
    const statusEl = document.getElementById('adr-form-status');
    if (statusEl) statusEl.value = 'proposed';
}

async function _saveAdr() {
    const title        = document.getElementById('adr-form-title')?.value?.trim();
    const status       = document.getElementById('adr-form-status')?.value;
    const context      = document.getElementById('adr-form-context')?.value?.trim();
    const decision     = document.getElementById('adr-form-decision')?.value?.trim();
    const rationale    = document.getElementById('adr-form-rationale')?.value?.trim();
    const consequences = document.getElementById('adr-form-consequences')?.value?.trim();
    const alternatives = document.getElementById('adr-form-alternatives')?.value?.trim();

    if (!title || !context || !decision) {
        showToast('Title, Context, and Decision are required', 'error');
        return;
    }

    // Status is only sent on create; edits use dedicated transition buttons
    const payload = _editingAdrId
        ? { title, context, decision, rationale, consequences, alternatives_considered: alternatives }
        : { title, status, context, decision, rationale, consequences, alternatives_considered: alternatives, source: 'manual' };

    try {
        let res;
        if (_editingAdrId) {
            res = await fetch(`${API_BASE}/api/adrs/${_editingAdrId}`, {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json', 'X-Dotbot-Request': '1' },
                body: JSON.stringify(payload)
            });
        } else {
            res = await fetch(`${API_BASE}/api/adrs`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'X-Dotbot-Request': '1' },
                body: JSON.stringify(payload)
            });
        }
        const data = await res.json();
        if (data.success) {
            showToast(data.message || 'ADR saved', 'success');
            _closeModal();
            await _loadAdrs();
            if (data.adr_id) {
                _expandedAdrId = data.adr_id;
                _renderList();
            }
        } else {
            showToast(data.error || 'Save failed', 'error');
        }
    } catch (e) {
        showToast('Request failed', 'error');
    }
}

// ── Public lookup ─────────────────────────────────────────────────────────────

function getAdrById(adrId) {
    return _adrs.find(a => a.id === adrId) || null;
}

// escapeHtml is provided by modules/utils.js (loaded earlier)

