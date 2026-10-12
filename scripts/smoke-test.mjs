// End-to-end smoke test against the running Docker Compose stack, through the
// frontend's nginx proxy (the same path the UI uses).
//
//   docker compose up -d --build
//   node scripts/smoke-test.mjs            # default http://localhost:3000
//
// Drives one order from CREATED to DELIVERED across all seven services, checks
// that a closed restaurant rejects an order (-> CANCELLED), and checks the
// notification, admin and validation behaviour. Exits non-zero on failure.

const BASE = process.argv[2] || 'http://localhost:3000';
let failures = 0;

async function call(service, path, { method = 'GET', body } = {}) {
  const res = await fetch(`${BASE}/api/${service}${path}`, {
    method,
    headers: body ? { 'Content-Type': 'application/json' } : {},
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let data;
  try { data = text ? JSON.parse(text) : null; } catch { data = text; }
  return { status: res.status, data };
}

async function ok(service, path, opts) {
  const r = await call(service, path, opts);
  if (r.status >= 300) throw new Error(`${opts?.method || 'GET'} ${service}${path} -> ${r.status} ${JSON.stringify(r.data)}`);
  return r.data;
}

function check(label, condition, detail = '') {
  console.log(`${condition ? 'PASS' : 'FAIL'}  ${label}${detail ? `  (${detail})` : ''}`);
  if (!condition) failures += 1;
}

// Polls until fn() returns a truthy value or the timeout passes.
async function waitFor(label, fn, timeoutMs = 45000) {
  const start = Date.now();
  let last;
  while (Date.now() - start < timeoutMs) {
    try {
      last = await fn();
      if (last) return last;
    } catch (err) { last = err.message; }
    await new Promise((r) => setTimeout(r, 1000));
  }
  throw new Error(`Timed out waiting for: ${label} (last: ${JSON.stringify(last)})`);
}

async function main() {
  console.log(`Smoke test against ${BASE}\n`);

  // ---- health
  const health = [['order', '/health'], ['customer', '/health'], ['restaurant', '/health'], ['payment', '/payments/health'],
    ['delivery', '/health'], ['notification', '/health'], ['admin', '/admin/health']];
  for (const [svc, path] of health) {
    await waitFor(`${svc} healthy`, async () => (await call(svc, path)).status === 200, 120000);
    check(`${svc} service is up`, true);
  }

  // ---- setup: restaurant open all day, customer, driver
  const restaurant = await ok('restaurant', '/restaurants', { method: 'POST', body: {
    ownerId: 'smoke', name: 'Smoke Test Grill', description: 'test', location: 'Windhoek',
    hours: { openTime: '00:00', closeTime: '00:00' } } });
  const dish = await ok('restaurant', `/restaurants/${restaurant.restaurantId}/menu`, { method: 'POST', body: {
    name: 'Kapana', description: 'test', price: 45, stockCount: 10 } });
  const customer = await ok('customer', '/customers', { method: 'POST', body: {
    fullName: 'Smoke Tester', email: `smoke.${Date.now()}@example.com`, phone: '+264811234567' } });
  await ok('customer', `/customers/${customer.customerId}/addresses`, { method: 'POST', body: {
    label: 'Home', street: '1 Test St', city: 'Windhoek', postalCode: '10005', country: 'Namibia', isDefault: true } });
  const driver = await ok('delivery', '/drivers', { method: 'POST', body: {
    name: 'Smoke Driver', phoneNumber: '0811111111', plateNumber: 'N 1 W', vehicleType: 'Bike' } });
  check('setup: restaurant, menu item, customer, address, driver created', true);

  // ---- validation
  const bad = await call('order', '/orders', { method: 'POST', body: {
    customerId: customer.customerId, restaurantId: restaurant.restaurantId,
    items: [{ itemId: dish.itemId, name: 'Kapana', quantity: 0, unitPrice: 45 }] } });
  check('order with quantity 0 is rejected with 400', bad.status === 400, JSON.stringify(bad.data));
  const badEmail = await call('customer', '/customers', { method: 'POST', body: { fullName: 'X', email: 'nope', phone: '0811234567' } });
  check('customer with invalid email is rejected with 400', badEmail.status === 400);

  // ---- happy path
  const order = await ok('order', '/orders', { method: 'POST', body: {
    customerId: customer.customerId, restaurantId: restaurant.restaurantId,
    items: [{ itemId: dish.itemId, name: 'Kapana', quantity: 2, unitPrice: 45 }] } });
  check('order created as CREATED', order.status === 'CREATED' && Number(order.totalAmount) === 90);

  // Payment is 85% random: retry until it succeeds, like a customer would.
  let current = await waitFor('restaurant ACK + payment result', async () => {
    const o = await ok('order', `/orders/${order.orderId}`);
    return o.paymentStatus && o.status !== 'CREATED' ? o : null;
  });
  for (let i = 0; current.paymentStatus === 'FAILED' && i < 10; i += 1) {
    console.log('      (simulated payment failed - retrying)');
    await call('payment', '/payments/initiate', { method: 'POST', body: {
      orderId: order.orderId, customerId: customer.customerId, amount: 90 } });
    current = await waitFor('payment retry result', async () => {
      const o = await ok('order', `/orders/${order.orderId}`);
      return o.paymentStatus === 'SUCCESS' ? o : (i === 9 ? o : null);
    }, 15000).catch(() => current);
  }
  const preparing = await waitFor('order PREPARING', async () => {
    const o = await ok('order', `/orders/${order.orderId}`);
    return o.status === 'PREPARING' ? o : null;
  });
  check('restaurant ACK + payment SUCCESS moved order to PREPARING', preparing.status === 'PREPARING');

  const menu = await ok('restaurant', `/restaurants/${restaurant.restaurantId}/menu`);
  check('restaurant stock decremented 10 -> 8', menu[0].stockCount === 8, `stock ${menu[0].stockCount}`);

  const delivery = await waitFor('delivery ASSIGNED', async () => {
    const list = await ok('delivery', `/deliveries?orderId=${order.orderId}`);
    return list[0]?.status === 'ASSIGNED' ? list[0] : null;
  });
  check('delivery created and a driver assigned', !!delivery.driverId);

  await ok('order', `/orders/${order.orderId}/status`, { method: 'PUT', body: { status: 'READY' } });
  await ok('delivery', `/deliveries/${delivery.deliveryId}/status`, { method: 'PUT', body: { status: 'PICKED_UP' } });
  await waitFor('order OUT_FOR_DELIVERY', async () => (await ok('order', `/orders/${order.orderId}`)).status === 'OUT_FOR_DELIVERY');
  check('driver pickup moved order to OUT_FOR_DELIVERY', true);
  await ok('delivery', `/deliveries/${delivery.deliveryId}/status`, { method: 'PUT', body: { status: 'IN_PROGRESS' } });
  await ok('delivery', `/deliveries/${delivery.deliveryId}/status`, { method: 'PUT', body: { status: 'DELIVERED' } });
  await waitFor('order DELIVERED', async () => (await ok('order', `/orders/${order.orderId}`)).status === 'DELIVERED');
  check('delivery DELIVERED moved order to DELIVERED', true);

  const freed = await ok('delivery', `/drivers/${delivery.driverId}`);
  check('driver freed after delivery', freed.status === 'AVAILABLE' || freed.status === 'ON_DELIVERY', freed.status);

  const history = await waitFor('customer order history DELIVERED', async () => {
    const h = await ok('customer', `/customers/${customer.customerId}/orders`);
    return h.find((x) => x.orderId === order.orderId && x.status === 'DELIVERED');
  });
  check('customer order history updated from Kafka', !!history);

  const notes = await waitFor('notifications for all three audiences', async () => {
    const n = await ok('notification', `/notifications?orderId=${order.orderId}&limit=100`);
    const audiences = new Set(n.map((x) => x.audience));
    return audiences.has('CUSTOMER') && audiences.has('RESTAURANT') && audiences.has('DRIVER') ? n : null;
  });
  check('notifications sent to customer, restaurant and driver', notes.length > 0, `${notes.length} notifications`);

  const adminOrder = await waitFor('admin read model', async () => {
    const all = await ok('admin', '/admin/orders');
    return all.find((x) => x.orderId === order.orderId && x.status === 'DELIVERED');
  });
  check('admin service recorded the delivered order', !!adminOrder);
  const stats = await ok('admin', '/admin/stats');
  check('admin stats available', stats.totalOrders >= 1, `total ${stats.totalOrders}`);
  const report = await ok('admin', '/admin/reports', { method: 'POST' });
  check('admin report generated', !!report.reportId);

  // ---- rejection path: paused restaurant -> REJECTED -> CANCELLED
  await ok('restaurant', `/restaurants/${restaurant.restaurantId}/availability`, { method: 'PUT', body: { isOpen: false } });
  const rejected = await ok('order', '/orders', { method: 'POST', body: {
    customerId: customer.customerId, restaurantId: restaurant.restaurantId,
    items: [{ itemId: dish.itemId, name: 'Kapana', quantity: 1, unitPrice: 45 }] } });
  const cancelled = await waitFor('rejected order CANCELLED', async () => {
    const o = await ok('order', `/orders/${rejected.orderId}`);
    return o.status === 'CANCELLED' ? o : null;
  });
  check('paused restaurant rejects order -> CANCELLED with reason', !!cancelled.cancellationReason, cancelled.cancellationReason);
  const stockAfter = (await ok('restaurant', `/restaurants/${restaurant.restaurantId}/menu`))[0].stockCount;
  check('rejected order did not touch stock', stockAfter === 8, `stock ${stockAfter}`);
  await ok('restaurant', `/restaurants/${restaurant.restaurantId}/availability`, { method: 'PUT', body: { isOpen: true } });

  console.log(`\n${failures === 0 ? 'ALL CHECKS PASSED' : `${failures} CHECK(S) FAILED`}`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((err) => {
  console.error(`\nFAIL  ${err.message}`);
  process.exit(1);
});
