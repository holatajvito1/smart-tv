// Minimal tvOS-style home. Runs in a desktop browser (arrow keys, Enter, Escape = Back,
// P = Play/Pause) and inside the Android wrapper, which forwards the remote's buttons here as
// tvKey(...) and exposes window.TV for launching apps, radio and UI sounds.

// `open` is what the Android side launches: pkg | component | action | amazonHome,
// with `store` as the Appstore search used when the app isn't installed and `allowAmazon`
// for targets that live inside Amazon's launcher. No `open` means nothing to launch.
// The background is one photo for everything, chosen by the month (SEASONS below).
const APPS = [
  { id: "netflix",    name: "Netflix",     line: "Pick up where you left off.", open: { pkg: "com.netflix.ninja" } },
  { id: "primevideo", name: "Prime Video", line: "Originals, movies, and live sports.", open: { pkg: "com.amazon.firebat" } },
  { id: "youtube",    name: "YouTube",     line: "Creators, music, and more.", open: { pkg: "com.amazon.firetv.youtube" } },
  { id: "disneyplus", name: "Disney+",     line: "Disney, Pixar, Marvel, and Star Wars.", open: { pkg: "com.disney.disneyplus" } },
  { id: "hulu",       name: "Hulu",        line: "Next-day TV and Hulu Originals.", open: { pkg: "com.hulu.plus" } },
  { id: "appletv",    name: "Apple TV",    line: "Apple Originals and award-winning films.", open: { pkg: "com.apple.atve.amazon.appletv", store: "Apple TV" } },
];

// Official streams (checked live: each server identifies itself as the station).
// MP3 or HLS only: this TV's MediaPlayer can't play raw-AAC live streams (they stall on
// "caching reached eos"), so AAC stations use their MP3 mount, or HLS when that's all there is.
const STATIONS = [
  { id: "hot97",    name: "Hot 97",         band: "97.1 FM",  line: "Hip-hop and R&B from New York.",            url: "https://playerservices.streamtheworld.com/api/livestream-redirect/WQHTFM.mp3" },
  { id: "wins",     name: "1010 WINS",      band: "1010 AM",  line: "All news, all the time.",                    url: "https://live.amperwave.net/direct/audacy-winsammp3-imc" },
  // Santo Domingo, DR. Labelled by city: frequencies couldn't all be confirmed. Primera 88.1 needs the
  // radiojar.com cleartext exception in network_security_config.xml (its stream redirects to http).
  { id: "cdn",      name: "CDN Radio",      band: "Santo Domingo", line: "News and talk from CDN.",                url: "https://play.cdnradio.com.do/cdnlive" },
  { id: "primera",  name: "Primera 88.1",   band: "Santo Domingo", line: "From the Telemicro group.",              url: "https://stream.radiojar.com/5705c71sn2zuv" },
  { id: "latina",   name: "Latina 104",     band: "Santo Domingo", line: "La Bonita de Santo Domingo.",            url: "https://radio.dominiserver.com/proxy/latina104?mp=/stream" },
  { id: "lax",      name: "La X 102.1",     band: "Santo Domingo", line: "Music from Santo Domingo.",              url: "https://audio.livecastnet.com:2535/stream" },
  { id: "bachata",  name: "Top Bachata",    band: "Santo Domingo", line: "Nonstop bachata from Latina 104.",       url: "https://radio.dominiserver.com/proxy/topbachata?mp=/stream" },
  { id: "platino",  name: "Platino Radio",  band: "Santo Domingo", line: "Internet radio from Santo Domingo.",     url: "https://platinoradio-henrsosa.radioca.st/stream" },
];

