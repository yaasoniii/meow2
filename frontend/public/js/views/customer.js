import { api } from '../api.js';
import {
  CANCELLABLE, busy, delegate, empty, esc, formValues, initials, itemsLine, money, patch, pill, saved, shortId,
  timeAgo, timeline, toast,
} from '../ui.js';

let root;
const state = {
  customerId: saved.get('customerId'),
  tab: saved.get('customerTab', 'browse'),
  restaurantId: saved.get('customerRestaurant'),
  // { restaurantId, items: { [itemId]: { itemId, name, unitPrice, quantity, stockCount } } }
  cart: saved.get('cart', { restaurantId: null, items: {} }),
};
let data = { customer: null, restaurants: [], menu: [], orders: [], deliveries: [], drivers: [], notifications: [] };

const $ = (id) => root.querySelector(`#${id}`);
const refreshNow = () => window.dispatchEvent(new Event('kapana:refresh'));

export function mount(el) {
  root = el;
  // Re-read on every mount: another view (e.g. demo data) may have changed it.
  state.customerId = saved.get('customerId');
  state.restaurantId = saved.get('customerRestaurant');
  state.cart = saved.get('cart', { restaurantId: null, items: {} });
  delegate(root, handlers);
  render();
}

function render() {
  root.innerHTML = state.customerId ? mainLayout() : authLayout();
  if (state.customerId) {
    showTab(state.tab);
    renderCart();
  }
}

// ---------- Layouts ----------

function authLayout() {
  return `
    <div class="page-head">
      <div><h1>Hungry?</h1><p class="muted">Continue as a registered customer, or create an account to start ordering.</p></div>
    </div>
    <div class="grid cols-2">
      <section class="card">
        <h2>Continue as</h2>
        <div id="c-customers" class="list">${empty('Loading customers…')}</div>
      </section>
      <section class="card">
        <h2>Create an account</h2>
        <form class="stack" data-action="register">
          <label>Full name<input name="fullName" required placeholder="Ndapewa Shikongo" autocomplete="name"></label>
          <label>Email<input name="email" type="email" required placeholder="you@example.com" autocomplete="email"></label>
          <label>Phone<input name="phone" required placeholder="+264811234567" autocomplete="tel"></label>
          <button class="btn" type="submit">Create account</button>
        </form>
      </section>
    </div>`;
}

function mainLayout() {
  return `
    <div class="page-head">
      <div><h1 id="c-greeting">Welcome back</h1><p class="muted" id="c-sub">Loading your account…</p></div>
      <button class="btn ghost" data-action="signout">Switch customer</button>
    </div>
    <div class="tabs" id="c-tabs" role="tablist"></div>

    <div data-tab="browse">
      <div class="grid browse">
        <section class="card">
          <h2>Restaurants</h2>
          <div id="c-restaurants" class="list">${empty('Loading…')}</div>
        </section>
        <section class="card" id="c-menu">${empty('Pick a restaurant', 'Its menu will appear here.')}</section>
        <aside class="card sticky">
          <h2>Your order</h2>
          <div id="c-cart"></div>
        </aside>
      </div>
    </div>

    <div data-tab="orders"><div id="c-orders" class="stack">${empty('Loading your orders…')}</div></div>

    <div data-tab="inbox">
      <section class="card">
        <div class="card-head"><h2>Notifications</h2><small>From the Notification Service, built from Kafka events</small></div>
        <div id="c-inbox" class="feed">${empty('Loading…')}</div>
      </section>
    </div>

    <div data-tab="account">
      <div class="grid cols-2">
        <section class="card"><h2>Profile</h2><div id="c-profile"></div></section>
        <section class="card">
          <h2>Delivery addresses</h2>
          <div id="c-addresses" class="list"></div>
          <form class="stack" data-action="addAddress" style="margin-top:14px">
            <div class="field-row">
              <label>Label<input name="label" required placeholder="Home"></label>
              <label>Street<input name="street" required placeholder="12 Independence Ave"></label>
            </div>
            <div class="field-row">
              <label>City<input name="city" required value="Windhoek"></label>
              <label>Postal code<input name="postalCode" required value="10005"></label>
              <label>Country<input name="country" required value="Namibia"></label>
            </div>
            <label class="check"><input type="checkbox" name="isDefault"> Make this my default address</label>
            <button class="btn" type="submit">Add address</button>
          </form>
        </section>
      </div>
    </div>`;
}

