const $ = (id) => document.getElementById(id);

const els = {
  indexCount: $('indexCount'),
  indexTime: $('indexTime'),
  scanBtn: $('scanBtn'),
  scanBtnLabel: $('scanBtn').querySelector('.btn-label'),
  scanHint: $('scanHint'),
  monitorBadge: $('monitorBadge'),
  monitorText: $('monitorText'),
  monitorToggle: $('monitorToggle'),
  pathList: $('pathList'),
  privacyNote: $('privacyNote'),
  kwInput: $('kwInput'),
  typeSelect: $('typeSelect'),
  sinceSelect: $('sinceSelect'),
  searchBtn: $('searchBtn'),
  searchMeta: $('searchMeta'),
  groupActions: $('groupActions'),
  expandAllBtn: $('expandAllBtn'),
  collapseAllBtn: $('collapseAllBtn'),
  results: $('results'),
  emptyState: $('emptyState'),
  refreshBtn: $('refreshBtn'),
  quitBtn: $('quitBtn'),
  themeBtn: $('themeBtn'),
  addPathBtn: $('addPathBtn'),
  addModal: $('addModal'),
  modalClose: $('modalClose'),
  suggestKw: $('suggestKw'),
  suggestBtn: $('suggestBtn'),
  suggestList: $('suggestList'),
  browsePath: $('browsePath'),
  browseUp: $('browseUp'),
  browseAdd: $('browseAdd'),
  browseList: $('browseList'),
  toast: $('toast'),
};

function applyTheme(theme) {
  document.body.dataset.theme = theme;
  els.themeBtn.textContent = theme === 'dark' ? '☀️' : '🌙';
  els.themeBtn.title = theme === 'dark' ? '切换到普通模式' : '切换到暗色模式';
  try { localStorage.setItem('mf-theme', theme); } catch (e) {}
}
applyTheme(localStorage.getItem('mf-theme') || 'light');
els.themeBtn.addEventListener('click', () => {
  applyTheme(document.body.dataset.theme === 'dark' ? 'light' : 'dark');
});

let toastTimer = null;
let currentGroups = [];
let currentIndexMode = 'ps';
function toast(msg, isErr = false) {
  els.toast.textContent = msg;
  els.toast.classList.toggle('err', isErr);
  els.toast.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => els.toast.classList.remove('show'), 2600);
}

async function api(path, body) {
  const opt = body !== undefined
    ? { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }
    : {};
  const res = await fetch(path, opt);
  if (!res.ok) throw new Error('请求失败: HTTP ' + res.status);
  return res.json();
}

function fmtSize(bytes) {
  if (bytes == null) return '-';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let i = 0, n = bytes;
  while (n >= 1024 && i < units.length - 1) { n /= 1024; i++; }
  return (i === 0 ? n : n.toFixed(1)) + ' ' + units[i];
}

