const statusEl = document.getElementById("status");
const touchpad = document.getElementById("touchpad");
const keyboardPanel = document.getElementById("keyboardPanel");
const dragLockButton = document.getElementById("dragLock");
const copySelectionButton = document.getElementById("copySelection");
const pasteClipboardButton = document.getElementById("pasteClipboard");
const scrollRail = document.getElementById("scrollRail");
const scrollThumb = document.getElementById("scrollThumb");
const textInput = document.getElementById("textInput");
const pasteTextButton = document.getElementById("pasteText");
const pasteEnterTextButton = document.getElementById("pasteEnterText");
const typeBackspaceButton = document.getElementById("typeBackspace");
const DEFAULT_SENSITIVITY = 1.5;

const TAP_MAX_MS = 180;
const TAP_MAX_DISTANCE = 10;
const DOUBLE_TAP_MS = 280;
const LONG_PRESS_MS = 420;
const SEND_INTERVAL_MS = 16;
const EDGE_SCROLL_STEP_PX = 6;
const EDGE_SCROLL_MULTIPLIER = 2.4;
const EDGE_HOLD_ZONE_PX = 18;
const EDGE_HOLD_INTERVAL_MS = 70;
const EDGE_HOLD_AMOUNT = 5;

let ws;
let reconnectTimer;
let reconnectDelay = 400;
let lastPointerId = null;
let lastX = 0;
let lastY = 0;
let startX = 0;
let startY = 0;
let startTime = 0;
let lastTapTime = 0;
let singleTapTimer;
let longPressTimer;
let dragging = false;
let dragLocked = false;
let lastSendTime = 0;
let pendingDx = 0;
let pendingDy = 0;
let edgeScrolling = false;
let edgeScrollLastY = 0;
let edgeScrollRemainder = 0;
let edgeHoldTimer;
let edgeHoldDirection = 0;
let ignorePointerUntil = 0;

function connect() {
  clearTimeout(reconnectTimer);
  const protocol = location.protocol === "https:" ? "wss:" : "ws:";
  ws = new WebSocket(`${protocol}//${location.host}/ws`);

  ws.addEventListener("open", () => {
    reconnectDelay = 400;
    setStatus(true);
  });

  ws.addEventListener("close", () => {
    setStatus(false);
    reconnectTimer = setTimeout(connect, reconnectDelay);
    reconnectDelay = Math.min(reconnectDelay * 1.6, 5000);
  });

  ws.addEventListener("error", () => {
    setStatus(false);
    ws.close();
  });
}

function setStatus(connected) {
  statusEl.textContent = connected ? "Connected" : "Disconnected";
  statusEl.classList.toggle("connected", connected);
  statusEl.classList.toggle("disconnected", !connected);
}

function send(message) {
  if (!ws || ws.readyState !== WebSocket.OPEN) {
    return;
  }
  ws.send(JSON.stringify(message));
}

function pasteTypedText() {
  const text = textInput.value;
  if (!text) {
    return;
  }
  send({ type: "paste_text", text });
  textInput.value = "";
  textInput.focus();
  flashButton(pasteTextButton, "Send");
}

function pasteAndEnterTypedText() {
  const text = textInput.value;
  if (!text) {
    return;
  }
  send({ type: "paste_enter_text", text });
  textInput.value = "";
  textInput.focus();
  flashButton(pasteEnterTextButton, "Search");
}

function flashButton(button, label) {
  button.textContent = "Sent";
  setTimeout(() => {
    button.textContent = label;
  }, 700);
}

function deleteFromTextInput() {
  const start = textInput.selectionStart ?? textInput.value.length;
  const end = textInput.selectionEnd ?? textInput.value.length;

  if (start !== end) {
    textInput.setRangeText("", start, end, "end");
    textInput.focus();
    return;
  }

  if (start > 0) {
    const chars = Array.from(textInput.value);
    const before = Array.from(textInput.value.slice(0, start));
    const after = textInput.value.slice(start);
    before.pop();
    textInput.value = before.join("") + after;
    textInput.selectionStart = before.join("").length;
    textInput.selectionEnd = before.join("").length;
    textInput.focus();
    return;
  }

  send({ type: "key", key: "backspace" });
  flashButton(typeBackspaceButton, "⌫");
}

function isControlTarget(target) {
  return Boolean(target.closest("button, textarea, .keyboard-panel, .top-actions, .scroll-rail"));
}

function sensitivity() {
  return DEFAULT_SENSITIVITY;
}

