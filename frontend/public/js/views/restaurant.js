import { api } from '../api.js';
import {
  CANCELLABLE, busy, delegate, empty, esc, formValues, initials, money, notificationItem, openPill, patch, pill, saved,
  shortId, timeAgo, toast,
} from '../ui.js';

let root;
const state = {
  restaurantId: saved.get('restaurantId'),
  tab: saved.get('restaurantTab', 'board'),
};
let data = { restaurant: null, restaurants: [], menu: [], orders: [], notifications: [] };

const $ = (id) => root.querySelector(`#${id}`);
const refreshNow = () => window.dispatchEvent(new Event('kapana:refresh'));

export function mount(el) {
  root = el;
  // Re-read on every mount: another view (e.g. demo data) may have changed it.
  state.restaurantId = saved.get('restaurantId');
  delegate(root, handlers);
  render();
}

function render() {
  root.innerHTML = state.restaurantId ? mainLayout() : authLayout();
  if (state.restaurantId) showTab(state.tab);
}

function authLayout() {
  return `
    <div class="page-head">
      <div><h1>Restaurant dashboard</h1><p class="muted">Manage a registered restaurant, or register a new one.</p></div>
    </div>
    <div class="grid cols-2">
      <section class="card">
        <h2>Your restaurants</h2>
        <div id="r-list" class="list">${empty('Loading…')}</div>
      </section>
      <section class="card">
        <h2>Register a restaurant</h2>
        <form class="stack" data-action="register">
          <label>Name<input name="name" required placeholder="Kapana Corner"></label>
          <label>Description<input name="description" placeholder="Flame-grilled street food"></label>
          <div class="field-row">
            <label>Location<input name="location" required placeholder="Katutura, Windhoek"></label>
            <label>Owner ID<input name="ownerId" required value="owner-1"></label>
          </div>
          <div class="field-row">
            <label>Opens<input name="openTime" required value="08:00" pattern="[0-2][0-9]:[0-5][0-9]"></label>
            <label>Closes<input name="closeTime" required value="22:00" pattern="[0-2][0-9]:[0-5][0-9]"></label>
          </div>
          <button class="btn" type="submit">Register restaurant</button>
        </form>
      </section>
    </div>`;
}

function mainLayout() {
  return `
    <div class="page-head">
      <div><h1 id="r-name">Restaurant</h1><p class="muted" id="r-sub"></p></div>
      <div class="row"><span id="r-toggle"></span><button class="btn ghost" data-action="signout">Switch restaurant</button></div>
    </div>
    <div class="tabs" id="r-tabs"></div>
    <div data-tab="board">
      <div class="banner info" style="margin-bottom:14px">
        New orders are checked automatically against your opening hours, the pause switch and stock, then accepted or rejected
        (Kafka <code>restaurant.status</code>). Accepted orders move to <strong>Preparing</strong> once payment clears –
        mark them <strong>Ready</strong> when the food is done and the driver collects it.
      </div>
      <div id="r-board" class="board"></div>
    </div>
    <div data-tab="inbox">
      <section class="card"><div class="card-head"><h2>Notifications</h2><small>Sent to this restaurant via dashboard + email</small></div><div id="r-inbox" class="feed"></div></section>
    </div>
    <div data-tab="menu">
      <div class="grid split">
        <section class="card"><h2>Menu</h2><div id="r-menu"></div></section>
        <section class="card sticky">
          <h2>Add a dish</h2>
          <form class="stack" data-action="addItem">
            <label>Name<input name="name" required placeholder="Kapana beef strips"></label>
            <label>Description<input name="description" placeholder="With chilli salt and salsa"></label>
            <div class="field-row">
              <label>Price (N$)<input name="price" type="number" min="0.01" step="0.01" required value="45"></label>
              <label>Stock<input name="stockCount" type="number" min="0" step="1" required value="20"></label>
            </div>
            <button class="btn" type="submit">Add to menu</button>
          </form>
        </section>
      </div>
    </div>`;
}

function showTab(tab) {
  state.tab = tab;
  saved.set('restaurantTab', tab);
  root.querySelectorAll('[data-tab]').forEach((el) => el.classList.toggle('hidden', el.dataset.tab !== tab));
  renderTabs();
}

