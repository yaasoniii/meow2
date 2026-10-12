import { api } from '../api.js';
import {
  busy, delegate, empty, esc, formValues, initials, itemsLine, money, notificationItem, patch, pill, saved, shortId, timeAgo,
  toast,
} from '../ui.js';

let root;
const state = { driverId: saved.get('driverId') };
let data = { driver: null, deliveries: [], pending: 0, job: null, notifications: [] };

const $ = (id) => root.querySelector(`#${id}`);
const refreshNow = () => window.dispatchEvent(new Event('kapana:refresh'));
const ACTIVE = ['ASSIGNED', 'PICKED_UP', 'IN_PROGRESS'];

export function mount(el) {
  root = el;
  // Re-read on every mount: another view (e.g. demo data) may have changed it.
  state.driverId = saved.get('driverId');
  delegate(root, handlers);
  render();
}

function render() {
  root.innerHTML = state.driverId ? mainLayout() : authLayout();
}

function authLayout() {
  return `
    <div class="page-head">
      <div><h1>Driver app</h1><p class="muted">Sign in as a registered driver, or register to start taking deliveries.</p></div>
    </div>
    <div class="grid cols-2">
      <section class="card"><h2>Drivers</h2><div id="d-list" class="list">${empty('Loading…')}</div></section>
      <section class="card">
        <h2>Register as a driver</h2>
        <form class="stack" data-action="register">
          <label>Name<input name="name" required placeholder="Tangeni Amupolo"></label>
          <label>Phone<input name="phoneNumber" required placeholder="0812345678"></label>
          <div class="field-row">
            <label>Plate number<input name="plateNumber" required placeholder="N 12345 W"></label>
            <label>Vehicle<input name="vehicleType" required placeholder="Motorbike"></label>
          </div>
          <button class="btn" type="submit">Register</button>
        </form>
      </section>
    </div>`;
}

function mainLayout() {
  return `
    <div class="page-head">
      <div><h1 id="d-name">Driver</h1><p class="muted" id="d-sub"></p></div>
      <div class="row">
        <span id="d-toggle"></span>
        <button class="btn ghost" data-action="signout">Switch driver</button>
      </div>
    </div>
    <div class="grid split">
      <section class="card"><div class="card-head"><h2>Current job</h2></div><div id="d-job"></div></section>
      <div class="stack">
        <section class="card"><h2>Recent deliveries</h2><div id="d-history" class="list"></div></section>
        <section class="card"><div class="card-head"><h2>Notifications</h2><small>push + SMS</small></div><div id="d-inbox" class="feed"></div></section>
      </div>
    </div>`;
}

export async function refresh() {
  if (!state.driverId) {
    try {
      const drivers = await api.drivers.list();
      patch($('d-list'), drivers.length
        ? drivers.map((d) => `
            <button class="list-item" data-action="pick" data-id="${esc(d.driverId)}">
              <span class="avatar">${esc(initials(d.name))}</span>
              <span class="grow"><span class="title">${esc(d.name)}</span><br><small>${esc(d.vehicleType)} · ${esc(d.plateNumber)}</small></span>
              ${pill(d.status)}
            </button>`).join('')
        : empty('No drivers yet', 'Register to start delivering.'));
    } catch (err) {
      patch($('d-list'), `<div class="banner">${esc(err.message)}</div>`);
    }
    return;
  }

  const [driver, deliveries, pending, notifications] = await Promise.all([
    api.drivers.get(state.driverId).catch((err) => err),
    api.deliveries.list({ driverId: state.driverId }).catch(() => data.deliveries),
    api.deliveries.list({ status: 'PENDING' }).catch(() => []),
    api.notifications.list({ recipientId: state.driverId, audience: 'DRIVER', limit: 20 }).catch(() => data.notifications),
  ]);
  if (driver instanceof Error) {
    if (driver.status === 404) { toast('That driver no longer exists', 'error'); signOut(); }
    return;
  }

  const active = deliveries.find((d) => ACTIVE.includes(d.status));
  let job = null;
  if (active) {
    // Everything the driver needs about the order lives in other services.
    const order = await api.orders.get(active.orderId).catch(() => null);
    const [restaurant, customer] = order ? await Promise.all([
      api.restaurants.get(order.restaurantId).catch(() => null),
      api.customers.get(order.customerId).catch(() => null),
    ]) : [null, null];
    job = { delivery: active, order, restaurant, customer };
  }

  data = { driver, deliveries, pending: pending.length, job, notifications };
  patch($('d-inbox'), notifications.length ? notifications.map((n) => notificationItem(n)).join('') : empty('No notifications yet'));
  patch($('d-name'), esc(driver.name));
  patch($('d-sub'), `${esc(driver.vehicleType)} · ${esc(driver.plateNumber)} · ${esc(driver.phoneNumber)} · ${pill(driver.status)}`);
  patch($('d-toggle'), driver.status === 'ON_DELIVERY' ? ''
    : `<button class="btn ${driver.status === 'AVAILABLE' ? 'ghost' : 'ok'}" data-action="toggle">${driver.status === 'AVAILABLE' ? 'Go off shift' : 'Go online'}</button>`);
  renderJob();
  renderHistory();
}

