const API = 'http://localhost:8000/api';

// ── State ──────────────────────────────────────────────
let state = { expenses: [], categories: [], charts: {} };

// ── API helpers ────────────────────────────────────────
async function apiFetch(path, opts = {}) {
  const res = await fetch(API + path, {
    headers: { 'Content-Type': 'application/json' },
    ...opts,
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.detail || 'Request failed');
  }
  if (res.status === 204) return null;
  return res.json();
}

const api = {
  getCategories: () => apiFetch('/categories/'),
  getExpenses: (params = {}) => apiFetch('/expenses/?' + new URLSearchParams(params)),
  getSummary: (params = {}) => apiFetch('/expenses/summary?' + new URLSearchParams(params)),
  createExpense: (body) => apiFetch('/expenses/', { method: 'POST', body: JSON.stringify(body) }),
  updateExpense: (id, body) => apiFetch(`/expenses/${id}`, { method: 'PUT', body: JSON.stringify(body) }),
  deleteExpense: (id) => apiFetch(`/expenses/${id}`, { method: 'DELETE' }),
};

// ── Toast ──────────────────────────────────────────────
function toast(msg, type = 'success') {
  const el = document.getElementById('toast');
  el.textContent = msg;
  el.className = `show ${type}`;
  clearTimeout(el._t);
  el._t = setTimeout(() => { el.className = ''; }, 3000);
}

// ── Navigation ─────────────────────────────────────────
function navigate(page) {
  document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
  document.querySelectorAll('.nav-btn').forEach(b => b.classList.remove('active'));
  document.getElementById(`page-${page}`).classList.add('active');
  document.getElementById(`nav-${page}`).classList.add('active');
  if (page === 'dashboard') loadDashboard();
  if (page === 'expenses') loadExpenses();
}

// ── Categories ─────────────────────────────────────────
async function loadCategories() {
  state.categories = await api.getCategories();
  const sel = document.getElementById('exp-category');
  const filterSel = document.getElementById('filter-category');
  [sel, filterSel].forEach(s => {
    if (!s) return;
    const placeholder = s.querySelector('option[value=""]');
    s.innerHTML = '';
    if (placeholder) s.appendChild(placeholder);
    state.categories.forEach(c => {
      const o = document.createElement('option');
      o.value = c.id;
      o.textContent = c.name;
      s.appendChild(o);
    });
  });
}

function getCategoryBadge(cat) {
  return `<span class="badge" style="background:${cat.color}22;color:${cat.color}">
    <span class="badge-dot" style="background:${cat.color}"></span>${cat.name}
  </span>`;
}

// ── Dashboard ──────────────────────────────────────────
async function loadDashboard() {
  const now = new Date();
  const firstDay = new Date(now.getFullYear(), now.getMonth(), 1).toISOString().slice(0, 10);
  const lastDay = new Date(now.getFullYear(), now.getMonth() + 1, 0).toISOString().slice(0, 10);

  const [summaryAll, summaryMonth] = await Promise.all([
    api.getSummary(),
    api.getSummary({ start_date: firstDay, end_date: lastDay }),
  ]);

  document.getElementById('stat-total').textContent = fmt(summaryAll.total);
  document.getElementById('stat-count').textContent = summaryAll.count;
  document.getElementById('stat-month').textContent = fmt(summaryMonth.total);
  document.getElementById('stat-month-count').textContent = `${summaryMonth.count} this month`;

  renderCategoryBars(summaryAll.by_category, summaryAll.total);
  renderPieChart(summaryAll.by_category);
  renderLineChart(summaryAll.monthly_totals);
}