function queueMove(dx, dy) {
  pendingDx += dx * sensitivity();
  pendingDy += dy * sensitivity();

  const now = performance.now();
  if (now - lastSendTime < SEND_INTERVAL_MS) {
    return;
  }

  const moveX = Math.round(pendingDx);
  const moveY = Math.round(pendingDy);
  pendingDx -= moveX;
  pendingDy -= moveY;

  if (moveX !== 0 || moveY !== 0) {
    send({ type: "move", dx: moveX, dy: moveY });
    lastSendTime = now;
  }
}

function flushMove() {
  const moveX = Math.round(pendingDx);
  const moveY = Math.round(pendingDy);
  pendingDx = 0;
  pendingDy = 0;

  if (moveX !== 0 || moveY !== 0) {
    send({ type: "move", dx: moveX, dy: moveY });
    lastSendTime = performance.now();
  }
}

function distanceFromStart(x, y) {
  return Math.hypot(x - startX, y - startY);
}

function beginDrag() {
  if (dragging) {
    return;
  }
  dragging = true;
  touchpad.classList.add("dragging");
  send({ type: "mouse_down", button: "left" });
}

function endDrag() {
  if (!dragging) {
    return;
  }
  dragging = false;
  touchpad.classList.remove("dragging");
  send({ type: "mouse_up", button: "left" });
}

function setDragLock(locked) {
  dragLocked = locked;
  touchpad.classList.toggle("drag-locked", dragLocked);
  dragLockButton.classList.toggle("active", dragLocked);
  dragLockButton.textContent = dragLocked ? "Drop" : "Grab";
}

function toggleDragLock() {
  if (dragLocked) {
    setDragLock(false);
    endDrag();
    return;
  }

  beginDrag();
  setDragLock(true);
}

function copySelection() {
  if (dragLocked) {
    setDragLock(false);
    endDrag();
    setTimeout(() => send({ type: "shortcut", shortcut: "copy" }), 80);
  } else {
    send({ type: "shortcut", shortcut: "copy" });
  }

  flashButton(copySelectionButton, "Copy");
}

function pasteClipboard() {
  send({ type: "shortcut", shortcut: "paste" });
  flashButton(pasteClipboardButton, "Paste");
}

touchpad.addEventListener("pointerdown", (event) => {
  if (isControlTarget(event.target)) {
    return;
  }

  if (edgeScrolling || performance.now() < ignorePointerUntil) {
    event.preventDefault();
    return;
  }

  if (lastPointerId !== null) {
    return;
  }

  event.preventDefault();
  touchpad.setPointerCapture(event.pointerId);
  lastPointerId = event.pointerId;
  lastX = event.clientX;
  lastY = event.clientY;
  startX = event.clientX;
  startY = event.clientY;
  startTime = performance.now();
  pendingDx = 0;
  pendingDy = 0;

  if (!dragLocked) {
    longPressTimer = setTimeout(() => {
      if (lastPointerId === event.pointerId && distanceFromStart(lastX, lastY) <= TAP_MAX_DISTANCE) {
        beginDrag();
      }
    }, LONG_PRESS_MS);
  }
});

touchpad.addEventListener("pointermove", (event) => {
  if (isControlTarget(event.target)) {
    return;
  }

  if (edgeScrolling || performance.now() < ignorePointerUntil) {
    event.preventDefault();
    return;
  }

  if (event.pointerId !== lastPointerId) {
    return;
  }

  event.preventDefault();
  const dx = event.clientX - lastX;
  const dy = event.clientY - lastY;
  lastX = event.clientX;
  lastY = event.clientY;

  if (!dragging && distanceFromStart(lastX, lastY) > TAP_MAX_DISTANCE) {
    clearTimeout(longPressTimer);
  }

  queueMove(dx, dy);
});

function finishPointer(event) {
  if (event.pointerId !== lastPointerId) {
    return;
  }

  event.preventDefault();
  clearTimeout(longPressTimer);
  touchpad.releasePointerCapture(event.pointerId);
  lastPointerId = null;

  if (dragLocked) {
    flushMove();
    return;
  }

  if (dragging) {
    endDrag();
    return;
  }

  const elapsed = performance.now() - startTime;
  const moved = distanceFromStart(event.clientX, event.clientY);
  if (elapsed <= TAP_MAX_MS && moved <= TAP_MAX_DISTANCE) {
    const now = performance.now();
    if (now - lastTapTime <= DOUBLE_TAP_MS) {
      clearTimeout(singleTapTimer);
      send({ type: "double_click" });
      lastTapTime = 0;
    } else {
      lastTapTime = now;
      singleTapTimer = setTimeout(() => {
        send({ type: "click", button: "left" });
        lastTapTime = 0;
      }, DOUBLE_TAP_MS);
    }
  } else {
    flushMove();
  }
}

