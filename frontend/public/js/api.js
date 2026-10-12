// Thin client for the platform's REST APIs. Every call goes through the nginx
// proxy at /api/<service>/..., which forwards it to that service's container.

export class ApiError extends Error {
  constructor(message, status) {
    super(message);
    this.status = status;
  }
}

async function request(service, path, { method = 'GET', body, query } = {}) {
  let url = `/api/${service}${path}`;
  if (query) {
    const params = new URLSearchParams();
    for (const [k, v] of Object.entries(query)) if (v !== undefined && v !== null && v !== '') params.set(k, v);
    const qs = params.toString();
    if (qs) url += `?${qs}`;
  }
  let res;
  try {
    res = await fetch(url, {
      method,
      headers: body === undefined ? {} : { 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
  } catch {
    throw new ApiError(`Could not reach the ${service} service`, 0);
  }
  const text = await res.text();
  let data = null;
  if (text) {
    try { data = JSON.parse(text); } catch { data = text; }
  }
  if (!res.ok) {
    const message = (data && typeof data === 'object' && data.message) || `${service} service: ${res.status} ${res.statusText}`;
    throw new ApiError(message, res.status);
  }
  return data;
}

const enc = encodeURIComponent;

export const api = {
  customers: {
    list: () => request('customer', '/customers'),
    get: (id) => request('customer', `/customers/${enc(id)}`),
    register: (body) => request('customer', '/customers', { method: 'POST', body }),
    addAddress: (id, body) => request('customer', `/customers/${enc(id)}/addresses`, { method: 'POST', body }),
    deleteAddress: (id, addressId) =>
      request('customer', `/customers/${enc(id)}/addresses/${enc(addressId)}`, { method: 'DELETE' }),
  },
  restaurants: {
    list: () => request('restaurant', '/restaurants'),
    get: (id) => request('restaurant', `/restaurants/${enc(id)}`),
    register: (body) => request('restaurant', '/restaurants', { method: 'POST', body }),
    menu: (id) => request('restaurant', `/restaurants/${enc(id)}/menu`),
    setOpen: (id, isOpen) => request('restaurant', `/restaurants/${enc(id)}/availability`, { method: 'PUT', body: { isOpen } }),
    addItem: (id, body) => request('restaurant', `/restaurants/${enc(id)}/menu`, { method: 'POST', body }),
    updateItem: (id, itemId, body) =>
      request('restaurant', `/restaurants/${enc(id)}/menu/${enc(itemId)}`, { method: 'PUT', body }),
    deleteItem: (id, itemId) =>
      request('restaurant', `/restaurants/${enc(id)}/menu/${enc(itemId)}`, { method: 'DELETE' }),
  },
  orders: {
    list: (query) => request('order', '/orders', { query }),
    get: (id) => request('order', `/orders/${enc(id)}`),
    create: (body) => request('order', '/orders', { method: 'POST', body }),
    setStatus: (id, status) => request('order', `/orders/${enc(id)}/status`, { method: 'PUT', body: { status } }),
  },
  payments: {
    byOrder: (orderId) => request('payment', `/payments/byOrder/${enc(orderId)}`),
    initiate: (body) => request('payment', '/payments/initiate', { method: 'POST', body }),
  },
  drivers: {
    list: () => request('delivery', '/drivers'),
    get: (id) => request('delivery', `/drivers/${enc(id)}`),
    register: (body) => request('delivery', '/drivers', { method: 'POST', body }),
    setStatus: (id, status) => request('delivery', `/drivers/${enc(id)}/status`, { method: 'PUT', body: { status } }),
  },
  deliveries: {
    list: (query) => request('delivery', '/deliveries', { query }),
    assign: (id) => request('delivery', `/deliveries/${enc(id)}/assign`, { method: 'POST' }),
    setStatus: (id, status) => request('delivery', `/deliveries/${enc(id)}/status`, { method: 'PUT', body: { status } }),
  },
  notifications: {
    list: (query) => request('notification', '/notifications', { query }),
  },
  admin: {
    stats: () => request('admin', '/admin/stats'),
    orders: () => request('admin', '/admin/orders'),
    reports: () => request('admin', '/admin/reports'),
    generateReport: () => request('admin', '/admin/reports', { method: 'POST' }),
  },
  health: (service, path) => request(service, path),
};
