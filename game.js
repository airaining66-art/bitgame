const state = {
  phase: "idle",
  countdownStartTime: 0,
  countdownStep: -1,
  startTime: 0,
  beatStartTime: 0,
  beatDuration: 600,
  currentBeat: 0,
  health: 3,
  score: 0,
  combo: 0,
  lastJudgedBeat: -1,
  current: null,
  queue: [],
  rafId: 0,
};

const els = {
  score: document.getElementById("score"),
  bpm: document.getElementById("bpm"),
  hearts: document.getElementById("hearts"),
  topLane: document.getElementById("topLane"),
  bottomLane: document.getElementById("bottomLane"),
  feedback: document.getElementById("feedback"),
  countdown: document.getElementById("countdown"),
  comboPanel: document.getElementById("comboPanel"),
  comboCount: document.getElementById("comboCount"),
  hitButton: document.getElementById("hitButton"),
  gameOver: document.getElementById("gameOver"),
  finalScore: document.getElementById("finalScore"),
  restartButton: document.getElementById("restartButton"),
};

const START_BPM = 50;
const END_BPM = 80;
const SPEEDUP_MS = 60_000;
const SLIDE_RATIO = 0.5;
const MIN_PERFECT_MS = 140;
const MIN_GOOD_MS = 260;
const COUNTDOWN_BEATS = ["3", "2", "1", "START"];
const COUNTDOWN_STEP_MS = 60_000 / START_BPM;

let audioContext = null;

function randBit() {
  return Math.random() < 0.5 ? 0 : 1;
}

function makeBeat() {
  const top = randBit();
  const shouldMatch = Math.random() < 0.5;
  return {
    top,
    bottom: shouldMatch ? top : 1 - top,
    shouldPress: shouldMatch,
  };
}

function ensureQueue() {
  while (state.queue.length < 5) {
    state.queue.push(makeBeat());
  }
}

function bpmAt(elapsed) {
  const t = Math.min(elapsed / SPEEDUP_MS, 1);
  return START_BPM + (END_BPM - START_BPM) * t;
}

function beatDurationAt(elapsed) {
  return 60_000 / bpmAt(elapsed);
}

function perfectWindowForBeat() {
  return Math.max(MIN_PERFECT_MS, state.beatDuration * 0.14);
}

function goodWindowForBeat() {
  return Math.max(MIN_GOOD_MS, state.beatDuration * 0.28);
}

function unlockAudio() {
  if (!audioContext) {
    audioContext = new AudioContext();
  }

  if (audioContext.state === "suspended") {
    audioContext.resume();
  }
}

function playTone({ frequency, duration, type = "sine", gain = 0.08, slideTo = null, delay = 0 }) {
  if (!audioContext) {
    return;
  }

  const start = audioContext.currentTime + delay;
  const osc = audioContext.createOscillator();
  const amp = audioContext.createGain();
  osc.type = type;
  osc.frequency.setValueAtTime(frequency, start);

  if (slideTo !== null) {
    osc.frequency.exponentialRampToValueAtTime(slideTo, start + duration);
  }

  amp.gain.setValueAtTime(0.0001, start);
  amp.gain.exponentialRampToValueAtTime(gain, start + 0.012);
  amp.gain.exponentialRampToValueAtTime(0.0001, start + duration);
  osc.connect(amp);
  amp.connect(audioContext.destination);
  osc.start(start);
  osc.stop(start + duration + 0.02);
}

function playSuccessSound() {
  playTone({ frequency: 660, slideTo: 990, duration: 0.09, type: "triangle", gain: 0.075 });
  playTone({ frequency: 1320, duration: 0.055, type: "sine", gain: 0.035, delay: 0.035 });
}

function playWrongSound() {
  playTone({ frequency: 190, slideTo: 82, duration: 0.16, type: "sawtooth", gain: 0.06 });
}

function playSkipSound() {
  playTone({ frequency: 520, duration: 0.035, type: "sine", gain: 0.018 });
}