touchpad.addEventListener("pointerup", finishPointer);
touchpad.addEventListener("pointercancel", (event) => {
  if (event.pointerId === lastPointerId) {
    clearTimeout(longPressTimer);
    if (!dragLocked) {
      endDrag();
    }
    lastPointerId = null;
  }
});

touchpad.addEventListener(
  "touchstart",
  (event) => {
    if (isControlTarget(event.target)) {
      return;
    }

    if (event.touches.length >= 2) {
      event.preventDefault();
      clearTimeout(longPressTimer);
      clearTimeout(singleTapTimer);
      lastTapTime = 0;

      if (!dragLocked) {
        send({ type: "click", button: "right" });
        touchpad.classList.add("right-clicking");
        setTimeout(() => touchpad.classList.remove("right-clicking"), 140);
      }
    }
  },
  { passive: false }
);

dragLockButton.addEventListener("click", toggleDragLock);
copySelectionButton.addEventListener("click", copySelection);
pasteClipboardButton.addEventListener("click", pasteClipboard);
pasteTextButton.addEventListener("click", pasteTypedText);
pasteEnterTextButton.addEventListener("click", pasteAndEnterTypedText);
typeBackspaceButton.addEventListener("click", deleteFromTextInput);

scrollRail.addEventListener("pointerdown", (event) => {
  event.preventDefault();
  edgeScrolling = true;
  edgeScrollLastY = event.clientY;
  edgeScrollRemainder = 0;
  ignorePointerUntil = performance.now() + 350;
  scrollRail.setPointerCapture(event.pointerId);
  scrollRail.classList.add("active");
  moveScrollThumb(event.clientY);
});

scrollRail.addEventListener("pointermove", (event) => {
  if (!edgeScrolling) {
    return;
  }

  event.preventDefault();
  const dy = event.clientY - edgeScrollLastY;
  edgeScrollLastY = event.clientY;
  edgeScrollRemainder += (dy / EDGE_SCROLL_STEP_PX) * EDGE_SCROLL_MULTIPLIER;

  const amount = Math.trunc(edgeScrollRemainder);
  if (amount !== 0) {
    send({ type: "scroll", amount: -amount });
    edgeScrollRemainder -= amount;
  }
  moveScrollThumb(event.clientY);
});

function finishEdgeScroll(event) {
  if (!edgeScrolling) {
    return;
  }

  edgeScrolling = false;
  edgeScrollRemainder = 0;
  stopEdgeHoldScroll();
  ignorePointerUntil = performance.now() + 250;
  scrollRail.releasePointerCapture(event.pointerId);
  scrollRail.classList.remove("active");
  scrollThumb.style.top = "50%";
}

function moveScrollThumb(clientY) {
  const rail = scrollRail.getBoundingClientRect();
  const thumbHalf = scrollThumb.offsetHeight / 2;
  const y = Math.max(thumbHalf, Math.min(rail.height - thumbHalf, clientY - rail.top));
  scrollThumb.style.top = `${y}px`;
  updateEdgeHoldScroll(y, rail.height, thumbHalf);
}

function updateEdgeHoldScroll(thumbCenterY, railHeight, thumbHalf) {
  if (thumbCenterY <= thumbHalf + EDGE_HOLD_ZONE_PX) {
    startEdgeHoldScroll(1);
    return;
  }

  if (thumbCenterY >= railHeight - thumbHalf - EDGE_HOLD_ZONE_PX) {
    startEdgeHoldScroll(-1);
    return;
  }

  stopEdgeHoldScroll();
}

function startEdgeHoldScroll(direction) {
  if (edgeHoldDirection === direction && edgeHoldTimer) {
    return;
  }

  stopEdgeHoldScroll();
  edgeHoldDirection = direction;
  edgeHoldTimer = setInterval(() => {
    send({ type: "scroll", amount: edgeHoldDirection * EDGE_HOLD_AMOUNT });
  }, EDGE_HOLD_INTERVAL_MS);
}

function stopEdgeHoldScroll() {
  if (edgeHoldTimer) {
    clearInterval(edgeHoldTimer);
    edgeHoldTimer = undefined;
  }
  edgeHoldDirection = 0;
}

scrollRail.addEventListener("pointerup", finishEdgeScroll);
scrollRail.addEventListener("pointercancel", finishEdgeScroll);

keyboardPanel.addEventListener(
  "touchmove",
  (event) => {
    event.stopPropagation();
  },
  { passive: false }
);

document.addEventListener(
  "touchmove",
  (event) => {
    if (event.target.closest(".keyboard-panel")) {
      return;
    }
    event.preventDefault();
  },
  { passive: false }
);

connect();
