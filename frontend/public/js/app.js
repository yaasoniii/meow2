import * as customer from './views/customer.js';
import * as restaurant from './views/restaurant.js';
import * as driver from './views/driver.js';
import * as admin from './views/admin.js';
import * as system from './views/system.js';

// Each view exports mount(root) and refresh(). refresh() is polled while the
// view is open, which is how order progress driven by Kafka events shows up
// live without reloading.
const views = { customer, restaurant, driver, admin, system };
const POLL_MS = 2500;

const app = document.getElementById('app');
let current = null;
let refreshing = false;

async function refresh() {
  if (!current || refreshing || document.hidden) return;
  refreshing = true;
  try {
    await current.refresh();
  } catch (err) {
    console.warn('refresh failed', err);
  } finally {
    refreshing = false;
  }
}

function route() {
  const name = location.hash.replace(/^#\/?/, '') || 'customer';
  const view = views[name] ? name : 'customer';
  document.querySelectorAll('.roles a').forEach((a) => a.classList.toggle('active', a.dataset.view === view));

  // A fresh root per view, so listeners delegated by the old view go with it.
  const root = document.createElement('div');
  app.replaceChildren(root);
  current = views[view];
  current.mount(root);
  refresh();
}

window.addEventListener('hashchange', route);
document.addEventListener('visibilitychange', refresh);
setInterval(refresh, POLL_MS);

// Lets a view ask for an immediate refresh after it changed something.
window.addEventListener('kapana:refresh', refresh);

route();