function showTab(tab) {
  state.tab = tab;
  saved.set('customerTab', tab);
  root.querySelectorAll('[data-tab]').forEach((el) => el.classList.toggle('hidden', el.dataset.tab !== tab));
  renderTabs();
}

function renderTabs() {
  const active = data.orders.filter((o) => !['DELIVERED', 'CANCELLED'].includes(o.status)).length;
  const tabs = [
    ['browse', 'Order food'],
    ['orders', `My orders${active ? `<span class="count">${active}</span>` : ''}`],
    ['inbox', 'Notifications'],
    ['account', 'Account'],
  ];
  patch($('c-tabs'), tabs.map(([id, label]) =>
    `<button role="tab" aria-selected="${state.tab === id}" class="${state.tab === id ? 'active' : ''}" data-action="tab" data-tab-id="${id}">${label}</button>`).join(''));
}

// ---------- Data ----------

const settle = (p, fallback) => p.then((v) => v, () => fallback);

export async function refresh() {
  if (!state.customerId) {
    try {
      const customers = await api.customers.list();
      patch($('c-customers'), customers.length
        ? customers.map((c) => `
            <button class="list-item" data-action="pick" data-id="${esc(c.customerId)}">
              <span class="avatar">${esc(initials(c.fullName))}</span>
              <span class="grow"><span class="title">${esc(c.fullName)}</span><br><small class="ellipsis">${esc(c.email)}</small></span>
            </button>`).join('')
        : empty('No customers yet', 'Create the first account, or load demo data from the System tab.'));
    } catch (err) {
      patch($('c-customers'), `<div class="banner">${esc(err.message)}</div>`);
    }
    return;
  }

  const needsDelivery = state.tab === 'orders';
  const [customer, restaurants, orders, notifications, deliveries, drivers, menu] = await Promise.all([
    api.customers.get(state.customerId).catch((err) => err),
    settle(api.restaurants.list(), data.restaurants),
    settle(api.orders.list({ customerId: state.customerId }), data.orders),
    settle(api.notifications.list({ customerId: state.customerId, limit: 100 }), data.notifications),
    needsDelivery ? settle(api.deliveries.list(), data.deliveries) : data.deliveries,
    needsDelivery ? settle(api.drivers.list(), data.drivers) : data.drivers,
    state.restaurantId ? settle(api.restaurants.menu(state.restaurantId), data.menu) : [],
  ]);

  if (customer instanceof Error) {
    if (customer.status === 404) {
      toast('That customer no longer exists', 'error');
      signOut();
    } else {
      patch($('c-sub'), `<span class="banner">${esc(customer.message)}</span>`);
    }
    return;
  }

  data = { customer, restaurants, orders, notifications, deliveries, drivers, menu };
  patch($('c-greeting'), `Hi, ${esc(customer.fullName.split(' ')[0])}`);
  patch($('c-sub'), `${esc(customer.email)} · customer <code>${esc(shortId(customer.customerId))}</code>`);
  renderTabs();
  renderRestaurants();
  renderMenu();
  renderOrders();
  renderInbox();
  renderAccount();
}

// ---------- Browse ----------

function renderRestaurants() {
  const list = data.restaurants;
  patch($('c-restaurants'), list.length
    ? list.map((r) => `
        <button class="list-item ${r.restaurantId === state.restaurantId ? 'selected' : ''}" data-action="openRestaurant" data-id="${esc(r.restaurantId)}">
          <span class="avatar">${esc(initials(r.name))}</span>
          <span class="grow"><span class="title ellipsis">${esc(r.name)}</span><br><small>${esc(r.location)} · ${esc(r.hours.openTime)}–${esc(r.hours.closeTime)}</small></span>
        </button>`).join('')
    : empty('No restaurants yet', 'Register one in the Restaurant tab.'));
}

