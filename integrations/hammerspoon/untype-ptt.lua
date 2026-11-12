-- untype dictation on the two keys beside Enter (' and \ on the ABC layout)
--
--   Hold both keys       record while held, stop and submit on release
--   Tap both keys        record hands-free; then Enter types and sends,
--                        both keys again type only, Esc discards
--
-- Either key alone still types normally. Each key is held back for a moment to
-- see whether the other one follows, then passed on to the app in front.
--
-- Keys are matched by physical position, so this works on every input layout.
--
-- untype's hotkey is plain F16. This module presses that hidden key while both
-- keys are down and releases it when they come up; untype itself tells a tap
-- from a hold and handles Enter and Esc. The key goes straight to the untype
-- process, because posted the ordinary way it only reaches whichever app is in
-- front.

local M = {}

local BUNDLE_ID = "com.local.untype"
local KEY = "f16"
local KEY_CODE = 106
local QUOTE_KEY = 39
local BACKSLASH_KEY = 42
-- The second key must arrive within this time to count as pressing both.
local CHORD_SECONDS = 0.07
-- Marks keys this module re-sends, so its own listener lets them through.
M.REPLAY_MARKER = 0x55505454

-- Loaded at startup so hs.ipc calls never trigger a lazy extension load.
local application = hs.application
local timer = hs.timer
local event = hs.eventtap.event
local userDataProperty = event.properties.eventSourceUserData

-- idle | holding
M.mode = "idle"
-- Both keys are currently down as a chord.
M.down = false

local isChordKey = { [QUOTE_KEY] = true, [BACKSLASH_KEY] = true }
-- Chord keys whose key-up must not reach the app in front.
local swallowUp = {}
-- First key of a possible chord, held back until the window closes.
local pendingCode = nil
local pendingEvent = nil
local pendingTimer = nil

local function sendKey(down)
  local app = application.applicationsForBundleID(BUNDLE_ID)[1]
  if app then
    event.newKeyEvent({}, KEY, down):post(app)
  end
end

local function onPress()
  if M.mode == "idle" then
    sendKey(true)
    M.mode = "holding"
  end
end

local function onRelease()
  if M.mode == "holding" then
    sendKey(false)
    M.mode = "idle"
  end
end

local function replayable(e)
  local copy = e:copy()
  copy:setProperty(userDataProperty, M.REPLAY_MARKER)
  return copy
end

local function clearPending()
  if pendingTimer then
    pendingTimer:stop()
  end
  pendingCode, pendingEvent, pendingTimer = nil, nil, nil
end

-- The window closed without a chord: hand the held-back key to the app.
local function flushPending()
  local held = pendingEvent
  clearPending()
  if held then
    held:post()
  end
end

M.tap = hs.eventtap.new({ event.types.keyDown, event.types.keyUp }, function(e)
  if e:getProperty(userDataProperty) == M.REPLAY_MARKER then
    return false
  end

  local code = e:getKeyCode()
  local isDown = e:getType() == event.types.keyDown

  if not isChordKey[code] then
    if isDown then
      if pendingCode then
        flushPending()
        replayable(e):post()
        return true
      end
    end
    return false
  end

  if isDown then
    if swallowUp[code] then
      return true
    end
    local flags = e:getFlags()
    if flags.cmd or flags.alt or flags.ctrl or flags.shift or flags.fn then
      if pendingCode then
        flushPending()
        replayable(e):post()
        return true
      end
      return false
    end
    if pendingCode == code then
      return true
    end
    if pendingCode then
      clearPending()
      M.down = true
      swallowUp[QUOTE_KEY] = true
      swallowUp[BACKSLASH_KEY] = true
      onPress()
      return true
    end
    pendingCode = code
    pendingEvent = replayable(e)
    pendingTimer = timer.doAfter(CHORD_SECONDS, flushPending)
    return true
  end

  if swallowUp[code] then
    swallowUp[code] = nil
    if M.down then
      M.down = false
      onRelease()
    end
    return true
  end
  if pendingCode == code then
    flushPending()
    replayable(e):post()
    return true
  end
  return false
end)
M.tap:start()

return M
