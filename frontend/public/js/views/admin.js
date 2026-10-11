import { api } from '../api.js';
import { LABEL, ORDER_STEPS, busy, delegate, empty, esc, money, patch, pill, shortId, timeAgo, toast } from '../ui.js';

let root;
const $ = (id) => root.querySelector(`#${id}`);
const refreshNow = () => window.dispatchEvent(new Event('kapana:refresh'));

export function mount(el) {
  root = el;
  delegate(root, handlers);
  root.innerHTML = `
    <div class="page-head">
      <div><h1>Platform overview</h1><p class="muted">Live figures from the Admin Service, assembled from every service's Kafka events.</p></div>
      <button class="btn" data-action="report">Generate report</button>
    </div>
    <div id="a-error"></div>
    <div id="a-kpis" class="kpis"></div>
    <div class="grid split">
      <section class="card">
        <div class="card-head"><h2>All orders</h2><small id="a-count"></small></div>
        <div id="a-orders" class="table-wrap"></div>
      </section>
      <div class="stack">
        <section class="card"><h2>Orders by status</h2><div id="a-bars" class="bars"></div></section>
        <section class="card"><h2>Saved reports</h2><div id="a-reports" class="list"></div></section>
      </div>
    </div>`;
}

export async function refresh() {
  try {
    const [stats, orders, reports] = await Promise.all([api.admin.stats(), api.admin.orders(), api.admin.reports()]);
    patch($('a-error'), '');
    renderKpis(stats);
    renderBars(stats);
    renderOrders(orders);
    renderReports(reports);
  } catch (err) {
    patch($('a-error'), `<div class="banner" style="margin-bottom:16px">${esc(err.message)}</div>`);
  }
}

function renderKpis(s) {
  const paid = s.paymentsSucceeded + s.paymentsFailed;
  const rate = paid ? Math.round((s.paymentsSucceeded / paid) * 100) : null;
  const kpi = (label, value, sub = '') =>
    `<div class="kpi"><div class="label">${esc(label)}</div><div class="value">${value}</div>${sub ? `<div class="sub">${sub}</div>` : ''}</div>`;
  patch($('a-kpis'), [
    kpi('Total orders', s.totalOrders, `${s.activeOrders} in progress`),
    kpi('Delivered revenue', money(s.deliveredRevenue), `avg order ${money(s.averageOrderValue)}`),
    kpi('Payment success', rate === null ? '–' : `${rate}%`, `${s.paymentsSucceeded} paid · ${s.paymentsFailed} failed`),
    kpi('Deliveries completed', s.completedDeliveries, `${s.driversAssigned} drivers assigned`),
    kpi('Avg delivery time', s.averageDeliveryMinutes == null ? '–' : `${Number(s.averageDeliveryMinutes).toFixed(1)} min`, 'order placed → delivered'),
  ].join(''));
}

function renderBars(s) {
  const statuses = [...ORDER_STEPS, 'CANCELLED', ...Object.keys(s.ordersByStatus).filter((k) => ![...ORDER_STEPS, 'CANCELLED'].includes(k))];
  const max = Math.max(1, ...Object.values(s.ordersByStatus));
  patch($('a-bars'), s.totalOrders ? statuses.map((st) => {
    const n = s.ordersByStatus[st] || 0;
    return `
      <div class="bar-row" title="${esc(LABEL[st] || st)}: ${n} order${n === 1 ? '' : 's'}">
        <span>${esc(LABEL[st] || st)}</span>
        <span class="bar-track"><span class="bar-fill" style="width:${(n / max) * 100}%"></span></span>
        <span class="n">${n}</span>
      </div>`;
  }).join('') : empty('No orders yet'));
}

function renderOrders(orders) {
  patch($('a-count'), `${orders.length} order${orders.length === 1 ? '' : 's'}`);
  patch($('a-orders'), orders.length ? `
    <table>
      <thead><tr><th>Order</th><th>Placed</th><th>Status</th><th>Payment</th><th>Driver</th><th class="num">Total</th></tr></thead>
      <tbody>${orders.slice(0, 50).map((o) => `
        <tr>
          <td><code>${esc(shortId(o.orderId))}</code></td>
          <td>${timeAgo(o.createdAt)}</td>
          <td>${pill(o.status || 'UNKNOWN')}</td>
          <td>${o.paymentStatus ? pill(o.paymentStatus) : '<span class="muted">–</span>'}</td>
          <td>${o.driverId ? `<code>${esc(shortId(o.driverId))}</code>` : '<span class="muted">–</span>'}</td>
          <td class="num">${o.totalAmount == null ? '–' : money(o.totalAmount)}</td>
        </tr>`).join('')}
      </tbody>
    </table>` : empty('No orders yet', 'Place an order from the Customer tab.'));
}

function renderReports(reports) {
  const sorted = [...reports].sort((a, b) => b.generatedAt.localeCompare(a.generatedAt)).slice(0, 6);
  patch($('a-reports'), sorted.length ? sorted.map((r) => {
    const top = r.restaurants[0];
    return `
      <details class="list-item" style="display:block">
        <summary style="cursor:pointer"><strong>${new Date(r.generatedAt).toLocaleString()}</strong>
          <small class="muted"> · ${r.cancellations.totalOrders} orders · ${r.cancellations.cancellationRate}% cancelled</small></summary>
        <div class="stack" style="margin-top:10px;font-size:.88rem">
          <div>Deliveries: <strong>${r.deliveries.completedDeliveries}</strong>
            ${r.deliveries.averageMinutes == null ? '' : ` · avg ${r.deliveries.averageMinutes} min (fastest ${r.deliveries.fastestMinutes}, slowest ${r.deliveries.slowestMinutes})`}</div>
          ${top ? `<div>Busiest restaurant: <code>${esc(shortId(top.restaurantId))}</code> – ${top.totalOrders} orders, ${money(top.revenue)} revenue</div>` : ''}
        </div>
      </details>`;
  }).join('') : empty('No reports yet', 'Generate one to snapshot the current figures.'));
}

const handlers = {
  report: (btn) => busy(btn, async () => {
    await api.admin.generateReport();
    toast('Report generated', 'ok');
    refreshNow();
  }),
};