function createTile(value, lane, className = "") {
  const tile = document.createElement("div");
  tile.className = `tile ${className}`.trim();
  tile.textContent = value;
  lane.appendChild(tile);
  return tile;
}

function setFeedback(text, type = "") {
  els.feedback.textContent = text;
  els.feedback.className = `feedback ${type}`.trim();
}

function updateHearts() {
  els.hearts.innerHTML = "";
  for (let i = 0; i < 3; i += 1) {
    const heart = document.createElement("div");
    heart.className = `heart ${i >= state.health ? "lost" : ""}`.trim();
    els.hearts.appendChild(heart);
  }
}

function updateCombo() {
  els.comboCount.textContent = state.combo;
  const tier = state.combo >= 100 ? 4 : state.combo >= 60 ? 3 : state.combo >= 20 ? 2 : state.combo >= 10 ? 1 : 0;
  const growSteps = Math.min(Math.floor(state.combo / 10), 10);
  els.comboPanel.className = `combo-panel tier-${tier}`.trim();
  els.comboPanel.style.transform = `scale(${1 + growSteps * 0.055})`;
}

function updateHud() {
  els.score.textContent = state.score;
  updateHearts();
  updateCombo();
}

function applyPenalty(text) {
  state.health -= 1;
  state.combo = 0;
  playWrongSound();
  updateHud();
  setFeedback(text, "bad");
  if (state.health <= 0) {
    endGame();
  }
}

function reward(kind, points) {
  state.score += points;
  state.combo += 1;
  playSuccessSound();
  updateHud();
  setFeedback(kind, kind === "Perfect" ? "perfect" : "good");
}

function judgePress(now) {
  if (state.phase !== "running" || state.lastJudgedBeat === state.currentBeat) {
    return;
  }

  flashButton();

  const elapsedInBeat = now - state.beatStartTime;
  const stopStart = state.beatDuration * SLIDE_RATIO;
  const judgeCenter = stopStart + (state.beatDuration - stopStart) * 0.5;
  const delta = Math.abs(elapsedInBeat - judgeCenter);
  state.lastJudgedBeat = state.currentBeat;

  if (!state.current.shouldPress) {
    applyPenalty("Wrong");
    return;
  }

  if (delta <= perfectWindowForBeat()) {
    reward("Perfect", 120);
  } else if (delta <= goodWindowForBeat()) {
    reward("Good", 80);
  } else {
    applyPenalty("Bad");
  }
}

function missOrSkipIfNeeded() {
  if (state.phase !== "running" || state.lastJudgedBeat === state.currentBeat) {
    return;
  }

  state.lastJudgedBeat = state.currentBeat;

  if (state.current.shouldPress) {
    applyPenalty("Miss");
    return;
  }

  playSkipSound();
  setFeedback("Skip", "");
}

function layoutTiles(progress) {
  const width = els.topLane.clientWidth;
  const centerX = width * 0.5;
  const move = Math.min(progress / SLIDE_RATIO, 1);
  const topPreview1X = width * 0.16;
  const topPreview2X = width * -0.18;
  const topCurrentX = topPreview1X + (centerX - topPreview1X) * move;
  const topP1X = topPreview2X + (topPreview1X - topPreview2X) * move;
  const topP2X = width * -0.52 + (topPreview2X - width * -0.52) * move;
  const bottomPreview1X = width * 0.84;
  const bottomPreview2X = width * 1.18;
  const bottomCurrentX = bottomPreview1X + (centerX - bottomPreview1X) * move;
  const bottomP1X = bottomPreview2X + (bottomPreview1X - bottomPreview2X) * move;
  const bottomP2X = width * 1.52 + (bottomPreview2X - width * 1.52) * move;
  const entries = [
    { beat: state.current, topX: topCurrentX, bottomX: bottomCurrentX, cls: "" },
    { beat: state.queue[0], topX: topP1X, bottomX: bottomP1X, cls: "preview" },
    { beat: state.queue[1], topX: topP2X, bottomX: bottomP2X, cls: "preview" },
  ];

  els.topLane.innerHTML = "";
  els.bottomLane.innerHTML = "";

  for (const entry of entries) {
    const topTile = createTile(entry.beat.top, els.topLane, entry.cls);
    const bottomTile = createTile(entry.beat.bottom, els.bottomLane, entry.cls);
    topTile.style.left = `${entry.topX}px`;
    bottomTile.style.left = `${entry.bottomX}px`;
  }
}