function fmtTime(iso) {
  if (!iso) return '-';
  const d = new Date(iso);
  const now = Date.now();
  const diff = now - d.getTime();
  if (diff < 60 * 1000) return '刚刚';
  if (diff < 60 * 60 * 1000) return Math.floor(diff / 60000) + ' 分钟前';
  if (diff < 24 * 60 * 60 * 1000) return Math.floor(diff / 3600000) + ' 小时前';
  const pad = (x) => String(x).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function setMonitorUI(state, indexMode) {
  if (indexMode === 'everything') {
    els.monitorBadge.textContent = '⚡ 实时索引';
    els.monitorBadge.className = 'badge badge-live';
    els.monitorText.textContent = 'Everything 实时索引已启用';
    els.monitorToggle.checked = true;
    els.monitorToggle.disabled = true;
    $('monitorCardTitle').textContent = '⚡ 实时索引';
    $('monitorHint').textContent = '基于 Everything 的 USN 日志实时追踪，文件新增 / 删除 / 重命名即时可见，无需手动刷新';
    return;
  }
  els.monitorToggle.disabled = false;
  const running = state && state.running;
  els.monitorToggle.checked = !!running;
  els.monitorText.textContent = running ? '● 自动刷新中' : '○ 已关闭';
  els.monitorBadge.textContent = running ? '自动刷新开启' : '自动刷新关闭';
  els.monitorBadge.className = 'badge ' + (running ? 'badge-on' : 'badge-off');
  $('monitorCardTitle').textContent = '🔄 自动刷新';
  $('monitorHint').textContent = '开启后每几秒自动检查监控目录中的新文件并收录（低功耗）';
}

async function fetchStatus(silent) {
  try {
    const s = await api('/api/status');
    currentIndexMode = s.indexMode || 'ps';
    els.indexCount.textContent = (s.index && s.index.count != null) ? s.index.count : 0;
    els.indexTime.textContent = (s.index && s.index.live) ? '实时更新' : fmtTime(s.index && s.index.modified);
    setMonitorUI(s.monitor, currentIndexMode);
    renderPaths(s.watchPaths || []);
    renderPrivacyDirs(s.privacyDirs || []);
    return s;
  } catch (e) {
    if (!silent) toast('无法连接服务器', true);
    return null;
  }
}

function renderPaths(paths) {
  els.pathList.innerHTML = '';
  paths.forEach((p) => {
    const li = document.createElement('li');
    li.className = 'path-item';
    const text = document.createElement('span');
    text.className = 'path-text';
    text.textContent = p;
    text.title = p + '（点击展开/收起完整路径）';
    text.addEventListener('click', (e) => e.currentTarget.classList.toggle('expanded'));
    li.appendChild(text);
    const del = document.createElement('button');
    del.className = 'path-del';
    del.title = '移除该目录';
    del.textContent = '✕';
    del.addEventListener('click', () => removePath(p));
    li.appendChild(del);
    els.pathList.appendChild(li);
  });
  if (!paths.length) {
    const li = document.createElement('li');
    li.textContent = '(未配置目录)';
    els.pathList.appendChild(li);
  }
}

async function doScan() {
  els.scanBtn.disabled = true;
  els.scanBtnLabel.innerHTML = '<span class="spinner"></span>扫描中…';
  els.scanHint.textContent = '正在扫描配置目录…';
  try {
    const r = await api('/api/scan', {});
    els.scanHint.textContent = r.message || ('完成: ' + r.count + ' 个文件');
    toast('扫描完成，共 ' + r.count + ' 个媒体文件');
    fetchStatus(true);
  } catch (e) {
    els.scanHint.textContent = '扫描失败';
    toast('扫描失败: ' + e.message, true);
  } finally {
    els.scanBtnLabel.textContent = '⟳ 重新扫描';
    els.scanBtn.disabled = false;
  }
}

async function toggleMonitor() {
  if (currentIndexMode === 'everything') {
    toast('实时索引模式下无需手动刷新');
    return;
  }
  const turningOn = els.monitorToggle.checked;
  els.monitorToggle.disabled = true;
  try {
    const r = await api(turningOn ? '/api/monitor/start' : '/api/monitor/stop', {});
    setMonitorUI(r.monitor, currentIndexMode);
    toast(turningOn ? '自动刷新已开启' : '自动刷新已关闭');
  } catch (e) {
    setMonitorUI({ running: !turningOn }, currentIndexMode);
    toast('操作失败: ' + e.message, true);
  } finally {
    if (currentIndexMode !== 'everything') els.monitorToggle.disabled = false;
  }
}

function typeClass(t) {
  if (t === 'video') return 'tb-video';
  if (t === 'image') return 'tb-image';
  if (t === 'audio') return 'tb-audio';
  return '';
}
const typeLabel = { video: '🎥 视频', image: '🖼️ 图片', audio: '🎵 音频' };

function showEmpty(text, icon) {
  els.results.innerHTML = '';
  els.groupActions.style.display = 'none';
  const div = document.createElement('div');
  div.className = 'empty-state';
  div.innerHTML = `<div class="empty-icon">${icon}</div><p>${text}</p>`;
  els.results.appendChild(div);
}

const preview = document.createElement('div');
preview.className = 'preview';
preview.innerHTML = '<img id="previewImg" alt="">';
document.body.appendChild(preview);
const previewImg = preview.querySelector('img');

function bindThumbPreview(thumbEl, path) {
  thumbEl.addEventListener('mouseenter', () => {
    previewImg.src = '/api/thumb?path=' + encodeURIComponent(path) + '&size=480';
    preview.classList.add('show');
  });
  thumbEl.addEventListener('mouseleave', () => {
    preview.classList.remove('show');
    previewImg.src = '';
  });
}
document.addEventListener('mousemove', (e) => {
  if (!preview.classList.contains('show')) return;
  const w = preview.offsetWidth || 340;
  const h = preview.offsetHeight || 240;
  let x = e.clientX + 18;
  let y = e.clientY + 18;
  if (x + w > window.innerWidth - 8) x = e.clientX - w - 12;
  if (y + h > window.innerHeight - 8) y = window.innerHeight - h - 12;
  preview.style.left = x + 'px';
  preview.style.top = y + 'px';
});

async function doSearch() {
  const kw = els.kwInput.value.trim();
  const type = els.typeSelect.value;
  const since = els.sinceSelect.value;
  els.searchBtn.disabled = true;
  els.searchMeta.textContent = '搜索中…';
  try {
    const r = await api('/api/search', { keyword: kw, type, since, limit: 500 });
    els.searchMeta.textContent = r.total ? `共找到 ${r.total} 个文件（显示前 ${Math.min(r.total, 500)} 个）` : '';
    renderResults(r.results || [], kw);
  } catch (e) {
    els.searchMeta.textContent = '';
    showEmpty('搜索失败: ' + e.message, '⚠️');
  } finally {
    els.searchBtn.disabled = false;
  }
}

function renderResults(items, kw) {
  els.results.innerHTML = '';
  if (!items.length) {
    showEmpty(kw ? `未找到与 “${kw}” 匹配的文件` : '索引为空，请先点击左侧「重新扫描」', '📭');
    return;
  }
  const frag = document.createDocumentFragment();
  const groups = new Map();
  currentGroups = [];
  items.forEach((it) => {
    const cat = it.category || '其他';
    if (!groups.has(cat)) groups.set(cat, []);
    groups.get(cat).push(it);
  });
  const order = [...groups.keys()];
  const other = order.indexOf('其他');
  if (other >= 0) { order.splice(other, 1); order.push('其他'); }
  order.forEach((cat) => {
    const groupItems = groups.get(cat);
    const group = document.createElement('div');
    group.className = 'group';
    currentGroups.push(group);
    const header = document.createElement('div');
    header.className = 'group-header';
    header.title = '点击折叠/展开';
    header.innerHTML = `<span class="chevron">▾</span><span>${escapeHtml(cat)}</span><span class="group-count">${groupItems.length}</span>`;
    const body = document.createElement('div');
    body.className = 'group-items';
    groupItems.forEach((it) => {
      const row = document.createElement('div');
      row.className = 'result-item';
      row.innerHTML = `
        <div class="thumb" data-path="${encodeURIComponent(it.path)}">
          <img src="/api/thumb?path=${encodeURIComponent(it.path)}&size=160" loading="lazy" alt="" style="display:none">
          <span class="thumb-type">${it.type === 'video' ? '🎬' : (it.type === 'image' ? '🖼️' : '🎵')}</span>
        </div>
        <div class="result-main">
          <div class="result-name" title="${escapeHtml(it.name)}">${escapeHtml(it.name)}</div>
          <div class="result-path" title="${escapeHtml(it.path)}">${escapeHtml(it.path)}</div>
        </div>
        <div class="result-meta">
          <div>${fmtSize(it.size)}</div>
          <div>${fmtTime(it.modified)}</div>
        </div>
        <div class="result-actions">
          <button class="icon-btn" title="打开文件" data-act="file">▶</button>
          <button class="icon-btn" title="打开所在文件夹" data-act="folder">📂</button>
          <button class="icon-btn" title="复制路径" data-act="copy">📋</button>
        </div>`;
      row.querySelector('[data-act="file"]').addEventListener('click', () => openFile(it.path));
      row.querySelector('[data-act="folder"]').addEventListener('click', () => openFolder(it.path));
      row.querySelector('[data-act="copy"]').addEventListener('click', () => copyPath(it.path));
      const thumb = row.querySelector('.thumb');
      const tImg = thumb.querySelector('img');
      if (it.type === 'image' || it.type === 'video') {
        tImg.style.display = '';
        tImg.addEventListener('load', () => { thumb.classList.add('thumb-loaded'); });
        tImg.addEventListener('error', () => {
          tImg.style.display = 'none';
          thumb.classList.add('thumb-fallback');
        });
        bindThumbPreview(thumb, it.path);
      }
      body.appendChild(row);
    });
    header.addEventListener('click', () => group.classList.toggle('collapsed'));
    group.appendChild(header);
    group.appendChild(body);
    frag.appendChild(group);
  });
  els.results.appendChild(frag);
  els.groupActions.style.display = currentGroups.length ? 'flex' : 'none';
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  }[c]));
}

