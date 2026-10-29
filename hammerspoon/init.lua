-- MeetingRec menu bar.
--
-- Deliberately uses only hs.menubar, hs.task, hs.timer, hs.dialog, hs.notify
-- and hs.autoLaunch. None of those need the Accessibility permission — that one covers
-- hs.window, hs.eventtap and hs.uielement (window management, input synthesis,
-- reading other apps' UI), which this build never touches. Accessibility is the
-- broadest grant macOS offers, so it stays declined. If you ever add an API
-- from that list, this comment is the thing that stopped being true.
--
-- Hammerspoon still needs its own Microphone and System Audio Recording grants:
-- permissions attach to the launcher, not to the binaries it spawns, so
-- whatever Terminal was granted does nothing here.

-- Where the meetingrec repo is cloned. The README's install command fills this in
-- automatically; edit it by hand only if you move the repo.
local REPO = os.getenv("HOME") .. "/meetingrec"

local MEETINGREC = REPO .. "/bin/meetingrec"
local LOGFILE = os.getenv("HOME") .. "/.hammerspoon/meetingrec.log"

-- ---------------------------------------------------------------------------
-- Logging
--
-- Hammerspoon's error console lives in memory and dies with the process, so a
-- misbehaving menu bar item leaves nothing to read afterwards. On 2026-08-04
-- the button detached mid-meeting and the only fix was a relaunch — which threw
-- away the very evidence that would have explained it. Everything below exists
-- so the next occurrence is diagnosable instead of guessed at.
-- ---------------------------------------------------------------------------

local function log(fmt, ...)
  local ok, line = pcall(string.format, fmt, ...)
  if not ok then line = tostring(fmt) end
  local f = io.open(LOGFILE, "a")
  if f then
    f:write(os.date("%Y-%m-%d %H:%M:%S "), line, "\n")
    f:close()
  end
end

-- Uncaught errors in callbacks are printed, not raised anywhere catchable, so
-- the tee has to sit on print itself to see them at all.
local rawprint = print
print = function(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  log("print: %s", table.concat(parts, "\t"))
  return rawprint(...)
end

-- A callback that throws leaves the button in an indeterminate state and says
-- nothing about why. xpcall keeps the traceback; the return value is passed
-- through untouched because setMenu's callback has to return its menu table.
local function guard(name, fn)
  return function(...)
    local args = table.pack(...)
    local ok, res = xpcall(function() return fn(table.unpack(args, 1, args.n)) end,
                           debug.traceback)
    if not ok then
      log("ERROR in %s: %s", name, tostring(res))
      return nil
    end
    return res
  end
end

-- hs.processInfo is absent from this build's docs, so it is read defensively:
-- a nil index here would abort the whole config and leave no menu bar at all.
local pid = (type(hs.processInfo) == "table" and hs.processInfo.processID) or "?"
log("--- init.lua loading (pid %s) ---", tostring(pid))

local menu = hs.menubar.new()
if not menu then
  log("FATAL: hs.menubar.new() returned nil — no menu bar item")
  hs.notify.new({ title = "MeetingRec",
                  informativeText = "Could not create the menu bar item." }):send()
  return
end

-- Hold a global reference: a menubar object reachable only from locals can be
-- garbage-collected, which makes the button vanish. Matters most when this file
-- is loaded with require() from an existing init.lua.
_G.meetingrecMenu = menu

local isRecording = false
local startTime = nil
local sessionDir = nil
local tickTimer = nil

local IDLE_TITLE = "○"

-- ---------------------------------------------------------------------------
-- Display
-- ---------------------------------------------------------------------------

local function elapsedMinutes()
  if not startTime then return 0 end
  return math.floor((os.time() - startTime) / 60)
end

local function refreshTitle()
  if isRecording then
    menu:setTitle("● " .. elapsedMinutes() .. "m")
  else
    menu:setTitle(IDLE_TITLE)
  end
end

local function startTicking()
  if tickTimer then tickTimer:stop() end
  -- Started and stopped with the recording rather than left running: an idle
  -- clock has nothing to count.
  tickTimer = hs.timer.doEvery(30, guard("tick", refreshTitle))
  refreshTitle()
end

local function stopTicking()
  if tickTimer then tickTimer:stop(); tickTimer = nil end
  refreshTitle()
end

local function notify(title, text)
  hs.notify.new({ title = title, informativeText = text }):send()
end

-- ---------------------------------------------------------------------------
-- Shelling out
-- ---------------------------------------------------------------------------

local function run(args, onDone)
  log("run: meetingrec %s", table.concat(args, " "))
  -- Absolute path, so Hammerspoon's minimal PATH is irrelevant.
  local task = hs.task.new(MEETINGREC, guard("task callback", function(exitCode, stdOut, stdErr)
    log("run: exit %s", tostring(exitCode))
    if exitCode ~= 0 then
      log("run: stderr %s", tostring(stdErr))
    end
    onDone(exitCode, stdOut or "", stdErr or "")
  end), args)
  if not task then
    log("ERROR: hs.task.new failed for %s", MEETINGREC)
    notify("MeetingRec", "Could not launch " .. MEETINGREC)
    return
  end
  task:start()
end

local function doStart(micOnly)
  local args = { "start" }

  local button, title = hs.dialog.textPrompt(
    micOnly and "Start recording (mic only)" or "Start recording",
    -- The disclosure obligation is a workflow step, not a code path: bot-free
    -- capture removes the notetaker from the participant list, it does not
    -- remove the need to say you're recording.
    "Optional title for this session.\n\nRemember to tell the other side you're recording.",
    "", "Start", "Cancel")
  if button == "Cancel" then return end
  if title and title ~= "" then table.insert(args, title) end
  if micOnly then table.insert(args, "--mic-only") end

  run(args, function(exitCode, stdOut, stdErr)
    if exitCode ~= 0 then
      notify("MeetingRec — start failed", (stdErr ~= "" and stdErr or stdOut))
      return
    end
    isRecording = true
    startTime = os.time()
    sessionDir = stdOut:match("recording: ([^\n]+)")
    startTicking()
    notify("MeetingRec", micOnly and "Recording (mic only)" or "Recording both tracks")
  end)
end

local function doStop()
  run({ "stop" }, function(exitCode, stdOut, stdErr)
    isRecording = false
    startTime = nil
    stopTicking()
    if exitCode ~= 0 then
      notify("MeetingRec — stop failed", (stdErr ~= "" and stdErr or stdOut))
      return
    end
    -- Surface a silent/short recording here rather than letting it be
    -- discovered later, when the meeting is gone.
    local warning = stdOut:match("WARNING: ([^\n]+)") or stdErr:match("WARNING: ([^\n]+)")
    if warning then
      notify("MeetingRec — check this recording", warning)
    else
      notify("MeetingRec", stdOut:match("(stopped[^\n]*)") or "Stopped")
    end
  end)
end

-- Hammerspoon holds state in memory, which a config reload would silently
-- discard mid-recording — leaving the button claiming idle while ffmpeg runs.
-- Asking the CLI on load makes the menu bar reflect reality instead.
local function resync()
  run({ "status" }, function(_, stdOut, _)
    local secs, dir = stdOut:match("^recording (%d+) ([^\n]+)")
    if secs then
      isRecording = true
      startTime = os.time() - tonumber(secs)
      sessionDir = dir
      startTicking()
    else
      isRecording = false
      startTime = nil
      stopTicking()
    end
  end)
end

-- ---------------------------------------------------------------------------
-- Updates
--
-- `meetingrec update --check` only asks GitHub what's new and changes nothing,
-- so it's safe on a timer. Updating itself is always a click.
-- ---------------------------------------------------------------------------

local updatesAvailable = 0
local CHECK_EVERY = 24 * 60 * 60
local MAX_LISTED = 10

-- The CLI's own error line, without the install log printed before it.
local function cliError(stdErr, stdOut)
  return stdErr:match("meetingrec: ([^\n]+)") or (stdErr ~= "" and stdErr or stdOut)
end

local function doUpdate()
  notify("MeetingRec", "Updating…")
  run({ "update", "--from-menu" }, function(exitCode, stdOut, stdErr)
    if exitCode ~= 0 then
      notify("MeetingRec — update failed", cliError(stdErr, stdOut))
      return
    end
    updatesAvailable = 0
    local now = stdOut:match("updated %S+ → (%x+)") or stdOut:match("already up to date %((%x+)%)")
    notify("MeetingRec", now and ("Updated to " .. now) or "Updated")
    -- install.sh may have rewritten this file. Deferred for the same reason
    -- as "Reload config" in the menu below.
    hs.timer.doAfter(0.1, hs.reload)
  end)
end

-- interactive: the user clicked, so every outcome gets an answer. The daily
-- check stays silent and only relabels the menu item.
local function checkForUpdates(interactive)
  if isRecording and not interactive then return end
  run({ "update", "--check" }, function(exitCode, stdOut, stdErr)
    if exitCode ~= 0 then
      -- Being offline is normal for a laptop; only a click deserves a reply.
      if interactive then
        notify("MeetingRec — couldn't check for updates", cliError(stdErr, stdOut))
      end
      return
    end
    local n = tonumber(stdOut:match("^available (%d+)"))
    updatesAvailable = n or 0
    if n then log("update check: %d available", n) end
    if not interactive then return end
    if not n then
      notify("MeetingRec", "MeetingRec is up to date")
      return
    end

    local lines = {}
    for line in stdOut:gmatch("[^\n]+") do
      if line:sub(1, 2) == "  " then lines[#lines + 1] = line:sub(3) end
    end
    -- Cut long lists so the dialog stays on screen.
    if #lines > MAX_LISTED then
      local more = #lines - MAX_LISTED
      for i = #lines, MAX_LISTED + 1, -1 do lines[i] = nil end
      lines[#lines + 1] = "…and " .. more .. " more"
    end
    local button = hs.dialog.blockAlert(
      n == 1 and "1 update available" or (n .. " updates available"),
      "What's new:\n" .. table.concat(lines, "\n") ..
        "\n\nUpdating takes a few seconds. Your recordings, notes, names and settings aren't changed.",
      "Update", "Later")
    if button == "Update" then doUpdate() end
  end)
end

-- ---------------------------------------------------------------------------
-- Menu
-- ---------------------------------------------------------------------------

menu:setMenu(guard("menu", function()
  if isRecording then
    return {
      { title = "Recording — " .. elapsedMinutes() .. " min", disabled = true },
      { title = "-" },
      { title = "Stop", fn = doStop },
      { title = "Open folder", fn = function()
          if sessionDir then hs.execute('open "' .. sessionDir .. '"') end
        end },
    }
  end
  return {
    { title = "Start recording…", fn = function() doStart(false) end },
    { title = "Start (mic only — on speakers)", fn = function() doStart(true) end },
    { title = "-" },
    -- Asked rather than assumed: OUTPUT_ROOT in config.sh can move it.
    { title = "Open recordings folder", fn = function()
        run({ "config", "get", "OUTPUT_ROOT" }, function(exitCode, stdOut)
          local dir = stdOut:match("^([^\n]+)")
          if exitCode ~= 0 or not dir then dir = REPO .. "/scribe/input" end
          hs.execute('open "' .. dir .. '"')
        end)
      end },
    { title = "Re-check status", fn = resync },
    { title = updatesAvailable > 0 and "Update available…" or "Check for updates…",
      fn = function() checkForUpdates(true) end },
    { title = "-" },
    -- hs.reload destroys the Lua state this callback is running inside, taking
    -- the menubar object with it mid-dispatch — the branch sawing off itself.
    -- Deferring by a tick lets the click return and the menu close first, so
    -- the teardown happens from a clean stack. Suspected cause of the button
    -- detaching on 2026-08-04; a reload could not fix it, only a relaunch.
    { title = "Reload config", fn = function()
        log("reload requested (deferred)")
        hs.timer.doAfter(0.1, hs.reload)
      end },
  }
end))

-- A button that's gone after a restart fails silently at the start of the next
-- call, so launch-at-login isn't left as a preferences checkbox to remember.
hs.autoLaunch(true)

-- Once a day, and a minute after loading: at login the network may not be up
-- yet. Global, like the menu, so the timers can't be garbage-collected.
local function quietCheck() checkForUpdates(false) end
_G.meetingrecUpdateTimer = hs.timer.doEvery(CHECK_EVERY, guard("update check", quietCheck))
_G.meetingrecFirstCheck = hs.timer.doAfter(60, guard("update check", quietCheck))

refreshTitle()
resync()
log("init.lua loaded; menu bar item created")
