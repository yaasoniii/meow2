import { api } from '../api.js';
import { busy, delegate, empty, esc, notificationItem, patch, pill, saved, toast } from '../ui.js';

const SERVICES = [
  { key: 'order', name: 'Order Service', port: 8081, health: '/health', owner: 'Jason' },
  { key: 'customer', name: 'Customer Service', port: 8082, health: '/health', owner: '' },
  { key: 'restaurant', name: 'Restaurant Service', port: 8083, health: '/health', owner: 'Renate' },
  { key: 'payment', name: 'Payment Service', port: 8084, health: '/payments/health', owner: 'Albert' },
  { key: 'delivery', name: 'Delivery Service', port: 8085, health: '/health', owner: 'Penny' },
  { key: 'notification', name: 'Notification Service', port: 8086, health: '/health', owner: 'Gerson' },
  { key: 'admin', name: 'Admin Service', port: 8087, health: '/admin/health', owner: 'Celine' },
];

const FLOW = [
  ['Customer places an order', 'Order Service saves it as <b>CREATED</b> and publishes <code>orders.created</code>.'],
  ['Restaurant accepts or rejects', 'Restaurant Service consumes <code>orders.created</code>, checks opening hours and stock, reduces stock and publishes <code>restaurant.status</code> ACKNOWLEDGED → order <b>CONFIRMED</b> (or REJECTED → <b>CANCELLED</b> and refunded).'],
  ['Payment is taken', 'Payment Service consumes <code>orders.created</code>, charges (simulated) and publishes <code>payments.completed</code> SUCCESS/FAILED → order <b>PREPARING</b> once both have happened.'],
  ['Driver assigned', 'Delivery Service consumes <code>payments.completed</code>, creates a delivery and claims a free driver → <code>delivery.assigned</code>.'],
  ['Food is ready', 'The restaurant marks the order <b>READY</b> (REST) → <code>orders.status_updated</code>.'],
  ['Pickup & delivery', 'The driver confirms pickup and delivery → <code>delivery.status_updated</code> → order <b>OUT_FOR_DELIVERY</b> then <b>DELIVERED</b>.'],
  ['Everyone is told', 'Notification Service alerts the customer (email + SMS), restaurant (dashboard + email) and driver (push + SMS); Admin Service builds platform statistics.'],
];

let root;
const $ = (id) => root.querySelector(`#${id}`);

export function mount(el) {
  root = el;
  delegate(root, handlers);
  root.innerHTML = `
    <div class="page-head">
      <div><h1>System</h1><p class="muted">Service health, the Kafka event flow, and the live event stream.</p></div>
      <button class="btn" data-action="seed">Load demo data</button>
    </div>
    <section style="margin-bottom:16px">
      <div id="s-services" class="services"></div>
    </section>
    <div class="grid cols-2">
      <section class="card"><h2>How an order flows</h2><div class="flow">${FLOW.map(([t, d]) => `<div class="flow-step"><div><h3>${t}</h3><p class="muted">${d}</p></div></div>`).join('')}</div></section>
      <section class="card">
        <div class="card-head"><h2>Live notifications</h2><small>every alert, to every audience</small></div>
        <div id="s-feed" class="feed"></div>
      </section>
    </div>`;
}

export async function refresh() {
  const results = await Promise.all(SERVICES.map((s) => api.health(s.key, s.health).then((h) => ({ ok: true, h }), (err) => ({ ok: false, err }))));
  patch($('s-services'), SERVICES.map((s, i) => {
    const r = results[i];
    const topics = r.ok && Array.isArray(r.h?.consumedTopics) ? r.h.consumedTopics : [];
    return `
      <div class="service">
        <div class="row between"><strong>${esc(s.name)}</strong>${pill(r.ok ? 'UP' : 'DOWN')}</div>
        <small class="muted">:${s.port}${s.owner ? ` · ${esc(s.owner)}` : ''}</small>
        ${r.ok ? (topics.length ? `<div class="topics">${topics.map((t) => `<span class="topic">${esc(t)}</span>`).join('')}</div>` : '')
          : `<small class="muted">${esc(r.err.message)}</small>`}
      </div>`;
  }).join(''));

  try {
    const events = await api.notifications.list({ limit: 40 });
    patch($('s-feed'), events.length ? events.map((n) => notificationItem(n, { showAudience: true })).join('')
      : empty('No events yet', 'Place an order and watch it flow through the services.'));
  } catch (err) {
    patch($('s-feed'), `<div class="banner">${esc(err.message)}</div>`);
  }
}

// Creates a restaurant with a menu, a customer with an address, and two drivers,
// then signs each role into the new records.
async function seedDemoData() {
  const restaurant = await api.restaurants.register({
    ownerId: 'owner-demo', name: 'Kapana Corner', description: 'Flame-grilled street food from Katutura',
    location: 'Katutura, Windhoek', hours: { openTime: '06:00', closeTime: '23:59' },
  });
  const dishes = [
    ['Kapana beef strips', 'Grilled on the open fire, with chilli salt and salsa', 45, 40],
    ['Vetkoek & mince', 'Golden fried dough with savoury mince', 30, 30],
    ['Oshifima & stew', 'Mahangu porridge with beef stew', 55, 25],
    ['Grilled boerewors roll', 'With caramelised onions', 38, 30],
    ['Rock shandy', 'Lemonade, soda and bitters', 22, 50],
  ];
  for (const [name, description, price, stockCount] of dishes) {
    await api.restaurants.addItem(restaurant.restaurantId, { name, description, price, stockCount });
  }

  const pizza = await api.restaurants.register({
    ownerId: 'owner-demo', name: 'Swakop Pizza Co.', description: 'Wood-fired pizza and coastal classics',
    location: 'Maerua Mall, Windhoek', hours: { openTime: '11:00', closeTime: '23:00' },
  });
  for (const [name, description, price, stockCount] of [
    ['Margherita', 'Tomato, mozzarella, basil', 89, 20],
    ['Oryx & cranberry', 'Smoked oryx with cranberry and feta', 129, 15],
    ['Garlic bread', 'With herb butter', 35, 30],
  ]) {
    await api.restaurants.addItem(pizza.restaurantId, { name, description, price, stockCount });
  }

  const customer = await api.customers.register({
    fullName: 'Ndapewa Shikongo', email: `ndapewa.${Date.now()}@example.com`, phone: '+264811234567',
  });
  await api.customers.addAddress(customer.customerId, {
    label: 'Home', street: '12 Independence Avenue', city: 'Windhoek', postalCode: '10005', country: 'Namibia', isDefault: true,
  });

  const driver = await api.drivers.register({ name: 'Tangeni Amupolo', phoneNumber: '0812345678', plateNumber: 'N 25648 W', vehicleType: 'Motorbike' });
  await api.drivers.register({ name: 'Johannes Nghipandulwa', phoneNumber: '0817654321', plateNumber: 'N 11873 W', vehicleType: 'Toyota Corolla' });

  saved.set('customerId', customer.customerId);
  saved.set('customerRestaurant', restaurant.restaurantId);
  saved.set('restaurantId', restaurant.restaurantId);
  saved.set('driverId', driver.driverId);
}

const handlers = {
  seed: (btn) => busy(btn, async () => {
    await seedDemoData();
    toast('Demo data loaded – you are signed in as the new customer, restaurant and driver', 'ok');
    location.hash = '#/customer';
  }),
};
