// Small rendering helpers shared by every view.

export function esc(value) {
  return String(value ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}

export function money(amount) {
  return `N$ ${Number(amount ?? 0).toFixed(2)}`;
}

export function shortId(id) {
  return id ? String(id).slice(0, 8) : '';
}

export function initials(name) {
  return String(name || '?').split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0].toUpperCase()).join('');
}

export function timeAgo(iso) {
  if (!iso) return '';
  const t = Date.parse(iso);
  if (Number.isNaN(t)) return '';
  const s = Math.max(0, Math.round((Date.now() - t) / 1000));
  if (s < 10) return 'just now';
  if (s < 60) return `${s}s ago`;
  if (s < 3600) return `${Math.floor(s / 60)}m ago`;
  if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
  return new Date(t).toLocaleDateString();
}

export const LABEL = {
  CREATED: 'Placed', CONFIRMED: 'Confirmed', PREPARING: 'Preparing', READY: 'Ready',
  OUT_FOR_DELIVERY: 'On the way', DELIVERED: 'Delivered', CANCELLED: 'Cancelled',
  PENDING: 'Awaiting driver', ASSIGNED: 'Driver assigned', PICKED_UP: 'Picked up', IN_PROGRESS: 'En route',
  SUCCESS: 'Paid', FAILED: 'Payment failed', REFUNDED: 'Refunded',
  AVAILABLE: 'Available', ON_DELIVERY: 'On delivery', UNAVAILABLE: 'Off shift',
  UP: 'Up', DOWN: 'Down',
};

export function pill(status, label) {
  const s = String(status || 'UNKNOWN');
  return `<span class="pill pill-${esc(s.toLowerCase())}">${esc(label ?? LABEL[s] ?? s)}</span>`;
}

export const ORDER_STEPS = ['CREATED', 'CONFIRMED', 'PREPARING', 'READY', 'OUT_FOR_DELIVERY', 'DELIVERED'];
export const CANCELLABLE = ['CREATED', 'CONFIRMED', 'PREPARING'];

// Progress dots for the order lifecycle. A cancelled order shows how far it got, in red.
export function timeline(order, reachedBeforeCancel = 0) {
  const cancelled = order.status === 'CANCELLED';
  const idx = cancelled ? reachedBeforeCancel : ORDER_STEPS.indexOf(order.status);
  const steps = ORDER_STEPS.map((s, i) => {
    const cls = [i <= idx ? 'done' : '', i === idx && !cancelled && s !== 'DELIVERED' ? 'current' : ''].join(' ');
    return `<div class="step ${cls}"><span class="dot"></span><span>${esc(LABEL[s])}</span></div>`;
  }).join('');
  return `<div class="timeline ${cancelled ? 'cancelled' : ''}" role="img" aria-label="Order status: ${esc(LABEL[order.status] || order.status)}">${steps}</div>`;
}

// Mirrors the Restaurant Service's rule (isWithinOpeningHours): open time
// inclusive, close time exclusive, overnight hours allowed, equal = all day.
export function isOpenNow(r, now = new Date()) {
  if (!r || !r.isOpen) return false;
  const mins = (hhmm) => Number(hhmm.slice(0, 2)) * 60 + Number(hhmm.slice(3, 5));
  const open = mins(r.hours.openTime);
  const close = mins(r.hours.closeTime);
  const cur = now.getHours() * 60 + now.getMinutes();
  if (open === close) return true;
  return open < close ? cur >= open && cur < close : cur >= open || cur < close;
}

export function openPill(r) {
  if (!r.isOpen) return pill('UNAVAILABLE', 'Paused');
  return isOpenNow(r) ? pill('AVAILABLE', 'Open') : pill('UNAVAILABLE', `Opens ${r.hours.openTime}`);
}

// One notification row; shows who it was for and on which channels when asked.
export function notificationItem(n, { showAudience = false } = {}) {
  const meta = showAudience
    ? `<br><small><span class="topic">${esc(n.audience)}</span> ${(n.channels || []).map((c) => `<span class="topic">${esc(c)}</span>`).join(' ')} · order <code>${esc(shortId(n.orderId))}</code></small>`
    : `<br><small class="muted">via ${esc((n.channels || []).join(' + ').toLowerCase())}</small>`;
  return `<div class="feed-item"><span class="bullet"></span><span><strong>${esc(n.title)}</strong> – ${esc(n.message)}${meta}</span><time datetime="${esc(n.timestamp)}">${timeAgo(n.timestamp)}</time></div>`;
}

export function empty(title, hint = '') {
  return `<div class="empty"><strong>${esc(title)}</strong>${hint ? `<span>${esc(hint)}</span>` : ''}</div>`;
}

export function itemsLine(items = []) {
  return items.map((i) => `${i.quantity}× ${i.name}`).join(', ');
}

// Replaces an element's HTML only when it changed, so polling doesn't reset
// scroll positions, hover states or open <details>.
export function patch(el, html) {
  if (el && el.__html !== html) {
    el.innerHTML = html;
    el.__html = html;
  }
}

export function toast(message, kind = 'info') {
  const host = document.getElementById('toasts');
  const el = document.createElement('div');
  el.className = `toast ${kind}`;
  el.textContent = message;
  host.appendChild(el);
  setTimeout(() => el.remove(), kind === 'error' ? 6000 : 3500);
}

// Runs an async action with the button in a busy state and errors shown as toasts.
export async function busy(button, action) {
  if (button) { button.disabled = true; button.classList.add('busy'); }
  try {
    return await action();
  } catch (err) {
    toast(err.message || String(err), 'error');
    return undefined;
  } finally {
    if (button) { button.disabled = false; button.classList.remove('busy'); }
  }
}

export function formValues(form) {
  const out = {};
  for (const el of form.elements) {
    if (!el.name) continue;
    if (el.type === 'checkbox') out[el.name] = el.checked;
    else if (el.type === 'number') out[el.name] = el.value === '' ? undefined : Number(el.value);
    else out[el.name] = el.value.trim();
  }
  return out;
}

// localStorage that never throws (private mode, blocked storage, ...).
export const saved = {
  get(key, fallback = null) {
    try {
      const v = localStorage.getItem(`kapana.${key}`);
      return v === null ? fallback : JSON.parse(v);
    } catch { return fallback; }
  },
  set(key, value) {
    try {
      if (value === null || value === undefined) localStorage.removeItem(`kapana.${key}`);
      else localStorage.setItem(`kapana.${key}`, JSON.stringify(value));
    } catch { /* ignore */ }
  },
};

// Makes a view's root handle [data-action] clicks and form submits by name.
export function delegate(root, handlers) {
  root.addEventListener('click', (e) => {
    const el = e.target.closest('[data-action]');
    if (!el || !root.contains(el) || el.tagName === 'FORM') return;
    const fn = handlers[el.dataset.action];
    if (fn) { e.preventDefault(); fn(el, e); }
  });
  root.addEventListener('submit', (e) => {
    const form = e.target.closest('form[data-action]');
    if (!form) return;
    e.preventDefault();
    const fn = handlers[form.dataset.action];
    if (fn) fn(form, form.querySelector('[type=submit]'));
  });
  root.addEventListener('change', (e) => {
    const el = e.target.closest('[data-change]');
    if (!el) return;
    const fn = handlers[el.dataset.change];
    if (fn) fn(el, e);
  });
}
