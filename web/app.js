const $ = (selector) => document.querySelector(selector);
const state = {
  auth: sessionStorage.getItem("gmd-auth") || "",
  tracks: [],
  queue: [],
  currentIndex: -1,
  objectURL: null,
  shuffle: false,
  repeat: "off",
  favorites: new Set(JSON.parse(localStorage.getItem("gmd-favorites") || "[]")),
  playlists: JSON.parse(localStorage.getItem("gmd-playlists") || "[]"),
  history: JSON.parse(localStorage.getItem("gmd-history") || "[]")
};
const audio = $("#audio");

function authHeader() {
  return state.auth ? { Authorization: `Basic ${state.auth}` } : {};
}
async function api(path, options = {}) {
  const response = await fetch(path, {
    ...options,
    headers: { ...authHeader(), ...(options.headers || {}) }
  });
  if (response.status === 401) {
    state.auth = "";
    sessionStorage.removeItem("gmd-auth");
    showLogin("Senha incorreta ou sessão expirada.");
    throw new Error("Autenticação necessária.");
  }
  const data = response.status === 204 ? null : await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data?.detail || `Erro HTTP ${response.status}`);
  return data;
}
function showLogin(message = "") {
  $("#login-overlay").classList.remove("hidden");
  $("#login-error").textContent = message;
}
function hideLogin() {
  $("#login-overlay").classList.add("hidden");
  $("#login-error").textContent = "";
  $("#logout-button").hidden = false;
}
function toast(message) {
  const element = $("#toast");
  element.textContent = message;
  element.classList.add("show");
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => element.classList.remove("show"), 2800);
}
function escapeHTML(value) {
  return String(value ?? "").replace(/[&<>"']/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[char]));
}
function formatTime(value) {
  if (!Number.isFinite(value)) return "0:00";
  const seconds = Math.floor(value);
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}
function setView(name) {
  document.querySelectorAll(".view").forEach(view => view.classList.remove("active"));
  $(`#${name}-view`).classList.add("active");
  document.querySelectorAll(".nav-button").forEach(button => button.classList.toggle("active", button.dataset.view === name));
  const titles = { search: "Explore músicas de jogos", library: "Minha biblioteca", favorites: "Seus favoritos", playlists: "Suas playlists", history: "Histórico de reprodução" };
  $("#page-title").textContent = titles[name];
  $("#detail-panel").hidden = true;
  if (name === "library") renderLibrary();
  if (name === "favorites") renderFavorites();
  if (name === "playlists") renderPlaylists();
  if (name === "history") renderHistory();
}
document.querySelectorAll(".nav-button").forEach(button => button.addEventListener("click", () => setView(button.dataset.view)));

$("#login-form").addEventListener("submit", async event => {
  event.preventDefault();
  const password = $("#password-input").value;
  state.auth = btoa(String.fromCharCode(...new TextEncoder().encode(`admin:${password}`)));
  try {
    await api("/api/library");
    sessionStorage.setItem("gmd-auth", state.auth);
    hideLogin();
    await refreshLibrary();
  } catch (error) {
    state.auth = "";
    $("#login-error").textContent = error.message || "Não foi possível entrar.";
  }
});
$("#logout-button").addEventListener("click", () => {
  state.auth = "";
  sessionStorage.removeItem("gmd-auth");
  $("#logout-button").hidden = true;
  showLogin();
});

async function refreshLibrary() {
  const data = await api("/api/library");
  state.tracks = data.tracks || [];
  $("#library-count").textContent = `${state.tracks.length} faixas`;
  renderLibrary();
}
$("#search-form").addEventListener("submit", async event => {
  event.preventDefault();
  const term = $("#search-input").value.trim();
  if (!term) return;
  $("#results-title").textContent = `Pesquisando “${term}”`;
  $("#search-results").className = "results-grid empty-panel";
  $("#search-results").innerHTML = "<p>Consultando o Internet Archive...</p>";
  try {
    const data = await api(`/api/search?q=${encodeURIComponent(term)}`);
    $("#results-title").textContent = "Resultados da pesquisa";
    $("#results-count").textContent = `${data.results.length} itens`;
    if (!data.results.length) {
      $("#search-results").className = "results-grid empty-panel";
      $("#search-results").innerHTML = '<div class="empty-icon">⌕</div><h3>Nenhum resultado encontrado</h3><p>Tente outro jogo, artista ou título.</p>';
      return;
    }
    $("#search-results").className = "results-grid";
    $("#search-results").innerHTML = data.results.map(item => `
      <article class="result-card">
        <span class="eyebrow">INTERNET ARCHIVE</span>
        <h3>${escapeHTML(item.title)}</h3>
        <p>${escapeHTML(item.creator)}</p>
        <div class="result-meta"><span>Licença declarada</span><button class="text-button" data-item="${escapeHTML(item.identifier)}" data-license="${escapeHTML(item.licenseURL || "")}">Ver arquivos →</button></div>
      </article>`).join("");
    $("#search-results").querySelectorAll("[data-item]").forEach(button => button.addEventListener("click", () => openItem(button.dataset.item, button.dataset.license)));
  } catch (error) {
    $("#search-results").className = "empty-panel";
    $("#search-results").textContent = error.message;
  }
});

async function openItem(identifier, searchLicense) {
  const panel = $("#detail-panel");
  panel.hidden = false;
  panel.innerHTML = "<p>Consultando metadados e verificando arquivos MP3...</p>";
  panel.scrollIntoView({ behavior: "smooth", block: "start" });
  try {
    const item = await api(`/api/items/${encodeURIComponent(identifier)}?search_license_url=${encodeURIComponent(searchLicense || "")}`);
    panel.innerHTML = `
      <div class="detail-head"><div><span class="eyebrow">DETALHES DO ITEM</span><h2>${escapeHTML(item.title)}</h2><p class="detail-muted">${escapeHTML(item.creator)} · ${escapeHTML(item.identifier)}</p></div><button id="close-detail" class="ghost-button">Fechar</button></div>
      <p class="detail-muted"><a href="${escapeHTML(item.itemURL)}" target="_blank" rel="noopener">Abrir página original no Internet Archive ↗</a></p>
      <div id="file-list"></div>
      <p class="detail-muted">A licença declarada não comprova, sozinha, a titularidade do áudio ou a autorização de quem enviou o arquivo. Confira a página original antes de baixar.</p>`;
    $("#close-detail").addEventListener("click", () => panel.hidden = true);
    const list = $("#file-list");
    if (!item.files.length) {
      list.innerHTML = '<p class="detail-muted">Nenhum MP3 público e elegível foi localizado neste item.</p>';
      return;
    }
    list.innerHTML = item.files.map(file => {
      const license = file.license;
      const allowed = license.canOfferDownload;
      const size = file.size && /^\d+$/.test(file.size) ? `${(Number(file.size) / 1048576).toFixed(1)} MB` : "Tamanho não informado";
      return `<div class="file-row"><div><strong>${escapeHTML(file.filename)}</strong><div class="detail-muted">${size} · <span class="${allowed ? "license-ok" : "license-no"}">${escapeHTML(license.name)}</span></div><p class="detail-muted">${escapeHTML(license.message)}</p></div><div>${allowed ? `<button class="primary-button download-button" data-file="${escapeHTML(file.filename)}">Confirmar e baixar</button>` : '<span class="license-no">Download bloqueado</span>'}</div></div>`;
    }).join("");
    list.querySelectorAll(".download-button").forEach(button => button.addEventListener("click", () => downloadFile(identifier, button.dataset.file, searchLicense, button)));
  } catch (error) {
    panel.innerHTML = `<p class="error-text">${escapeHTML(error.message)}</p>`;
  }
}
async function downloadFile(identifier, filename, searchLicense, button) {
  const confirmation = "Confirme que você verificou a página do item, a licença e que o uploader tinha autorização para disponibilizar este áudio. Deseja continuar?";
  if (!window.confirm(confirmation)) return;
  button.disabled = true;
  button.textContent = "Baixando...";
  try {
    const data = await api("/api/download", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ identifier, filename, search_license_url: searchLicense, confirmed: true })
    });
    toast(data.message);
    await refreshLibrary();
  } catch (error) {
    toast(error.message);
  } finally {
    button.disabled = false;
    button.textContent = "Confirmar e baixar";
  }
}