function renderTabs() {
  const waiting = data.orders.filter((o) => o.status === 'PREPARING').length;
  const tabs = [['board', `Orders${waiting ? `<span class="count">${waiting}</span>` : ''}`], ['menu', 'Menu'], ['inbox', 'Notifications']];
  patch($('r-tabs'), tabs.map(([id, label]) =>
    `<button class="${state.tab === id ? 'active' : ''}" data-action="tab" data-tab-id="${id}">${label}</button>`).join(''));
}

export async function refresh() {
  if (!state.restaurantId) {
    try {
      const list = await api.restaurants.list();
      patch($('r-list'), list.length
        ? list.map((r) => `
            <button class="list-item" data-action="pick" data-id="${esc(r.restaurantId)}">
              <span class="avatar">${esc(initials(r.name))}</span>
              <span class="grow"><span class="title">${esc(r.name)}</span><br><small>${esc(r.location)}</small></span>
            </button>`).join('')
        : empty('No restaurants yet', 'Register one to get started.'));
    } catch (err) {
      patch($('r-list'), `<div class="banner">${esc(err.message)}</div>`);
    }
    return;
  }

  const [restaurant, menu, orders, notifications] = await Promise.all([
    api.restaurants.get(state.restaurantId).catch((err) => err),
    api.restaurants.menu(state.restaurantId).catch(() => data.menu),
    api.orders.list({ restaurantId: state.restaurantId }).catch(() => data.orders),
    api.notifications.list({ recipientId: state.restaurantId, audience: 'RESTAURANT', limit: 50 }).catch(() => data.notifications),
  ]);
  if (restaurant instanceof Error) {
    if (restaurant.status === 404) { toast('That restaurant no longer exists', 'error'); signOut(); }
    return;
  }
  data = { ...data, restaurant, menu, orders, notifications };
  patch($('r-name'), esc(restaurant.name));
  patch($('r-sub'), `${esc(restaurant.location)} · open ${esc(restaurant.hours.openTime)}–${esc(restaurant.hours.closeTime)} · ${openPill(restaurant)} · <code>${esc(shortId(restaurant.restaurantId))}</code>`);
  patch($('r-toggle'), `<button class="btn ${restaurant.isOpen ? 'ghost' : 'ok'}" data-action="toggleOpen">${restaurant.isOpen ? 'Pause orders' : 'Resume orders'}</button>`);
  patch($('r-inbox'), notifications.length ? notifications.map((n) => notificationItem(n)).join('') : empty('No notifications yet'));
  renderTabs();
  renderBoard();
  renderMenu();
}

// ---------- Orders board ----------

function ticket(o) {
  const actions = [];
  if (o.status === 'PREPARING') actions.push(`<button class="btn small ok" data-action="ready" data-id="${esc(o.orderId)}">Mark ready</button>`);
  if (CANCELLABLE.includes(o.status)) actions.push(`<button class="btn small danger" data-action="cancel" data-id="${esc(o.orderId)}">Cancel</button>`);
  let note = '';
  if (o.status === 'CREATED') note = 'Accepting…';
  if (o.status === 'CONFIRMED') note = o.paymentStatus === 'FAILED' ? 'Payment failed – waiting for customer retry' : 'Waiting for payment';
  if (o.status === 'READY') note = 'Waiting for driver pickup';
  if (o.status === 'CANCELLED' && o.cancellationReason) note = o.cancellationReason;
  return `
    <div class="ticket">
      <div class="row between"><strong>#${esc(shortId(o.orderId))}</strong><small>${timeAgo(o.createdAt)}</small></div>
      <ul>${o.items.map((i) => `<li>${i.quantity}× ${esc(i.name)}</li>`).join('')}</ul>
      <div class="row between"><span class="price">${money(o.totalAmount)}</span>${pill(o.status)}</div>
      ${note ? `<small class="muted">${esc(note)}</small>` : ''}
      ${actions.length ? `<div class="row">${actions.join('')}</div>` : ''}
    </div>`;
}

function renderBoard() {
  const lanes = [
    ['Incoming', ['CREATED', 'CONFIRMED']],
    ['Preparing', ['PREPARING']],
    ['Ready for pickup', ['READY']],
    ['Out & done', ['OUT_FOR_DELIVERY', 'DELIVERED', 'CANCELLED']],
  ];
  patch($('r-board'), lanes.map(([title, statuses]) => {
    let orders = data.orders.filter((o) => statuses.includes(o.status));
    const total = orders.length;
    if (title === 'Out & done') orders = orders.slice(0, 8);
    return `
      <section class="lane">
        <h3><span>${esc(title)}</span><span>${total}</span></h3>
        ${orders.map(ticket).join('') || '<p class="muted" style="padding:4px;font-size:.85rem">Nothing here</p>'}
      </section>`;
  }).join(''));
}