function renderMenu() {
  const r = data.restaurants.find((x) => x.restaurantId === state.restaurantId);
  if (!r) {
    patch($('c-menu'), empty('Pick a restaurant', 'Its menu will appear here.'));
    return;
  }
  const items = data.menu.map((m) => {
    const inCart = state.cart.restaurantId === r.restaurantId ? state.cart.items[m.itemId]?.quantity || 0 : 0;
    const soldOut = !m.available || m.stockCount <= inCart;
    return `
      <div class="menu-item">
        <div class="grow">
          <div class="title">${esc(m.name)}</div>
          <small>${esc(m.description)}</small>
          <div><small>${m.available ? `${m.stockCount} left` : 'Sold out'}</small></div>
        </div>
        <div class="stack" style="justify-items:end;gap:6px">
          <span class="price">${money(m.price)}</span>
          <button class="btn small" data-action="add" data-id="${esc(m.itemId)}" ${soldOut ? 'disabled' : ''}>${inCart ? `Add · ${inCart}` : 'Add'}</button>
        </div>
      </div>`;
  }).join('');
  patch($('c-menu'), `
    <div class="card-head"><div><h2>${esc(r.name)}</h2><small>${esc(r.description)}</small></div></div>
    ${items || empty('No dishes yet', 'This restaurant has not added a menu.')}`);
}

function cartLines() {
  return Object.values(state.cart.items);
}

function renderCart() {
  const lines = cartLines();
  const el = $('c-cart');
  if (!el) return;
  if (!lines.length) {
    patch(el, empty('Your basket is empty', 'Add dishes from a menu.'));
    return;
  }
  const r = data.restaurants.find((x) => x.restaurantId === state.cart.restaurantId);
  const total = lines.reduce((sum, l) => sum + l.unitPrice * l.quantity, 0);
  patch(el, `
    <p class="muted" style="margin-bottom:8px">From <strong>${esc(r?.name || 'restaurant')}</strong></p>
    <div class="stack" style="gap:10px">
      ${lines.map((l) => `
        <div class="row between">
          <span class="grow">${esc(l.name)}<br><small>${money(l.unitPrice)}</small></span>
          <span class="qty">
            <button data-action="dec" data-id="${esc(l.itemId)}" aria-label="One less ${esc(l.name)}">−</button>
            <strong>${l.quantity}</strong>
            <button data-action="inc" data-id="${esc(l.itemId)}" aria-label="One more ${esc(l.name)}" ${l.quantity >= l.stockCount ? 'disabled' : ''}>+</button>
          </span>
        </div>`).join('')}
      <div class="total-row"><span>Total</span><span>${money(total)}</span></div>
      <button class="btn block" data-action="placeOrder">Place order</button>
      <small class="muted">Payment is taken automatically when the order is placed.</small>
    </div>`);
}

function saveCart() {
  saved.set('cart', state.cart);
  renderCart();
  renderMenu();
}

// ---------- Orders ----------

function nextStepHint(o, delivery, driver) {
  const who = driver ? driver.name : 'Your driver';
  switch (o.status) {
    case 'CREATED':
      return o.paymentStatus === 'FAILED' ? 'Payment failed – retry it to continue.' : 'Waiting for the restaurant to accept your order…';
    case 'CONFIRMED':
      return o.paymentStatus === 'FAILED' ? 'Payment failed – retry it to continue.' : 'Restaurant accepted. Confirming your payment…';
    case 'PREPARING': return 'The kitchen is cooking your food.';
    case 'READY': return driver ? `${who} is on the way to collect your food.` : 'Food is ready – finding a driver…';
    case 'OUT_FOR_DELIVERY': return `${who} is bringing your order.`;
    case 'DELIVERED': return 'Delivered. Enjoy your meal!';
    case 'CANCELLED': return 'This order was cancelled.';
    default: return '';
  }
}