function emptyState(message) {
  return `<div class="empty-panel"><div class="empty-icon">♫</div><h3>${message}</h3><p>Suas músicas aparecerão aqui depois de baixadas.</p></div>`;
}
function trackCard(track, index, actions = true) {
  return `<article class="track-card"><div class="cover-small">♫</div><div class="track-info"><strong>${escapeHTML(track.title)}</strong><small>${escapeHTML(track.artist)} · ${escapeHTML(track.game)}</small></div><div class="track-actions"><button class="icon-button play-track" data-index="${index}" aria-label="Reproduzir">▶</button>${actions ? `<button class="icon-button favorite-track" data-id="${escapeHTML(track.id)}" aria-label="Favoritar">${state.favorites.has(track.id) ? "♥" : "♡"}</button><button class="icon-button playlist-track" data-id="${escapeHTML(track.id)}" aria-label="Adicionar a playlist">＋</button><button class="icon-button delete-track" data-id="${escapeHTML(track.id)}" aria-label="Excluir">⌫</button>` : ""}</div></article>`;
}
function bindTrackActions(container, tracks) {
  container.querySelectorAll(".play-track").forEach(button => button.addEventListener("click", () => playTrack(tracks[Number(button.dataset.index)], tracks)));
  container.querySelectorAll(".favorite-track").forEach(button => button.addEventListener("click", () => {
    const id = button.dataset.id;
    state.favorites.has(id) ? state.favorites.delete(id) : state.favorites.add(id);
    localStorage.setItem("gmd-favorites", JSON.stringify([...state.favorites]));
    renderLibrary();
    renderFavorites();
  }));
  container.querySelectorAll(".playlist-track").forEach(button => button.addEventListener("click", () => {
    if (!state.playlists.length) { toast("Crie uma playlist primeiro."); setView("playlists"); return; }
    const choices = state.playlists.map((list, index) => `${index + 1}. ${list.name}`).join("\n");
    const answer = prompt(`Adicionar a qual playlist?\n${choices}\nDigite o número:`);
    const index = Number(answer) - 1;
    if (!Number.isInteger(index) || !state.playlists[index]) return;
    const list = state.playlists[index];
    if (!list.ids.includes(button.dataset.id)) list.ids.push(button.dataset.id);
    savePlaylists();
    toast(`Adicionada à playlist ${list.name}.`);
  }));
  container.querySelectorAll(".delete-track").forEach(button => button.addEventListener("click", async () => {
    if (!confirm("Excluir esta música do servidor?")) return;
    try { await api(`/api/library/${encodeURIComponent(button.dataset.id)}`, { method: "DELETE" }); await refreshLibrary(); toast("Música removida."); }
    catch (error) { toast(error.message); }
  }));
}
function renderLibrary() {
  const el = $("#library-list");
  el.innerHTML = state.tracks.length ? state.tracks.map((track, index) => trackCard(track, index)).join("") : emptyState("Sua biblioteca está vazia");
  bindTrackActions(el, state.tracks);
}
function renderFavorites() {
  const tracks = state.tracks.filter(track => state.favorites.has(track.id));
  const el = $("#favorites-list");
  el.innerHTML = tracks.length ? tracks.map((track, index) => trackCard(track, index)).join("") : emptyState("Nenhum favorito ainda");
  bindTrackActions(el, tracks);
}
function renderPlaylists() {
  const el = $("#playlists-list");
  if (!state.playlists.length) { el.innerHTML = emptyState("Crie sua primeira playlist"); return; }
  el.innerHTML = state.playlists.map(list => `<article class="playlist-card"><h3>${escapeHTML(list.name)}</h3><p>${list.ids.length} músicas</p><div class="track-actions"><button class="text-button open-playlist" data-id="${list.id}">Abrir</button><button class="text-button remove-playlist" data-id="${list.id}">Excluir</button></div><div class="playlist-tracks" id="playlist-${list.id}"></div></article>`).join("");
  el.querySelectorAll(".open-playlist").forEach(button => button.addEventListener("click", () => {
    const list = state.playlists.find(item => item.id === button.dataset.id);
    const tracks = list.ids.map(id => state.tracks.find(track => track.id === id)).filter(Boolean);
    const target = $(`#playlist-${list.id}`);
    target.innerHTML = tracks.length ? tracks.map((track, index) => trackCard(track, index, false)).join("") : '<p class="detail-muted">Adicione músicas pelo botão de playlist na biblioteca em uma próxima etapa.</p>';
    bindTrackActions(target, tracks);
  }));
  el.querySelectorAll(".remove-playlist").forEach(button => button.addEventListener("click", () => {
    state.playlists = state.playlists.filter(item => item.id !== button.dataset.id);
    savePlaylists(); renderPlaylists();
  }));
}
function savePlaylists() { localStorage.setItem("gmd-playlists", JSON.stringify(state.playlists)); }
$("#playlist-form").addEventListener("submit", event => {
  event.preventDefault();
  const name = $("#playlist-name").value.trim();
  if (!name) return;
  state.playlists.push({ id: crypto.randomUUID(), name, ids: [] });
  savePlaylists(); $("#playlist-name").value = ""; renderPlaylists(); toast("Playlist criada.");
});
function renderHistory() {
  const tracks = state.history.map(id => state.tracks.find(track => track.id === id)).filter(Boolean);
  const el = $("#history-list");
  el.innerHTML = tracks.length ? tracks.map((track, index) => trackCard(track, index, false)).join("") : emptyState("Seu histórico está vazio");
  bindTrackActions(el, tracks);
}
$("#clear-history").addEventListener("click", () => { state.history = []; localStorage.setItem("gmd-history", "[]"); renderHistory(); });

