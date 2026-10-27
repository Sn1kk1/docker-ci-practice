// Загружаем записи из API и рисуем список.
async function loadItems() {
  const list = document.getElementById('items');
  const error = document.getElementById('error');
  try {
    const res = await fetch('/api/items');
    if (!res.ok) throw new Error(`HTTP ${res.status}: ${await res.text()}`);
    const items = await res.json();
    list.innerHTML = '';
    if (items.length === 0) {
      list.innerHTML = '<li class="muted">Пусто</li>';
      return;
    }
    for (const it of items) {
      const li = document.createElement('li');
      li.textContent = `#${it.id} — ${it.name}`;
      list.appendChild(li);
    }
  } catch (e) {
    list.innerHTML = '';
    error.hidden = false;
    error.textContent = `Не удалось загрузить данные: ${e.message}`;
  }
}

loadItems();