function renderOrders() {
  const byId = (arr, key) => Object.fromEntries(arr.map((x) => [x[key], x]));
  const restaurants = byId(data.restaurants, 'restaurantId');
  const deliveries = byId(data.deliveries, 'orderId');
  const drivers = byId(data.drivers, 'driverId');
  const notes = {};
  for (const n of data.notifications) (notes[n.orderId] ||= []).push(n);

  if (!data.orders.length) {
    patch($('c-orders'), `<section class="card">${empty('No orders yet', 'Your orders and their live progress will show up here.')}</section>`);
    return;
  }

  patch($('c-orders'), data.orders.map((o) => {
    const delivery = deliveries[o.orderId];
    const driver = delivery?.driverId ? drivers[delivery.driverId] : null;
    const payment = o.paymentStatus ? pill(o.paymentStatus) : pill('PENDING', 'Payment pending');
    const canRetry = o.paymentStatus === 'FAILED' && o.status !== 'CANCELLED';
    const orderNotes = (notes[o.orderId] || []).slice(0, 8);
    return `
      <article class="card order-card">
        <div class="row between">
          <div>
            <h3>${esc(restaurants[o.restaurantId]?.name || `Restaurant ${shortId(o.restaurantId)}`)}</h3>
            <div class="meta"><span>Order <code>${esc(shortId(o.orderId))}</code></span><span>${timeAgo(o.createdAt)}</span><span>${money(o.totalAmount)}</span></div>
          </div>
          ${pill(o.status)}
        </div>
        ${timeline(o)}
        <p><strong>${esc(nextStepHint(o, delivery, driver))}</strong></p>
        <p class="items-line muted">${esc(itemsLine(o.items))}</p>
        <div class="facts">
          ${payment}
          ${delivery ? pill(delivery.status) : ''}
          ${driver ? `<span class="pill">${esc(driver.name)} · ${esc(driver.vehicleType)} · ${esc(driver.plateNumber)}</span>` : ''}
        </div>
        ${canRetry || CANCELLABLE.includes(o.status) ? `
          <div class="actions">
            ${canRetry ? `<button class="btn small" data-action="retryPayment" data-id="${esc(o.orderId)}">Retry payment</button>` : ''}
            ${CANCELLABLE.includes(o.status) ? `<button class="btn small danger" data-action="cancelOrder" data-id="${esc(o.orderId)}">Cancel order</button>` : ''}
          </div>` : ''}
        ${orderNotes.length ? `
          <details style="margin-top:12px">
            <summary class="muted" style="cursor:pointer">Activity (${orderNotes.length})</summary>
            <div class="feed">${orderNotes.map(feedItem).join('')}</div>
          </details>` : ''}
      </article>`;
  }).join(''));
}

function feedItem(n) {
  return `<div class="feed-item"><span class="bullet"></span><span><strong>${esc(n.title)}</strong> – ${esc(n.message)}</span><time datetime="${esc(n.timestamp)}">${timeAgo(n.timestamp)}</time></div>`;
}

function renderInbox() {
  patch($('c-inbox'), data.notifications.length
    ? data.notifications.map(feedItem).join('')
    : empty('Nothing yet', 'Updates about your orders will appear here.'));
}

// ---------- Account ----------

function renderAccount() {
  const c = data.customer;
  patch($('c-profile'), `
    <div class="row" style="gap:14px">
      <span class="avatar" style="width:56px;height:56px;font-size:1.2rem">${esc(initials(c.fullName))}</span>
      <div><h3>${esc(c.fullName)}</h3><div class="muted">${esc(c.email)}</div><div class="muted">${esc(c.phone)}</div></div>
    </div>
    <p class="muted" style="margin-top:14px">Customer ID <code>${esc(c.customerId)}</code></p>
    <p class="muted">Member since ${new Date(c.createdAt).toLocaleDateString()}</p>`);
  patch($('c-addresses'), c.addresses.length
    ? c.addresses.map((a) => `
        <div class="list-item">
          <div class="grow"><span class="title">${esc(a.label)}</span> ${a.isDefault ? pill('SUCCESS', 'Default') : ''}<br>
            <small>${esc(a.street)}, ${esc(a.city)} ${esc(a.postalCode)}, ${esc(a.country)}</small></div>
          <button class="btn small ghost" data-action="deleteAddress" data-id="${esc(a.addressId)}">Remove</button>
        </div>`).join('')
    : `<div class="banner">Add an address so your driver knows where to deliver.</div>`);
}

