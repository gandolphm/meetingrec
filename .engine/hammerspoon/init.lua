-- MeetingRec menu bar.
--
-- Deliberately uses only hs.menubar, hs.task, hs.timer, hs.dialog, hs.notify,
-- hs.settings, hs.focus and hs.autoLaunch. None of those need the Accessibility permission —
-- that one covers hs.window, hs.eventtap and hs.uielement (window management,
-- input synthesis, reading other apps' UI), which this build never touches. Accessibility is the
-- broadest grant macOS offers, so it stays declined. If you ever add an API
-- from that list, this comment is the thing that stopped being true.
--
-- Hammerspoon still needs its own Microphone and System Audio Recording grants:
-- permissions attach to the launcher, not to the binaries it spawns, so
-- whatever Terminal was granted does nothing here.

-- Where the meetingrec repo is cloned. The README's install command fills this in
-- automatically; edit it by hand only if you move the repo.
local REPO = os.getenv("HOME") .. "/meetingrec"

local MEETINGREC = REPO .. "/.engine/bin/meetingrec"
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

-- A message for after hs.reload, which clears notifications sent just before it.
local AFTER_RELOAD = "meetingrec.afterReload"

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
    -- A notification sent now would vanish with the reload, so the reloaded
    -- config shows it (see the end of this file).
    hs.settings.set(AFTER_RELOAD, now and ("Updated to " .. now) or "Updated")
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
-- Writing notes
--
-- Opens Claude Code in the skill's folder with the request typed in, waiting
-- for Enter: in the Claude app if it's installed, so no Terminal is needed,
-- otherwise in Terminal. Both are a plain `open` of a link, so no macOS
-- permission is involved. The skills work the same however Claude was started.
-- ---------------------------------------------------------------------------

local function urlEncode(s)
  return (s:gsub("[^%w%-%._~/]", function(c) return string.format("%%%02X", string.byte(c)) end))
end

local function writeUp(folder, request)
  local dir = REPO .. "/" .. folder
  local query = "?folder=" .. urlEncode(dir) .. "&q=" .. urlEncode(request)
  local _, opened = hs.execute('open "claude://code/new' .. query .. '"')
  if opened then
    log("write-up: Claude app in %s", dir)
    return
  end
  -- No Claude app: Claude Code's own link opens it in Terminal instead.
  query = "?cwd=" .. urlEncode(dir) .. "&q=" .. urlEncode(request)
  _, opened = hs.execute('open "claude-cli://open' .. query .. '"')
  if opened then
    log("write-up: Claude Code in Terminal in %s", dir)
    return
  end
  log("write-up: nothing handles claude:// or claude-cli:// links")
  notify("MeetingRec", "Couldn't open Claude. Install the Claude app, or type " ..
    folder .. " in Terminal.")
end

-- ---------------------------------------------------------------------------
-- Settings
--
-- Stored in ~/.config/meetingrec/config.sh and read and written through
-- `meetingrec config`, the command the skills use too, so the menu, Terminal
-- and Claude never disagree and the checks (the folder exists, personal and
-- team notes in separate vaults) live in one place. Values are cached: the menu
-- is rebuilt on every click, and asking the CLI each time would make it slow
-- to open.
-- ---------------------------------------------------------------------------

local HOME = os.getenv("HOME")
local settings = {}   -- NAME -> { value = "…", isDefault = true|false }

local function loadSettings(after)
  run({ "config", "list" }, function(exitCode, stdOut)
    if exitCode == 0 then
      for name, value, kind in stdOut:gmatch("([%w_]+)\t([^\t\n]*)\t(%a+)") do
        settings[name] = { value = value, isDefault = (kind == "default") }
      end
    end
    if after then after() end
  end)
end

-- Global, like the menu, so the timers can't be garbage-collected.
local function startAutoCheck()
  if _G.meetingrecUpdateTimer then return end
  local function quietCheck() checkForUpdates(false) end
  _G.meetingrecUpdateTimer = hs.timer.doEvery(CHECK_EVERY, guard("update check", quietCheck))
  -- A minute after loading as well: at login the network may not be up yet.
  _G.meetingrecFirstCheck = hs.timer.doAfter(60, guard("update check", quietCheck))
end

local function stopAutoCheck()
  if _G.meetingrecUpdateTimer then _G.meetingrecUpdateTimer:stop() end
  if _G.meetingrecFirstCheck then _G.meetingrecFirstCheck:stop() end
  _G.meetingrecUpdateTimer, _G.meetingrecFirstCheck = nil, nil
end

local function saveSetting(name, value, onSaved)
  run({ "config", "set", name, value }, function(exitCode, stdOut, stdErr)
    if exitCode ~= 0 then
      notify("MeetingRec — setting not changed", cliError(stdErr, stdOut))
      return
    end
    loadSettings(onSaved)
  end)
end

local function tilde(path)
  if path:sub(1, #HOME + 1) == HOME .. "/" then return "~" .. path:sub(#HOME + 1) end
  return path
end

local function exists(path)
  local f = io.open(path, "r")
  if f then f:close() end
  return f ~= nil
end

local function countNotes(dir)
  local out = hs.execute('find "' .. dir .. '/meeting-notes" -name "*.md" 2>/dev/null | wc -l')
  return tonumber(out and out:match("%d+")) or 0
end

-- The skill moves notes safely when asked; the menu only says they exist.
local function folderChanged(name, label, old)
  local new = settings[name].value
  local msg = label .. " → " .. tilde(new) .. (settings[name].isDefault and " (default)" or "")
  if name ~= "OUTPUT_ROOT" and old ~= new and countNotes(old) > 0 then
    msg = msg .. ". The notes already in " .. tilde(old) ..
      " stay there; ask Claude to move them if you like."
  end
  notify("MeetingRec", msg)
end

local function chooseFolder(name, label)
  local old = settings[name] and settings[name].value or HOME
  hs.focus()   -- otherwise the picker can open behind the frontmost app
  local picked = hs.dialog.chooseFileOrFolder("Choose the folder for " .. label:lower(),
                                              old, false, true, false)
  local path = picked and (picked["1"] or picked[1])
  if not path then return end
  path = path:gsub("^file://", ""):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
  path = path:gsub("(.)/$", "%1")
  saveSetting(name, path, function() folderChanged(name, label, old) end)
end

local function folderMenu(name, label)
  local s = settings[name]
  local shown = s and (tilde(s.value) .. (s.isDefault and " (default)" or "")) or "…"
  return { title = label .. ": " .. shown, menu = {
    { title = "Choose folder…", fn = function() chooseFolder(name, label) end },
    { title = "Use default", disabled = (s == nil or s.isDefault), fn = function()
        if not s then return end
        local old = s.value
        saveSetting(name, "", function() folderChanged(name, label, old) end)
      end },
    { title = "Show in Finder", disabled = (s == nil), fn = function()
        if s then hs.execute('open "' .. s.value .. '"') end
      end },
  } }
end

-- The skill creates personal.md on its first run; if someone opens it first,
-- make it now. A names.local.md from before is opened as-is: the skill carries
-- it over properly on its next run.
local function openPersonal(folder, skill)
  local ref = REPO .. "/" .. folder .. "/.claude/skills/" .. skill .. "/reference"
  local file = ref .. "/personal.md"
  if not exists(file) then
    if exists(ref .. "/names.local.md") then
      file = ref .. "/names.local.md"
    else
      hs.execute('cp -n "' .. ref .. '/personal.example.md" "' .. file .. '"')
    end
  end
  hs.execute('open -t "' .. file .. '"')
end

-- Two windows before anything goes: "Uninstall?" and, if you have notes in the
-- meetingrec folder, whether to keep them; a third asks about Claude Code if
-- the installer added it. Cancel and Keep are the buttons Return presses. The uninstall then runs detached, because it quits
-- Hammerspoon at the end; it sends its own notification when it's done.
local function uninstall()
  run({ "uninstall", "--dry-run" }, function(exitCode, stdOut, stdErr)
    if exitCode ~= 0 then
      notify("MeetingRec — can't uninstall", cliError(stdErr, stdOut))
      return
    end
    local count, hsAction, claudeOffer = stdOut:match("^plan (%d+) (%a+) (%a+)")
    count = tonumber(count) or 0
    local stays = stdOut:match("\nstays ([^\n]+)") or "Apple's command line tools"
    local button = hs.dialog.blockAlert("Uninstall meetingrec?",
      "This removes meetingrec's programs, settings and commands, and this menu-bar button" ..
        (hsAction == "remove" and ", and Hammerspoon, which the installer added for it" or "") .. ".\n\n" ..
        "These stay on your Mac: " .. stays .. "." ..
        (claudeOffer == "offer" and " You'll be asked about Claude Code." or ""),
      "Cancel", "Uninstall", "warning")
    if button ~= "Uninstall" then return end
    local notes = "--keep-notes"
    if count > 0 then
      button = hs.dialog.blockAlert("Keep your notes?",
        "You have " .. count .. (count == 1 and " file" or " files") .. " of your own in " ..
          tilde(REPO) .. "/scribe and teamnotes: notes, recordings and settings.\n\n" ..
          "Deleting them can't be undone.",
        "Keep them", "Delete them", "warning")
      if button == "Delete them" then notes = "--delete-notes" end
    end
    local claude = "--keep-claude"
    if claudeOffer == "offer" then
      button = hs.dialog.blockAlert("Remove Claude Code too?",
        "The meetingrec installer added Claude Code. Remove it only if you don't use it for " ..
          "anything else.\n\nIts settings and history in ~/.claude stay either way.",
        "Keep it", "Remove it", "warning")
      if button == "Remove it" then claude = "--remove-claude" end
    end
    log("uninstall: %s %s", notes, claude)
    notify("MeetingRec", "Uninstalling…")
    local logFile = (os.getenv("TMPDIR") or "/tmp/") .. "meetingrec-uninstall.log"
    hs.task.new("/bin/sh", nil, { "-c",
      'nohup "$0" uninstall --from-menu "$1" "$2" >"$3" 2>&1 </dev/null &',
      MEETINGREC, notes, claude, logFile }):start()
  end)
end

local function settingsMenu()
  local auto = settings.AUTO_UPDATE_CHECK
  local autoOn = not auto or auto.value ~= "off"
  return {
    { title = "Check for updates daily", checked = autoOn, fn = function()
        local want = autoOn and "off" or "on"
        saveSetting("AUTO_UPDATE_CHECK", want, function()
          if want == "on" then startAutoCheck() else stopAutoCheck() end
        end)
      end },
    { title = "-" },
    folderMenu("NOTES_VAULT", "Personal notes"),
    folderMenu("TEAM_VAULT", "Team notes"),
    folderMenu("OUTPUT_ROOT", "Recordings"),
    { title = "-" },
    { title = "Edit my rules and names…", fn = function() openPersonal("scribe", "meeting-notes") end },
    { title = "Edit team rules and names…", fn = function() openPersonal("teamnotes", "team-notes") end },
    { title = "Team profiles…", fn = function()
        hs.execute('open "' .. REPO .. '/teamnotes/.claude/skills/team-notes/profiles"')
      end },
    { title = "-" },
    { title = "Uninstall meetingrec…", disabled = isRecording, fn = uninstall },
  }
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
    { title = "Write up notes…", fn = function() writeUp("scribe", "scribe") end },
    { title = "Write up team notes…", fn = function() writeUp("teamnotes", "team notes") end },
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
    { title = "Settings", menu = settingsMenu() },
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

-- The daily update check runs unless AUTO_UPDATE_CHECK is "off". Settings load
-- in the background, so the timers start once they're known.
loadSettings(function()
  local auto = settings.AUTO_UPDATE_CHECK
  if not auto or auto.value ~= "off" then startAutoCheck() end
end)

refreshTitle()
resync()
log("init.lua loaded; menu bar item created")

local pending = hs.settings.get(AFTER_RELOAD)
if pending then
  hs.settings.clear(AFTER_RELOAD)
  notify("MeetingRec", pending)
end