const svg = (body) => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${body}</svg>`;
const ICONS = {
  radio: svg('<circle cx="12" cy="12" r="2"/><path d="M16.24 7.76a6 6 0 0 1 0 8.49M7.76 16.24a6 6 0 0 1 0-8.49M19.07 4.93a10 10 0 0 1 0 14.14M4.93 19.07a10 10 0 0 1 0-14.14"/>'),
  apps: svg('<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>'),
  airplay: svg('<path d="M5 17H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2h-1"/><path d="M12 15l5 6H7z" fill="currentColor"/>'),
  settings: svg('<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>'),
  firetv: svg('<path d="M3 10.5L12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6h-6v6H4a1 1 0 0 1-1-1z"/>'),
  power: svg('<path d="M12 2v9"/><path d="M18.36 6.64a9 9 0 1 1-12.73 0"/>'),
};

const CLOUD = '<path d="M17.5 19H8a5 5 0 1 1 .9-9.92A6 6 0 0 1 20 11.5a3.75 3.75 0 0 1-2.5 7.5z"/>';
const WX_ICONS = {
  sun: svg('<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"/>'),
  moon: svg('<path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/>'),
  partly: svg('<path d="M8 3v1.5M3.4 5.4l1 1M2 10h1.5"/><path d="M5.6 12.4A4 4 0 1 1 11.8 7"/><path d="M18 21H9.5a4 4 0 1 1 .7-7.94A5 5 0 0 1 19.5 15a3 3 0 0 1-1.5 6z"/>'),
  cloud: svg(CLOUD),
  fog: svg('<path d="M4 9h16M4 14h16M7 19h10"/>'),
  rain: svg(CLOUD.replace('19H8', '15H8').replace('7.5z', '3.5z') + '<path d="M8 19l-1 2M12 19l-1 2M16 19l-1 2"/>'),
  snow: svg(CLOUD.replace('19H8', '15H8').replace('7.5z', '3.5z') + '<path d="M8 19h.01M12 21h.01M16 19h.01"/>'),
  storm: svg(CLOUD.replace('19H8', '15H8').replace('7.5z', '3.5z') + '<path d="M13 16l-2 3h3l-2 3"/>'),
};

const PILLS = [
  { id: "radio",    name: "Radio",        line: "New York and Santo Domingo." },
  // AirPlay is a background receiver on Fire TV (its screens are Amazon-only), so there's
  // nothing to open: the line tells you what to pick on your iPhone or Mac instead.
  { id: "airplay",  name: "AirPlay",      line: "Stream from your iPhone, iPad, or Mac." },
  { id: "settings", name: "Settings",     line: "Display, sound, and network.", open: { action: "android.settings.SETTINGS", allowAmazon: true } },
  { id: "firetv",   name: "Fire TV Home", line: "The original Fire TV home screen.", open: { amazonHome: true } },
  // Standby via the Home service (no Restart: Android only lets Amazon-signed apps reboot).
  { id: "power",    name: "Power Off",    line: "Turn off the TV. The remote’s power button turns it back on." },
];

// Background by month (0 = January): img/bg/<name>.jpg, all 1920x1080.
const SEASONS = ["winter", "winter", "spring", "spring", "spring", "summer",
                 "summer", "summer", "autumn", "halloween", "thanksgiving", "christmas"];
// Photos too bright for white text (snow, sky): these get the heavier .bright scrim.
const BRIGHT_PHOTOS = ["winter"];

// Messages shown over the background all day on these dates, every year (month 1-12).
const OCCASIONS = [
  { month: 2,  day: 2,  text: "Happy Birthday Patricia" },
  { month: 10, day: 31, text: "Happy Halloween" },
  { month: 12, day: 31, text: "Happy Birthday Lucia" },
];

// Weather for Astoria, NY 11102 from Open-Meteo (free, no API key, CORS-open so the page
// fetches it directly). Refreshed every 30 minutes and when coming back after that long.
const WEATHER_URL = "https://api.open-meteo.com/v1/forecast?latitude=40.7706&longitude=-73.9265" +
  "&current=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min" +
  "&temperature_unit=fahrenheit&timezone=America%2FNew_York&forecast_days=1";
const WEATHER_EVERY_MS = 30 * 60000;

const native = window.TV || null;
const $ = (id) => document.getElementById(id);

const state = {
  mode: "apps",               // top row shows "apps" or "radio" (stations)
  row: 0,
  col: { apps: 0, radio: 0, pills: 0 },
  stationOffset: 0,
  busy: false,
  radio: { id: null, status: "stopped", last: null },
};
const els = { apps: [], radio: [], pills: [] };

// ── Build ──
function build() {
  for (const app of APPS) {
    const el = document.createElement("div");
    el.className = "tile";
    el.innerHTML = `<div class="tile-art" style="background-image:url('img/tiles/${app.id}.png')"></div>`;
    $("tiles").appendChild(el);
    els.apps.push(el);
  }
  for (const st of STATIONS) {
    const el = document.createElement("div");
    el.className = "tile station";
    el.innerHTML = `<div class="tile-art"><span class="st-band">${st.band}</span><span class="st-name">${st.name}</span>` +
      `<span class="bars"><i></i><i></i><i></i></span></div>`;
    $("stationTrack").appendChild(el);
    els.radio.push(el);
  }
  for (const pill of PILLS) {
    const el = document.createElement("div");
    el.className = "pill";
    el.innerHTML = `<span class="pill-icon">${ICONS[pill.id]}</span><span class="pill-name">${pill.name}</span>`;
    $("pills").appendChild(el);
    els.pills.push(el);
  }
}

const rowName = (row) => (row === 0 ? state.mode : "pills");
const rowItems = (row) => ({ apps: APPS, radio: STATIONS, pills: PILLS })[rowName(row)];
const rowEls = (row) => els[rowName(row)];
const current = () => rowItems(state.row)[state.col[rowName(state.row)]];
const currentEl = () => rowEls(state.row)[state.col[rowName(state.row)]];

// ── Focus ──
function focus(row, col, instant) {
  currentEl().classList.remove("focus");
  state.row = row;
  state.col[rowName(row)] = col;
  currentEl().classList.add("focus");
  if (rowName(row) === "radio") scrollStations(col);
  showInfo(current(), instant);
}

const lineFor = (item) => (item.band ? `${item.band} · ${item.line}` : item.line);

function showInfo(item, instant) {
  const info = $("info");
  const apply = () => {
    $("infoName").textContent = item.name;
    $("infoLine").textContent = lineFor(item);
    info.classList.remove("swap");
  };
  clearTimeout(showInfo.t);              // a newer focus always wins over a pending swap
  if (instant) return apply();
  info.classList.add("swap");
  showInfo.t = setTimeout(apply, 120);
}

// Keep the focused station card inside the safe area; the track slides (GPU transform only).
function scrollStations(i) {
  const step = 27, card = 24, visible = 164.8;       // rem: card + gap, card, inside the dock
  const x = i * step;
  let off = state.stationOffset;
  // Scroll in whole cards so the leftmost visible card sits on the margin.
  if (x - off > visible - card) off = Math.ceil((x - (visible - card)) / step) * step;
  if (x - off < 0) off = x;
  state.stationOffset = off;
  $("stationTrack").style.transform = `translateX(${-off}rem)`;
}

// ── Apps <-> radio stations in the top row ──
function setMode(mode) {
  if (state.mode === mode) return;
  if (state.row === 0) currentEl().classList.remove("focus");
  state.mode = mode;
  $("ui").classList.toggle("radio", mode === "radio");
  const pill = els.pills[0];
  pill.querySelector(".pill-icon").innerHTML = ICONS[mode === "radio" ? "apps" : "radio"];
  pill.querySelector(".pill-name").textContent = mode === "radio" ? "Apps" : "Radio";
  // Land on the station that's playing, else where you were.
  const playing = STATIONS.findIndex((s) => s.id === state.radio.id);
  focus(0, mode === "radio" && playing >= 0 ? playing : state.col[mode]);
}

// ── Radio ──
function radioPlay(st) {
  state.radio = { id: st.id, status: "loading", last: st.id };
  renderRadio();
  if (native) native.radioPlay(st.id, st.url);
  else previewAudio(st);
}

function radioStop() {
  if (!state.radio.id) return;
  state.radio = { ...state.radio, id: null, status: "stopped" };
  renderRadio();
  if (native) native.radioStop();
  else previewAudio(null);
}

// Player reports back: loading | playing | stopped | error.
window.tvRadio = function (status, id) {
  if (id !== state.radio.id) return;                 // stale news about a station we left
  if (status === "error") {
    state.radio = { ...state.radio, id: null, status: "error" };
    renderRadio(STATIONS.find((s) => s.id === id));
    return;
  }
  state.radio = { ...state.radio, id: status === "stopped" ? null : id, status };
  renderRadio();
};

function renderRadio(failed) {
  const { id, status } = state.radio;
  STATIONS.forEach((s, i) => {
    els.radio[i].classList.toggle("playing", s.id === id && status === "playing");
    els.radio[i].classList.toggle("loading", s.id === id && status === "loading");
  });
  const st = STATIONS.find((s) => s.id === id);
  const now = $("now");
  clearTimeout(renderRadio.t);
  if (failed) {
    $("nowText").textContent = `Couldn’t reach ${failed.name}`;
    now.className = "now show error";
    renderRadio.t = setTimeout(() => (now.className = "now"), 4000);
  } else if (st) {
    $("nowText").textContent = status === "loading" ? `Tuning ${st.name}…` : `${st.name} · ${st.band}`;
    now.className = `now show ${status}`;
  } else {
    now.className = "now";
  }
}

// Desktop preview: plain <audio>, same streams.
function previewAudio(st) {
  const a = previewAudio.el || (previewAudio.el = new Audio());
  a.onplaying = a.onerror = null;
  if (!st) { a.pause(); a.removeAttribute("src"); return; }
  a.src = st.url;
  a.onplaying = () => window.tvRadio("playing", st.id);
  a.onerror = () => window.tvRadio("error", st.id);
  a.play().catch(() => window.tvRadio("error", st.id));
}

// ── Sounds ──
function sound(name) {
  const now = performance.now();
  if (name === "move" && now - (sound.last || 0) < 70) return;   // holding an arrow: don't rattle
  sound.last = now;
  if (native) return native.sound(name);
  const a = new Audio(`sounds/${name}.wav`);
  a.volume = 0.8;
  a.play().catch(() => {});
}

// ── Input ──
function move(dir) {
  const { row } = state;
  const col = state.col[rowName(row)];
  const len = rowItems(row).length;
  if (dir === "left" && col > 0) focus(row, col - 1);
  else if (dir === "right" && col < len - 1) focus(row, col + 1);
  else if (dir === "down" && row === 0) focus(1, state.col.pills);
  else if (dir === "up" && row === 1) focus(0, state.col[state.mode]);
  else return false;
  return true;
}

function activate() {
  if (state.busy) return;
  const item = current();
  const kind = rowName(state.row);
  const el = currentEl();
  state.busy = true;
  el.classList.add("press");
  sound("select");
  setTimeout(() => {
    el.classList.remove("press");
    state.busy = false;
    if (kind === "radio") {
      if (state.radio.id === item.id) radioStop();
      else radioPlay(item);
    } else if (item.id === "radio") {
      setMode(state.mode === "radio" ? "apps" : "radio");
    } else if (item.id === "power") {
      radioStop();
      if (!native) toast("Would turn off the TV");
      else if (!native.powerOff()) toast("Couldn't turn off: the Home service isn't running");
    } else if (item.open) {
      if (kind === "apps") radioStop();          // an app is about to take the screen and the audio
      if (native) native.launch(JSON.stringify(item.open));
      else toast(`Would open ${item.name}`);
    }
  }, 140);
}

// Called by the Android wrapper for every remote key; also used by the keyboard handler.
window.tvKey = function (key) {
  if (key === "enter") return activate();
  if (key === "back") {
    if (state.mode === "radio") { setMode("apps"); sound("move"); }
    return;
  }
  if (key === "playpause") {
    if (state.radio.id) return radioStop();
    const st = STATIONS.find((s) => s.id === state.radio.last) || (state.mode === "radio" && state.row === 0 ? current() : null);
    if (st) radioPlay(st);
    return;
  }
  if (move(key)) sound("move");
};

// Wrapper hooks: back in the foreground / Home pressed while already showing.
window.tvResume = function () {
  tick();
  if (Date.now() - (refreshWeather.at || 0) > WEATHER_EVERY_MS) refreshWeather();
  // Draw first: the installed-app check costs a few binder calls on this chip.
  setTimeout(refreshInstalled, 600);
};
window.tvHome = function () {
  if (state.mode !== "apps") setMode("apps");
  if (state.row !== 0 || state.col.apps !== 0) focus(0, 0);
};

const KEYS = { ArrowLeft: "left", ArrowRight: "right", ArrowUp: "up", ArrowDown: "down", Enter: "enter", " ": "enter", Escape: "back", Backspace: "back", p: "playpause" };
document.addEventListener("keydown", (e) => {
  const key = KEYS[e.key];
  if (!key) return;
  e.preventDefault();
  window.tvKey(key);
});

// ── Apps that aren't installed get a "Get" badge and open the Appstore ──
function refreshInstalled() {
  if (!native) return;
  APPS.forEach((app, i) => {
    const installed = native.isInstalled(JSON.stringify(app.open));
    const tile = els.apps[i];
    let badge = tile.querySelector(".badge");
    if (installed && badge) badge.remove();
    if (!installed && !badge) {
      badge = document.createElement("div");
      badge.className = "badge";
      badge.textContent = "Get";
      tile.appendChild(badge);
    }
  });
}

// ── Clock, date, and the month's background (re-checked every minute) ──
function tick() {
  const now = new Date();
  if (dateOverride.length) now.setMonth(dateOverride[0] - 1, dateOverride[1]);   // [] when not previewing
  else if (monthOverride) now.setMonth(monthOverride - 1, 1);
  $("clock").textContent = now.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }).replace(/\s?[AP]M$/i, "");
  $("date").textContent = now.toLocaleDateString([], { weekday: "long", month: "long", day: "numeric" });
  setSeason(SEASONS[now.getMonth()]);
  setOccasion(OCCASIONS.find((o) => o.month === now.getMonth() + 1 && o.day === now.getDate()));
  clearTimeout(tick.t);
  tick.t = setTimeout(tick, 60000 - (now.getSeconds() * 1000 + now.getMilliseconds()) + 50);
}
// Preview another day: ?month=1..12 (background), ?date=MM-DD (background + occasion message).
const monthOverride = Number(new URLSearchParams(location.search).get("month")) || 0;
const dateOverride = (/^(\d{1,2})-(\d{1,2})$/.exec(new URLSearchParams(location.search).get("date") || "") || [])
  .slice(1).map(Number);

function setOccasion(occasion) {
  const text = occasion ? occasion.text : "";
  if (setOccasion.current === text) return;
  setOccasion.current = text;
  const el = $("occasion");
  if (text) el.textContent = text;
  el.classList.toggle("show", !!text);
}

function setSeason(name) {
  if (setSeason.current === name) return;
  setSeason.current = name;
  $("bg").style.backgroundImage = `url("img/bg/${name}.jpg")`;
  $("stage").classList.toggle("bright", BRIGHT_PHOTOS.includes(name));
}

// ── Weather ──
// WMO weather code -> words + icon (https://open-meteo.com/en/docs, "WMO Weather interpretation codes").
function describeWeather(code, isDay) {
  if (code === 0) return ["Clear", isDay ? "sun" : "moon"];
  if (code <= 2) return [code === 1 ? "Mostly Clear" : "Partly Cloudy", isDay ? "partly" : "cloud"];
  if (code === 3) return ["Cloudy", "cloud"];
  if (code === 45 || code === 48) return ["Fog", "fog"];
  if (code >= 51 && code <= 57) return ["Drizzle", "rain"];
  if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82)) return [code >= 80 ? "Showers" : "Rain", "rain"];
  if ((code >= 71 && code <= 77) || code === 85 || code === 86) return ["Snow", "snow"];
  if (code >= 95) return ["Thunderstorms", "storm"];
  return ["", "cloud"];
}

function showWeather(w) {
  if (!w || !w.current) return;
  const [words, icon] = describeWeather(w.current.weather_code, w.current.is_day === 1);
  const hi = Math.round(w.daily.temperature_2m_max[0]), lo = Math.round(w.daily.temperature_2m_min[0]);
  $("wxIcon").innerHTML = WX_ICONS[icon];
  $("wxText").textContent = `${Math.round(w.current.temperature_2m)}° ${words} · H ${hi}° L ${lo}°`;
  $("weather").classList.add("show");
}

async function refreshWeather() {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), 10000);
  try {
    const w = await (await fetch(WEATHER_URL, { signal: ctl.signal })).json();
    refreshWeather.at = Date.now();
    showWeather(w);
    try { localStorage.setItem("weather", JSON.stringify(w)); } catch (e) {}
  } catch (e) {
    // Offline or the service is down: keep showing the last reading.
  } finally {
    clearTimeout(timer);
  }
}

function toast(msg) {
  const t = $("toast");
  t.textContent = msg;
  t.classList.add("show");
  clearTimeout(toast.t);
  toast.t = setTimeout(() => t.classList.remove("show"), 1400);
}

// Name this TV shows up as for AirPlay.
const tvName = native && native.deviceName ? native.deviceName() : "";
PILLS[1].line = tvName ? `Ready — choose “${tvName}” in Screen Mirroring.` : "Ready — choose this TV in Screen Mirroring.";

build();
tick();
try { showWeather(JSON.parse(localStorage.getItem("weather"))); } catch (e) {}   // last reading, instantly
refreshWeather();
setInterval(refreshWeather, WEATHER_EVERY_MS);
setTimeout(refreshInstalled, 600);
// Preview helpers: ?radio=1 opens the stations, ?focus=row,col starts on another item,
// ?month=N shows month N's background.
const params = new URLSearchParams(location.search);
if (params.get("radio")) setMode("radio");
const [r0, c0] = (params.get("focus") || "0,0").split(",").map(Number);
focus(rowItems(r0) ? r0 : 0, rowItems(r0) && rowItems(r0)[c0] ? c0 : 0, true);