// ---------- Actions ----------

function signOut() {
  state.customerId = null;
  saved.set('customerId', null);
  data = { customer: null, restaurants: [], menu: [], orders: [], deliveries: [], drivers: [], notifications: [] };
  render();
  refreshNow();
}

function pickCustomer(id) {
  state.customerId = id;
  saved.set('customerId', id);
  render();
  refreshNow();
}

const handlers = {
  pick: (el) => pickCustomer(el.dataset.id),
  signout: signOut,
  tab: (el) => { showTab(el.dataset.tabId); refreshNow(); },

  register: (form, btn) => busy(btn, async () => {
    const c = await api.customers.register(formValues(form));
    toast(`Welcome, ${c.fullName}!`, 'ok');
    pickCustomer(c.customerId);
  }),

  openRestaurant: (el) => {
    state.restaurantId = el.dataset.id;
    saved.set('customerRestaurant', state.restaurantId);
    data.menu = [];
    patch($('c-menu'), empty('Loading menu…'));
    renderRestaurants();
    refreshNow();
  },

  add: (el) => {
    const m = data.menu.find((x) => x.itemId === el.dataset.id);
    if (!m) return;
    if (state.cart.restaurantId && state.cart.restaurantId !== state.restaurantId && cartLines().length) {
      if (!confirm('Your basket has dishes from another restaurant. Start a new basket?')) return;
      state.cart = { restaurantId: null, items: {} };
    }
    state.cart.restaurantId = state.restaurantId;
    const line = state.cart.items[m.itemId] ||= { itemId: m.itemId, name: m.name, unitPrice: Number(m.price), quantity: 0 };
    line.stockCount = m.stockCount;
    line.quantity += 1;
    saveCart();
  },
  inc: (el) => { const l = state.cart.items[el.dataset.id]; if (l) { l.quantity += 1; saveCart(); } },
  dec: (el) => {
    const l = state.cart.items[el.dataset.id];
    if (!l) return;
    l.quantity -= 1;
    if (l.quantity <= 0) delete state.cart.items[l.itemId];
    if (!cartLines().length) state.cart.restaurantId = null;
    saveCart();
  },

  placeOrder: (btn) => busy(btn, async () => {
    const items = cartLines().map(({ itemId, name, quantity, unitPrice }) => ({ itemId, name, quantity, unitPrice }));
    const order = await api.orders.create({ customerId: state.customerId, restaurantId: state.cart.restaurantId, items });
    state.cart = { restaurantId: null, items: {} };
    saveCart();
    toast(`Order ${shortId(order.orderId)} placed – ${money(order.totalAmount)}`, 'ok');
    data.orders = [order, ...data.orders];
    showTab('orders');
    renderOrders();
    refreshNow();
  }),

  cancelOrder: (btn) => {
    if (!confirm('Cancel this order?')) return;
    busy(btn, async () => {
      await api.orders.setStatus(btn.dataset.id, 'CANCELLED');
      toast('Order cancelled');
      refreshNow();
    });
  },

  retryPayment: (btn) => busy(btn, async () => {
    const o = data.orders.find((x) => x.orderId === btn.dataset.id);
    const p = await api.payments.initiate({ orderId: o.orderId, customerId: o.customerId, amount: o.totalAmount });
    toast(p.status === 'SUCCESS' ? 'Payment successful' : 'Payment failed again – try once more', p.status === 'SUCCESS' ? 'ok' : 'error');
    refreshNow();
  }),

  addAddress: (form, btn) => busy(btn, async () => {
    await api.customers.addAddress(state.customerId, formValues(form));
    form.reset();
    toast('Address saved', 'ok');
    refreshNow();
  }),

  deleteAddress: (btn) => busy(btn, async () => {
    await api.customers.deleteAddress(state.customerId, btn.dataset.id);
    refreshNow();
  }),
};