function renderJob() {
  const { job, driver, pending } = data;
  if (!job) {
    const waiting = pending ? `${pending} order${pending > 1 ? 's are' : ' is'} waiting for a driver.` : 'No orders are waiting right now.';
    patch($('d-job'), driver.status === 'AVAILABLE'
      ? empty('You are online', `New deliveries are assigned to you automatically. ${waiting}`)
      : empty('You are off shift', `Go online to receive deliveries. ${waiting}`));
    return;
  }

  const { delivery, order, restaurant, customer } = job;
  const address = customer?.addresses?.find((a) => a.isDefault);
  let action = '';
  if (delivery.status === 'ASSIGNED') {
    const ready = order?.status === 'READY';
    action = ready
      ? `<button class="btn block" data-action="advance" data-status="PICKED_UP">Confirm pickup</button>`
      : `<button class="btn block" disabled>Waiting for the kitchen</button>
         <small class="muted">The order is ${esc(order ? order.status.toLowerCase().replaceAll('_', ' ') : 'unknown')}. Pickup unlocks when the restaurant marks it ready.</small>`;
  } else if (delivery.status === 'PICKED_UP') {
    action = `<button class="btn block" data-action="advance" data-status="IN_PROGRESS">Start trip</button>`;
  } else if (delivery.status === 'IN_PROGRESS') {
    action = `<button class="btn block ok" data-action="advance" data-status="DELIVERED">Mark delivered</button>`;
  }

  patch($('d-job'), `
    <div class="stack">
      <div class="row between"><strong>Order #${esc(shortId(delivery.orderId))}</strong>${pill(delivery.status)}</div>
      <div class="grid cols-2">
        <div><small class="muted">Collect from</small><div class="title">${esc(restaurant?.name || 'Restaurant')}</div><small>${esc(restaurant?.location || '')}</small></div>
        <div><small class="muted">Deliver to</small><div class="title">${esc(customer?.fullName || 'Customer')}</div>
          <small>${address ? `${esc(address.street)}, ${esc(address.city)}` : 'No saved address'}${customer ? ` · ${esc(customer.phone)}` : ''}</small></div>
      </div>
      ${order ? `<p class="items-line">${esc(itemsLine(order.items))} · <strong>${money(order.totalAmount)}</strong></p>` : ''}
      ${action}
    </div>`);
}

function renderHistory() {
  const done = data.deliveries.filter((d) => !ACTIVE.includes(d.status)).slice(0, 10);
  patch($('d-history'), done.length
    ? done.map((d) => `
        <div class="list-item"><div class="grow"><span class="title">#${esc(shortId(d.orderId))}</span><br><small>${timeAgo(d.updatedAt || d.createdAt)}</small></div>${pill(d.status)}</div>`).join('')
    : empty('No completed deliveries yet'));
}

function signOut() {
  state.driverId = null;
  saved.set('driverId', null);
  render();
  refreshNow();
}

function pick(id) {
  state.driverId = id;
  saved.set('driverId', id);
  render();
  refreshNow();
}

const handlers = {
  pick: (el) => pick(el.dataset.id),
  signout: signOut,

  register: (form, btn) => busy(btn, async () => {
    const d = await api.drivers.register(formValues(form));
    toast(d.status === 'ON_DELIVERY' ? `Welcome ${d.name} – you already have a delivery!` : `Welcome ${d.name}`, 'ok');
    pick(d.driverId);
  }),

  toggle: (btn) => busy(btn, async () => {
    await api.drivers.setStatus(state.driverId, data.driver.status === 'AVAILABLE' ? 'UNAVAILABLE' : 'AVAILABLE');
    refreshNow();
  }),

  advance: (btn) => busy(btn, async () => {
    await api.deliveries.setStatus(data.job.delivery.deliveryId, btn.dataset.status);
    if (btn.dataset.status === 'DELIVERED') toast('Delivery complete – nice work!', 'ok');
    refreshNow();
  }),
};