// ---------- Menu ----------

function renderMenu() {
  if (!data.menu.length) {
    patch($('r-menu'), empty('No dishes yet', 'Add your first dish with the form.'));
    return;
  }
  patch($('r-menu'), `
    <div class="table-wrap"><table>
      <thead><tr><th>Dish</th><th class="num">Price</th><th class="num">Stock</th><th>Status</th><th></th></tr></thead>
      <tbody>${data.menu.map((m) => `
        <tr>
          <td><strong>${esc(m.name)}</strong><br><small>${esc(m.description)}</small></td>
          <td class="num">${money(m.price)}</td>
          <td class="num">
            <span class="qty">
              <button data-action="stock" data-id="${esc(m.itemId)}" data-delta="-1" aria-label="Decrease stock">−</button>
              <strong>${m.stockCount}</strong>
              <button data-action="stock" data-id="${esc(m.itemId)}" data-delta="5" aria-label="Add 5 to stock">+</button>
            </span>
          </td>
          <td>${m.available ? pill('AVAILABLE', 'On menu') : pill('UNAVAILABLE', 'Hidden / sold out')}</td>
          <td class="row" style="justify-content:flex-end">
            <button class="btn small ghost" data-action="toggle" data-id="${esc(m.itemId)}">${m.available ? 'Hide' : 'Show'}</button>
            <button class="btn small danger" data-action="deleteItem" data-id="${esc(m.itemId)}">Delete</button>
          </td>
        </tr>`).join('')}
      </tbody>
    </table></div>`);
}

// ---------- Actions ----------

function signOut() {
  state.restaurantId = null;
  saved.set('restaurantId', null);
  data = { restaurant: null, restaurants: [], menu: [], orders: [] };
  render();
  refreshNow();
}

function pick(id) {
  state.restaurantId = id;
  saved.set('restaurantId', id);
  render();
  refreshNow();
}

const handlers = {
  pick: (el) => pick(el.dataset.id),
  signout: signOut,
  tab: (el) => showTab(el.dataset.tabId),

  toggleOpen: (btn) => busy(btn, async () => {
    const r = await api.restaurants.setOpen(state.restaurantId, !data.restaurant.isOpen);
    toast(r.isOpen ? 'Taking orders again' : 'Paused – new orders will be rejected', r.isOpen ? 'ok' : 'info');
    refreshNow();
  }),

  register: (form, btn) => busy(btn, async () => {
    const v = formValues(form);
    const r = await api.restaurants.register({
      ownerId: v.ownerId, name: v.name, description: v.description, location: v.location,
      hours: { openTime: v.openTime, closeTime: v.closeTime },
    });
    toast(`${r.name} registered`, 'ok');
    pick(r.restaurantId);
  }),

  addItem: (form, btn) => busy(btn, async () => {
    const v = formValues(form);
    await api.restaurants.addItem(state.restaurantId, v);
    form.querySelector('[name=name]').value = '';
    form.querySelector('[name=description]').value = '';
    toast(`${v.name} added`, 'ok');
    refreshNow();
  }),

  stock: (btn) => busy(btn, async () => {
    const m = data.menu.find((x) => x.itemId === btn.dataset.id);
    const stockCount = Math.max(0, m.stockCount + Number(btn.dataset.delta));
    await api.restaurants.updateItem(state.restaurantId, m.itemId, { stockCount, available: stockCount > 0 });
    refreshNow();
  }),

  toggle: (btn) => busy(btn, async () => {
    const m = data.menu.find((x) => x.itemId === btn.dataset.id);
    await api.restaurants.updateItem(state.restaurantId, m.itemId, { available: !m.available });
    refreshNow();
  }),

  deleteItem: (btn) => {
    if (!confirm('Delete this dish?')) return;
    busy(btn, async () => {
      await api.restaurants.deleteItem(state.restaurantId, btn.dataset.id);
      refreshNow();
    });
  },

  ready: (btn) => busy(btn, async () => {
    await api.orders.setStatus(btn.dataset.id, 'READY');
    toast('Marked ready for pickup', 'ok');
    refreshNow();
  }),

  cancel: (btn) => {
    if (!confirm('Cancel this order?')) return;
    busy(btn, async () => {
      await api.orders.setStatus(btn.dataset.id, 'CANCELLED');
      refreshNow();
    });
  },
};