async function openFile(p) {
  try { await api('/api/openfile', { path: p }); }
  catch (e) { toast('无法打开文件', true); }
}
async function openFolder(p) {
  try { await api('/api/open', { path: p }); }
  catch (e) { toast('无法打开文件夹', true); }
}
async function copyPath(p) {
  try {
    await navigator.clipboard.writeText(p);
    toast('已复制路径');
  } catch (e) {
    toast('复制失败', true);
  }
}

let browseCurrent = '';
let browseParent = null;

function openAddModal() {
  els.addModal.style.display = 'flex';
  els.suggestKw.value = '';
  els.suggestList.innerHTML = '';
  loadBrowse('');
}
function closeAddModal() {
  els.addModal.style.display = 'none';
}
function dirName(d) {
  const m = String(d).match(/^([a-zA-Z]):\\$/);
  if (m) return `${m[1]}: (${m[1]}盘)`;
  const parts = String(d).split(/[\\/]/).filter(Boolean);
  return parts.length ? parts[parts.length - 1] : String(d);
}
async function loadBrowse(path) {
  els.browseList.innerHTML = '<div class="browse-hint">加载中…</div>';
  try {
    const r = await api('/api/browse', { path });
    browseCurrent = r.current;
    browseParent = r.parent;
    els.browsePath.textContent = browseCurrent || '我的电脑';
    els.browsePath.title = browseCurrent || '';
    els.browseUp.disabled = browseParent === null;
    els.browseAdd.disabled = !browseCurrent;
    els.browseList.innerHTML = '';
    if (!r.dirs || !r.dirs.length) {
      els.browseList.innerHTML = '<div class="browse-hint">此文件夹下没有子文件夹</div>';
      return;
    }
    r.dirs.forEach((d) => {
      const item = document.createElement('div');
      item.className = 'browse-item';
      item.innerHTML = `<span>📁 ${escapeHtml(dirName(d))}</span>`;
      item.title = d;
      item.addEventListener('click', () => loadBrowse(d));
      els.browseList.appendChild(item);
    });
  } catch (e) {
    els.browseList.innerHTML = '<div class="browse-hint">无法读取该位置</div>';
  }
}
async function doSuggest() {
  const kw = els.suggestKw.value.trim();
  if (!kw) { toast('请输入游戏或软件名称', true); return; }
  els.suggestBtn.disabled = true;
  els.suggestList.innerHTML = '<div class="browse-hint">正在搜索…</div>';
  try {
    const r = await api('/api/suggest', { keyword: kw });
    els.suggestList.innerHTML = '';
    if (!r.results || !r.results.length) {
      els.suggestList.innerHTML = `<div class="browse-hint">未找到与“${escapeHtml(kw)}”相关的文件夹，请尝试其它名称或手动浏览</div>`;
      return;
    }
    r.results.forEach((sug) => {
      const item = document.createElement('div');
      item.className = 'suggest-item';
      item.innerHTML = `<span class="suggest-kind">${escapeHtml(sug.kind)}</span><span class="suggest-path">${escapeHtml(sug.path)}</span>`;
      item.title = '点击添加';
      item.addEventListener('click', () => addPath(sug.path));
      els.suggestList.appendChild(item);
    });
  } catch (e) {
    els.suggestList.innerHTML = '<div class="browse-hint">搜索失败</div>';
  } finally {
    els.suggestBtn.disabled = false;
  }
}
async function addPath(path) {
  try {
    const r = await api('/api/config/add', { path });
    if (r.ok) {
      toast('已添加目录，正在扫描…');
      closeAddModal();
      await fetchStatus(true);
      doScan();
    } else {
      toast('添加失败：' + (r.error || ''), true);
    }
  } catch (e) {
    toast('添加失败', true);
  }
}
async function removePath(path) {
  if (!confirm('确定移除该目录吗？\n' + path)) return;
  try {
    const r = await api('/api/config/remove', { path });
    toast('已移除目录');
    await fetchStatus(true);
    doScan();
  } catch (e) {
    toast('移除失败', true);
  }
}
async function ignorePrivacy(path) {
  try {
    const r = await api('/api/config/ignore-privacy', { path });
    toast('已记住，不再提示该目录');
    renderPrivacyDirs(r.privacyDirs || []);
  } catch (e) {
    toast('操作失败', true);
  }
}
function renderPrivacyDirs(dirs) {
  const box = els.privacyNote;
  box.innerHTML = '';
  if (!dirs || !dirs.length) return;
  const kinds = [...new Set(dirs.map((d) => d.kind))].join('/');
  const title = document.createElement('div');
  title.className = 'privacy-note-title';
  title.textContent = '📩 检测到' + kinds + '接收目录';
  box.appendChild(title);
  dirs.forEach((d) => {
    const p = document.createElement('span');
    p.className = 'privacy-note-path';
    p.textContent = d.path;
    p.title = d.path + '（点击展开/收起完整路径）';
    p.addEventListener('click', (e) => e.currentTarget.classList.toggle('expanded'));
    box.appendChild(p);
    const hint = document.createElement('div');
    hint.className = 'privacy-note-hint';
    hint.textContent = '该目录含' + d.hint + '，是否纳入监控？纳入后搜索结果中会出现其中内容。';
    box.appendChild(hint);
  });
  const actions = document.createElement('div');
  actions.className = 'privacy-actions';
  const addBtn = document.createElement('button');
  addBtn.className = 'privacy-btn privacy-btn-primary';
  addBtn.textContent = '纳入监控';
  addBtn.addEventListener('click', () => addPath(dirs[0].path));
  const noBtn = document.createElement('button');
  noBtn.className = 'privacy-btn';
  noBtn.textContent = '不再提示';
  noBtn.addEventListener('click', () => ignorePrivacy(dirs[0].path));
  actions.appendChild(addBtn);
  actions.appendChild(noBtn);
  box.appendChild(actions);
}
els.addPathBtn.addEventListener('click', openAddModal);
els.modalClose.addEventListener('click', closeAddModal);
els.addModal.addEventListener('click', (e) => { if (e.target === els.addModal) closeAddModal(); });
els.suggestBtn.addEventListener('click', doSuggest);
els.suggestKw.addEventListener('keydown', (e) => { if (e.key === 'Enter') doSuggest(); });
els.browseUp.addEventListener('click', () => { if (browseParent !== null) loadBrowse(browseParent); });
els.browseAdd.addEventListener('click', () => { if (browseCurrent) addPath(browseCurrent); });

let kwTimer = null;
els.kwInput.addEventListener('input', () => {
  clearTimeout(kwTimer);
  kwTimer = setTimeout(doSearch, 320);
});
els.typeSelect.addEventListener('change', doSearch);
els.sinceSelect.addEventListener('change', doSearch);
els.searchBtn.addEventListener('click', doSearch);
els.expandAllBtn.addEventListener('click', () => {
  currentGroups.forEach((g) => g.classList.remove('collapsed'));
});
els.collapseAllBtn.addEventListener('click', () => {
  currentGroups.forEach((g) => g.classList.add('collapsed'));
});
els.scanBtn.addEventListener('click', doScan);
els.monitorToggle.addEventListener('change', toggleMonitor);
els.refreshBtn.addEventListener('click', () => { toast('已刷新'); fetchStatus(); });
els.quitBtn.addEventListener('click', async () => {
  if (!confirm('确定要关闭 MediaFinder 服务器吗？')) return;
  try {
    await api('/api/quit', {});
    toast('服务器已关闭');
    setTimeout(() => { window.close(); }, 600);
  } catch (e) {
    toast('服务器已关闭');
  }
});

fetchStatus();
setInterval(() => fetchStatus(true), 5000);