async function playTrack(track, queue = state.tracks) {
  if (!track) return;
  try {
    const response = await fetch(`/api/library/${encodeURIComponent(track.id)}/audio`, { headers: authHeader() });
    if (response.status === 401) { showLogin("Entre novamente para reproduzir."); return; }
    if (!response.ok) throw new Error("Não foi possível carregar o áudio.");
    const blob = await response.blob();
    if (state.objectURL) URL.revokeObjectURL(state.objectURL);
    state.objectURL = URL.createObjectURL(blob);
    audio.src = state.objectURL;
    state.currentIndex = queue.findIndex(item => item.id === track.id);
    state.queue = queue;
    $("#player-title").textContent = track.title;
    $("#player-artist").textContent = track.artist;
    $("#player-bar").hidden = false;
    if ("mediaSession" in navigator && "MediaMetadata" in window) {
      navigator.mediaSession.metadata = new MediaMetadata({ title: track.title, artist: track.artist, album: track.game, artwork: [{ src: "/icon.svg", sizes: "any", type: "image/svg+xml" }] });
      navigator.mediaSession.setActionHandler("play", () => audio.play());
      navigator.mediaSession.setActionHandler("pause", () => audio.pause());
      navigator.mediaSession.setActionHandler("previoustrack", previousTrack);
      navigator.mediaSession.setActionHandler("nexttrack", nextTrack);
      navigator.mediaSession.setActionHandler("seekto", details => { if (Number.isFinite(details.seekTime)) audio.currentTime = details.seekTime; });
    }
    await audio.play();
    state.history = [track.id, ...state.history.filter(id => id !== track.id)].slice(0, 100);
    localStorage.setItem("gmd-history", JSON.stringify(state.history));
    $("#play-button").textContent = "Ⅱ";
  } catch (error) { toast(error.message); }
}
$("#play-button").addEventListener("click", async () => {
  if (!audio.src) return;
  if (audio.paused) { try { await audio.play(); } catch { toast("Não foi possível iniciar a reprodução."); } }
  else audio.pause();
});
audio.addEventListener("play", () => $("#play-button").textContent = "Ⅱ");
audio.addEventListener("pause", () => $("#play-button").textContent = "▶");
audio.addEventListener("timeupdate", () => {
  $("#current-time").textContent = formatTime(audio.currentTime);
  $("#duration").textContent = formatTime(audio.duration);
  $("#seek").value = audio.duration ? String(audio.currentTime / audio.duration * 100) : "0";\n  if ("mediaSession" in navigator && audio.duration) navigator.mediaSession.setPositionState({ duration: audio.duration, playbackRate: audio.playbackRate, position: audio.currentTime });
});
audio.addEventListener("ended", () => {
  if (state.repeat === "one") { audio.currentTime = 0; audio.play(); return; }
  nextTrack();
});
$("#seek").addEventListener("input", event => { if (audio.duration) audio.currentTime = audio.duration * Number(event.target.value) / 100; });
$("#volume").addEventListener("input", event => audio.volume = Number(event.target.value));
$("#shuffle-button").addEventListener("click", () => { state.shuffle = !state.shuffle; $("#shuffle-button").classList.toggle("active", state.shuffle); toast(state.shuffle ? "Modo aleatório ativado." : "Modo aleatório desativado."); });
$("#repeat-button").addEventListener("click", () => { state.repeat = state.repeat === "off" ? "all" : state.repeat === "all" ? "one" : "off"; $("#repeat-button").textContent = state.repeat === "one" ? "↻¹" : "↻"; toast(`Repetição: ${state.repeat === "off" ? "desligada" : state.repeat === "all" ? "todas" : "uma faixa"}.`); });
function nextTrack() {
  if (!state.queue.length) return;
  let index;
  if (state.shuffle && state.queue.length > 1) {
    const choices = state.queue.map((_, i) => i).filter(i => i !== state.currentIndex);
    index = choices[Math.floor(Math.random() * choices.length)];
  } else if (state.currentIndex + 1 < state.queue.length) index = state.currentIndex + 1;
  else if (state.repeat === "all") index = 0;
  else { audio.pause(); audio.currentTime = 0; return; }
  playTrack(state.queue[index], state.queue);
}
function previousTrack() {
  if (audio.currentTime > 3) { audio.currentTime = 0; return; }
  if (!state.queue.length) return;
  let index = state.shuffle && state.queue.length > 1 ? Math.floor(Math.random() * state.queue.length) : state.currentIndex - 1;
  if (index < 0) index = state.repeat === "all" ? state.queue.length - 1 : 0;
  playTrack(state.queue[index], state.queue);
}
$("#next-button").addEventListener("click", nextTrack);
$("#previous-button").addEventListener("click", previousTrack);

(async function initialize() {
  try {
    const health = await fetch("/api/health");
    if (!health.ok) throw new Error("Servidor indisponível.");
    if (state.auth) {
      try { await refreshLibrary(); hideLogin(); }
      catch { state.auth = ""; sessionStorage.removeItem("gmd-auth"); showLogin(); }
    } else showLogin();
  } catch (error) {
    showLogin(error.message);
  }
})();
