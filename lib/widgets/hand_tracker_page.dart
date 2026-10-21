/// The hand-tracking page that runs inside a small WebView.
///
/// Hand-gesture logic adapted from the open-source (MIT licensed) orb UI
/// by Sagar Tamang (sagartamang.com): pinch with one hand and move to
/// spin, pinch with both hands and spread or close them to zoom. It uses
/// Google's MediaPipe HandLandmarker, loaded from the internet the first
/// time (the page needs a connection to start).
///
/// It sends small JSON messages to the app through the "EdithHands"
/// channel: {t:"rotate",dx,dy}, {t:"zoom",f}, {t:"status",hands,mode},
/// {t:"loading"}, {t:"ready"} and {t:"error",msg}.
const String handTrackerHtml = r'''
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<style>
  html, body { margin: 0; height: 100%; background: #000; overflow: hidden; }
  #v, #o {
    position: absolute; left: 0; top: 0; width: 100%; height: 100%;
    object-fit: cover;
  }
  #v { transform: scaleX(-1); }
</style>
</head>
<body>
<video id="v" playsinline muted autoplay></video>
<canvas id="o"></canvas>
<script>
const WASM = "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.35/wasm";
const BUNDLE = "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.35/vision_bundle.mjs";
const MODEL = "https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task";

const WRIST = 0, THUMB_TIP = 4, INDEX_TIP = 8, MIDDLE_MCP = 9;
const PINCH_ON = 0.32, PINCH_OFF = 0.45;
const ROTATE_SPEED = 5.0, SMOOTHING = 0.4;

const video = document.getElementById("v");
const overlay = document.getElementById("o");

function send(o) {
  try { EdithHands.postMessage(JSON.stringify(o)); } catch (e) {}
}
function d2(a, b) { return Math.hypot(a.x - b.x, a.y - b.y); }

let landmarker = null;
let running = false;
let lastVideoTime = -1;
const handStates = new Map();
let prevMode = "idle";
let prevSpinGrab = null;
let prevZoomDist = null;
let lastHands = -1;
let lastMode = "";

function emitStatus(hands, mode) {
  if (hands !== lastHands || mode !== lastMode) {
    lastHands = hands; lastMode = mode;
    send({ t: "status", hands: hands, mode: mode });
  }
}

function processHands(landmarks, labels) {
  const pinchedGrabs = [];
  const seen = new Set();
  const labelCount = {};

  landmarks.forEach((lm, i) => {
    const base = labels[i];
    labelCount[base] = (labelCount[base] || 0) + 1;
    const key = base + "#" + labelCount[base];
    seen.add(key);

    const handScale = d2(lm[WRIST], lm[MIDDLE_MCP]);
    if (handScale < 1e-6) return;
    const pinchRatio = d2(lm[THUMB_TIP], lm[INDEX_TIP]) / handScale;

    const raw = {
      x: 1 - (lm[THUMB_TIP].x + lm[INDEX_TIP].x) / 2,
      y: (lm[THUMB_TIP].y + lm[INDEX_TIP].y) / 2
    };

    let st = handStates.get(key);
    if (!st) { st = { pinching: false, grab: raw }; handStates.set(key, st); }

    if (st.pinching && pinchRatio > PINCH_OFF) st.pinching = false;
    else if (!st.pinching && pinchRatio < PINCH_ON) st.pinching = true;

    st.grab = {
      x: st.grab.x + (raw.x - st.grab.x) * SMOOTHING,
      y: st.grab.y + (raw.y - st.grab.y) * SMOOTHING
    };
    if (st.pinching) pinchedGrabs.push(st.grab);
  });

  for (const key of Array.from(handStates.keys())) {
    if (!seen.has(key)) handStates.delete(key);
  }

  const mode = pinchedGrabs.length >= 2 ? "zoom"
             : pinchedGrabs.length === 1 ? "spin" : "idle";

  if (mode !== prevMode) {
    prevSpinGrab = null; prevZoomDist = null; prevMode = mode;
  }

  if (mode === "spin") {
    const g = pinchedGrabs[0];
    if (prevSpinGrab) {
      const dx = g.x - prevSpinGrab.x;
      const dy = g.y - prevSpinGrab.y;
      if (Math.abs(dx) > 1e-4 || Math.abs(dy) > 1e-4) {
        send({ t: "rotate", dx: dx * ROTATE_SPEED, dy: dy * ROTATE_SPEED });
      }
    }
    prevSpinGrab = g;
  } else if (mode === "zoom") {
    const d = Math.hypot(pinchedGrabs[0].x - pinchedGrabs[1].x,
                         pinchedGrabs[0].y - pinchedGrabs[1].y);
    if (prevZoomDist && d > 1e-4) {
      const f = Math.min(1.18, Math.max(0.85, prevZoomDist / d));
      send({ t: "zoom", f: f });
    }
    prevZoomDist = d;
  }
  emitStatus(landmarks.length, mode);
}

function drawOverlay(landmarks) {
  const ctx = overlay.getContext("2d");
  const w = overlay.width, h = overlay.height;
  ctx.clearRect(0, 0, w, h);
  for (const lm of landmarks) {
    const t = lm[THUMB_TIP], ix = lm[INDEX_TIP];
    const tx = (1 - t.x) * w, ty = t.y * h;
    const ixx = (1 - ix.x) * w, iy = ix.y * h;
    const hs = d2(lm[WRIST], lm[MIDDLE_MCP]);
    const pinched = hs > 1e-6 && d2(t, ix) / hs < PINCH_ON;
    ctx.strokeStyle = pinched ? "#ffffff" : "rgba(47,224,255,0.6)";
    ctx.lineWidth = pinched ? 4 : 2;
    ctx.beginPath(); ctx.moveTo(tx, ty); ctx.lineTo(ixx, iy); ctx.stroke();
    ctx.fillStyle = pinched ? "#ffffff" : "rgba(47,224,255,0.9)";
    [[tx, ty], [ixx, iy]].forEach(function (p) {
      ctx.beginPath(); ctx.arc(p[0], p[1], pinched ? 9 : 6, 0, Math.PI * 2); ctx.fill();
    });
  }
}

function loop() {
  if (!running) return;
  requestAnimationFrame(loop);
  if (!landmarker || video.readyState < 2) return;
  if (video.currentTime === lastVideoTime) return;
  lastVideoTime = video.currentTime;
  const result = landmarker.detectForVideo(video, performance.now());
  const labels = result.handedness.map(function (h) {
    return (h[0] && h[0].categoryName) || "?";
  });
  processHands(result.landmarks, labels);
  drawOverlay(result.landmarks);
}

async function start() {
  try {
    send({ t: "loading" });
    const stream = await navigator.mediaDevices.getUserMedia({
      video: { width: 640, height: 480, facingMode: "user" },
      audio: false
    });
    video.srcObject = stream;
    await video.play();
    overlay.width = video.videoWidth || 640;
    overlay.height = video.videoHeight || 480;

    const mp = await import(BUNDLE);
    const fileset = await mp.FilesetResolver.forVisionTasks(WASM);
    const options = {
      baseOptions: { modelAssetPath: MODEL, delegate: "GPU" },
      runningMode: "VIDEO",
      numHands: 2,
      minHandDetectionConfidence: 0.6,
      minHandPresenceConfidence: 0.6,
      minTrackingConfidence: 0.6
    };
    try {
      landmarker = await mp.HandLandmarker.createFromOptions(fileset, options);
    } catch (e) {
      options.baseOptions = { modelAssetPath: MODEL, delegate: "CPU" };
      landmarker = await mp.HandLandmarker.createFromOptions(fileset, options);
    }
    running = true;
    send({ t: "ready" });
    loop();
  } catch (e) {
    send({ t: "error", msg: String((e && e.message) || e) });
  }
}
start();
</script>
</body>
</html>
''';