function fmt(n) {
  return '$' + Number(n).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function renderCategoryBars(data, total) {
  const el = document.getElementById('category-bars');
  if (!data.length) { el.innerHTML = '<p style="color:var(--muted);font-size:.85rem">No data yet.</p>'; return; }
  el.innerHTML = data.map(c => `
    <div class="cat-bar-row">
      <div class="cat-name" title="${c.name}">${c.name}</div>
      <div class="cat-bar-track">
        <div class="cat-bar-fill" style="width:${total ? (c.total/total*100).toFixed(1) : 0}%;background:${c.color}"></div>
      </div>
      <div class="cat-bar-amt">${fmt(c.total)}</div>
    </div>
  `).join('');
}

function renderPieChart(data) {
  const ctx = document.getElementById('pie-chart').getContext('2d');
  if (state.charts.pie) state.charts.pie.destroy();
  if (!data.length) return;
  state.charts.pie = new Chart(ctx, {
    type: 'doughnut',
    data: {
      labels: data.map(d => d.name),
      datasets: [{ data: data.map(d => d.total), backgroundColor: data.map(d => d.color), borderWidth: 2, borderColor: '#1e293b' }],
    },
    options: {
      plugins: { legend: { labels: { color: '#94a3b8', font: { size: 12 } } } },
      cutout: '65%',
    },
  });
}

function renderLineChart(monthly) {
  const ctx = document.getElementById('line-chart').getContext('2d');
  if (state.charts.line) state.charts.line.destroy();
  if (!monthly.length) return;
  const labels = monthly.map(m => {
    const d = new Date(m.year, m.month - 1);
    return d.toLocaleString('en-US', { month: 'short', year: '2-digit' });
  });
  state.charts.line = new Chart(ctx, {
    type: 'bar',
    data: {
      labels,
      datasets: [{
        label: 'Monthly Spending',
        data: monthly.map(m => m.total),
        backgroundColor: '#6366f155',
        borderColor: '#6366f1',
        borderWidth: 2,
        borderRadius: 6,
      }],
    },
    options: {
      plugins: { legend: { display: false } },
      scales: {
        x: { ticks: { color: '#94a3b8' }, grid: { color: '#334155' } },
        y: { ticks: { color: '#94a3b8', callback: v => '$' + v }, grid: { color: '#334155' } },
      },
    },
  });
}

// ── Expenses list ──────────────────────────────────────
async function loadExpenses(params = {}) {
  const tbody = document.getElementById('expenses-tbody');
  tbody.innerHTML = '<tr><td colspan="5" class="empty-state">Loading…</td></tr>';
  try {
    state.expenses = await api.getExpenses(params);
    renderExpensesTable();
  } catch (e) {
    tbody.innerHTML = `<tr><td colspan="5" class="empty-state">${e.message}</td></tr>`;
  }
}

function renderExpensesTable() {
  const tbody = document.getElementById('expenses-tbody');
  if (!state.expenses.length) {
    tbody.innerHTML = '<tr><td colspan="5" class="empty-state"><div class="icon">💸</div>No expenses yet. Add one!</td></tr>';
    return;
  }
  tbody.innerHTML = state.expenses.map(e => `
    <tr>
      <td>${new Date(e.date + 'T00:00:00').toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })}</td>
      <td>
        <div style="font-weight:500">${escHtml(e.title)}</div>
        ${e.description ? `<div style="font-size:.8rem;color:var(--muted)">${escHtml(e.description)}</div>` : ''}
      </td>
      <td>${getCategoryBadge(e.category)}</td>
      <td class="amount-cell">${fmt(e.amount)}</td>
      <td>
        <div style="display:flex;gap:6px">
          <button class="btn btn-ghost btn-sm" onclick="openEditModal(${e.id})">✏️ Edit</button>
          <button class="btn btn-danger btn-sm" onclick="confirmDelete(${e.id})">Delete</button>
        </div>
      </td>
    </tr>
  `).join('');
}

function escHtml(s) {
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

// ── Filters ────────────────────────────────────────────
function applyFilters() {
  const params = {};
  const cat = document.getElementById('filter-category').value;
  const start = document.getElementById('filter-start').value;
  const end = document.getElementById('filter-end').value;
  if (cat) params.category_id = cat;
  if (start) params.start_date = start;
  if (end) params.end_date = end;
  loadExpenses(params);
}

function clearFilters() {
  document.getElementById('filter-category').value = '';
  document.getElementById('filter-start').value = '';
  document.getElementById('filter-end').value = '';
  loadExpenses();
}

// ── Add/Edit Modal ─────────────────────────────────────
let editingId = null;

function openAddModal() {
  editingId = null;
  document.getElementById('modal-title').textContent = 'Add Expense';
  document.getElementById('expense-form').reset();
  document.getElementById('exp-date').value = new Date().toISOString().slice(0, 10);
  document.getElementById('expense-modal').classList.add('open');
}

async function openEditModal(id) {
  editingId = id;
  const expense = state.expenses.find(e => e.id === id);
  if (!expense) return;
  document.getElementById('modal-title').textContent = 'Edit Expense';
  document.getElementById('exp-title').value = expense.title;
  document.getElementById('exp-amount').value = expense.amount;
  document.getElementById('exp-date').value = expense.date;
  document.getElementById('exp-category').value = expense.category_id;
  document.getElementById('exp-description').value = expense.description || '';
  document.getElementById('expense-modal').classList.add('open');
}

function closeModal() {
  document.getElementById('expense-modal').classList.remove('open');
}

async function saveExpense(e) {
  e.preventDefault();
  const body = {
    title: document.getElementById('exp-title').value.trim(),
    amount: parseFloat(document.getElementById('exp-amount').value),
    date: document.getElementById('exp-date').value,
    category_id: parseInt(document.getElementById('exp-category').value),
    description: document.getElementById('exp-description').value.trim() || null,
  };
  try {
    if (editingId) {
      await api.updateExpense(editingId, body);
      toast('Expense updated');
    } else {
      await api.createExpense(body);
      toast('Expense added');
    }
    closeModal();
    loadExpenses();
    if (document.getElementById('page-dashboard').classList.contains('active')) loadDashboard();
  } catch (err) {
    toast(err.message, 'error');
  }
}

// ── Delete ─────────────────────────────────────────────
let deleteId = null;

function confirmDelete(id) {
  deleteId = id;
  document.getElementById('confirm-modal').classList.add('open');
}

function closeConfirm() {
  document.getElementById('confirm-modal').classList.remove('open');
}

async function executeDelete() {
  try {
    await api.deleteExpense(deleteId);
    toast('Expense deleted');
    closeConfirm();
    loadExpenses();
    if (document.getElementById('page-dashboard').classList.contains('active')) loadDashboard();
  } catch (err) {
    toast(err.message, 'error');
  }
}

// ── Init ───────────────────────────────────────────────
async function init() {
  await loadCategories();
  navigate('dashboard');
}

document.addEventListener('DOMContentLoaded', init);