function advanceBeat(now) {
  missOrSkipIfNeeded();
  if (state.phase !== "running") {
    return;
  }

  state.current = state.queue.shift();
  ensureQueue();
  state.beatStartTime = now;
  state.beatDuration = beatDurationAt(now - state.startTime);
  state.currentBeat += 1;
  els.bpm.textContent = Math.round(bpmAt(now - state.startTime));
}

function updateCountdown(now) {
  const elapsed = now - state.countdownStartTime;
  const step = Math.min(Math.floor(elapsed / COUNTDOWN_STEP_MS), COUNTDOWN_BEATS.length - 1);

  if (step !== state.countdownStep) {
    state.countdownStep = step;
    els.countdown.textContent = COUNTDOWN_BEATS[step];
    els.countdown.classList.remove("pulse");
    void els.countdown.offsetWidth;
    els.countdown.classList.add("pulse");
  }

  if (elapsed >= COUNTDOWN_STEP_MS * COUNTDOWN_BEATS.length) {
    beginRun(now);
  }
}

function frame(now) {
  if (state.phase === "countdown") {
    updateCountdown(now);
    layoutTiles(1);
    state.rafId = requestAnimationFrame(frame);
    return;
  }

  if (state.phase !== "running") {
    return;
  }

  while (now - state.beatStartTime >= state.beatDuration) {
    advanceBeat(state.beatStartTime + state.beatDuration);
  }

  const progress = Math.max(0, Math.min((now - state.beatStartTime) / state.beatDuration, 1));
  layoutTiles(progress);
  els.bpm.textContent = Math.round(bpmAt(now - state.startTime));
  state.rafId = requestAnimationFrame(frame);
}

function flashButton() {
  els.hitButton.classList.add("active");
  window.setTimeout(() => els.hitButton.classList.remove("active"), 90);
}

function prepareBeats() {
  state.queue = [];
  ensureQueue();
  state.current = state.queue.shift();
  ensureQueue();
}

function beginRun(now) {
  state.phase = "running";
  state.startTime = now;
  state.beatStartTime = now;
  state.beatDuration = beatDurationAt(0);
  state.currentBeat = 0;
  state.lastJudgedBeat = -1;
  els.countdown.hidden = true;
  setFeedback("Start", "");
}

function startGame() {
  cancelAnimationFrame(state.rafId);
  state.phase = "countdown";
  state.countdownStartTime = performance.now();
  state.countdownStep = -1;
  state.beatDuration = beatDurationAt(0);
  state.health = 3;
  state.score = 0;
  state.combo = 0;
  state.currentBeat = 0;
  state.lastJudgedBeat = -1;
  prepareBeats();
  els.gameOver.hidden = true;
  els.countdown.hidden = false;
  els.bpm.textContent = START_BPM;
  setFeedback("Ready", "");
  updateHud();
  layoutTiles(1);
  state.rafId = requestAnimationFrame(frame);
}

function endGame() {
  state.phase = "over";
  cancelAnimationFrame(state.rafId);
  els.finalScore.textContent = `Score ${state.score}`;
  els.gameOver.hidden = false;
}

els.hitButton.addEventListener("pointerdown", (event) => {
  event.preventDefault();
  unlockAudio();
  judgePress(performance.now());
});

window.addEventListener("keydown", (event) => {
  if (event.code === "Space") {
    event.preventDefault();
    if (event.repeat) {
      return;
    }
    unlockAudio();
    judgePress(performance.now());
  }
});

els.restartButton.addEventListener("click", () => {
  unlockAudio();
  startGame();
});

startGame();
