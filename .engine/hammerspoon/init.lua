-- MeetingRec menu bar.
--
-- Deliberately uses only hs.menubar, hs.task, hs.timer, hs.dialog, hs.notify,
-- hs.settings, hs.focus, hs.autoLaunch and hs.caffeinate.watcher. None of those need the
-- Accessibility permission —
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
-- True while the menu is closing a recording that died on its own, so a Start
-- in that second can't have its new recording stopped by mistake.
local finishing = false
-- True while a Stop from the menu is running, so going to sleep in that moment
-- doesn't start a second one beside it.
local stopping = false
-- Defined with the other CLI calls below; the tick needs it.
local checkAlive

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
  tickTimer = hs.timer.doEvery(30, guard("tick", function()
    refreshTitle()
    checkAlive()
  end))
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
    return false
  end
  -- Whether it started: false means onDone will never be called.
  return task:start() and true or false
end

-- Every tick while recording: if the recorder quit on its own (a crash, a Force
-- Quit), the menu would otherwise show ● and count minutes until someone clicks
-- Stop. The CLI decides; the menu only asks, so a native app can ask the same.
local checking = false
checkAlive = function()
  if not isRecording or checking or finishing then return end
  checking = true
  run({ "status" }, function(_, stdOut, _)
    checking = false
    if not isRecording or stdOut:match("^recording ") then return end
    isRecording = false
    startTime = nil
    stopTicking()
    -- Plain "idle" means it was stopped elsewhere (`meetingrec stop` in
    -- Terminal): nothing went wrong. "stale" means the recorder died.
    if not stdOut:match("stale") then return end
    -- Stop closes the session's bookkeeping (session.json, the levels check),
    -- and its warning says which track is affected.
    finishing = true
    run({ "stop" }, function(_, out, err)
      finishing = false
      local warning = out:match("WARNING: ([^\n]+)") or err:match("WARNING: ([^\n]+)")
      notify("MeetingRec — recording stopped unexpectedly",
             warning or "The recorder quit on its own. What it recorded until then is in the recordings folder.")
    end)
  end)
end

local function doStart(micOnly)
  if finishing then
    notify("MeetingRec", "Still closing the last recording. Try again in a moment.")
    return
  end
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

-- Defined below doStop, which needs it after a failed stop.
local resync

local function doStop()
  stopping = run({ "stop" }, function(exitCode, stdOut, stdErr)
    stopping = false
    isRecording = false
    startTime = nil
    stopTicking()
    if exitCode ~= 0 then
      notify("MeetingRec — stop failed", (stdErr ~= "" and stdErr or stdOut))
      -- A failed stop may have left ffmpeg running: show what the CLI says,
      -- not a guess of idle.
      resync()
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
resync = function()
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
-- Sleep
--
-- A Mac that sleeps freezes the recorder without stopping it. The recorder then
-- runs again every time the Mac wakes itself for background work, and from when
-- the lid opens until someone notices the ●. On 2026-11-15 a lid closed after a
-- half-hour call left a recording 3 h 47 min long: 57 of those wakes, about 35
-- minutes of a closed laptop.
--
-- So the recording is stopped when the Mac is about to sleep. Idle sleep doesn't
-- happen while audio is being captured, which leaves a closed lid, Apple menu →
-- Sleep and an empty battery: none of them a call still going on.
--
-- The stop runs inside the handler (hs.execute), not as a task. macOS holds
-- sleep off, for up to 30 seconds, only until the handler returns, and a stop
-- cut in two by the sleep would close the tracks minutes apart, when each
-- track's timing is read from the moment its file was closed. The CLI is asked
-- whether it's recording, so one started from Terminal is stopped too.
-- ---------------------------------------------------------------------------

-- Shown on wake: a notification sent on the way to sleep can be missed.
local sleepNote = nil

local function stopForSleep()
  if stopping or finishing then return end
  local status = hs.execute('"' .. MEETINGREC .. '" status')
  if not (status and status:match("^recording ")) then return end
  log("sleep: stopping the recording")
  local out, ok = hs.execute('"' .. MEETINGREC .. '" stop 2>&1')
  out = out or ""
  if not ok then
    log("sleep: stop failed: %s", out)
    sleepNote = { failed = true, title = "MeetingRec — stop failed",
                  text = out:match("meetingrec: ([^\n]+)") or out }
    return
  end
  -- With what stop printed: a recorder that had to be force-quit says so in a
  -- line the notification doesn't show.
  log("sleep: stopped: %s", (out:gsub("%s+$", "")))
  isRecording = false
  startTime = nil
  stopTicking()
  local after = out:match("stopped after ([^\n]+)")
  sleepNote = { title = "MeetingRec — stopped when your Mac went to sleep",
                text = out:match("WARNING: ([^\n]+)")
                  or ("The recording was stopped" .. (after and (" after " .. after) or "") .. ".") }
end

local function afterWake()
  if not sleepNote then return end
  local note = sleepNote
  sleepNote = nil
  notify(note.title, note.text)
  -- A failed stop may have left ffmpeg running: show what the CLI says.
  if note.failed then resync() end
end

-- Global, like the menu, so it can't be garbage-collected.
_G.meetingrecSleepWatcher = hs.caffeinate.watcher.new(guard("sleep watcher", function(event)
  if event == hs.caffeinate.watcher.systemWillSleep then
    stopForSleep()
  elseif event == hs.caffeinate.watcher.systemDidWake then
    afterWake()
  end
end))
_G.meetingrecSleepWatcher:start()

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
-- for Enter. WRITEUP_IN picks where: the Claude app by default, so no Terminal
-- is needed, or Terminal. If that one can't open, the other is tried. Both are
-- a plain `open` of a link, so no macOS permission is involved. The skills work
-- the same however Claude was started.
--
-- Codex and Antigravity (NOTES_AGENT is plain "codex" or "agy") have app links
-- too, and get the same choice. Antigravity's takes a project, not a folder, so
-- it works once the notes folder is a project in Antigravity; until then the
-- write-up opens in Terminal and says how to add it. Nothing opens it in Terminal by a link, so its Terminal is the one
-- every other agent gets: bin/scribe.command or bin/teamnotes.command. macOS
-- runs a .command file in a new Terminal window, again with no permission, and
-- the file runs the scribe or teamnotes command, which starts the agent with
-- the request sent. An agent with options, "claude --model x" included, always
-- goes that way: a link can't carry them.
-- ---------------------------------------------------------------------------

local function urlEncode(s)
  return (s:gsub("[^%w%-%._~/]", function(c) return string.format("%%%02X", string.byte(c)) end))
end

-- An agent's app or Terminal link: the notes folder and the request ride along
-- as two parameters, and the request waits in the box for Enter.
local CLAUDE_APP = { name = "Claude app", link = "claude://code/new", folderParam = "folder", textParam = "q",
  insteadOfTerminal = " Run claude once in Terminal, then try again." }
local CLAUDE_TERMINAL = { name = "Claude Code in Terminal", link = "claude-cli://open", folderParam = "cwd", textParam = "q" }
-- Codex's app is the ChatGPT app, which kept the codex:// links.
local CODEX_APP = { name = "ChatGPT app", link = "codex://threads/new", folderParam = "path", textParam = "prompt",
  insteadOfTerminal = "" }
-- Not in Antigravity's docs: read from its app (2.32.1). `project` is the ID of
-- an Antigravity project that holds the folder; `meetingrec antigravity-project`
-- finds it.
local ANTIGRAVITY_APP = { name = "Antigravity app", link = "antigravity://open", projectParam = "project",
  textParam = "prompt", insteadOfTerminal = "" }
-- Any agent, in Terminal: bin/scribe.command or bin/teamnotes.command.
local COMMAND_FILE = { name = "Terminal" }

-- Which agents have an app link, and what stands in for Terminal. Only the
-- plain command counts: a link can't carry options.
local function writeUpTargets(agent)
  if agent == "claude" then return CLAUDE_APP, CLAUDE_TERMINAL end
  if agent == "codex" then return CODEX_APP, COMMAND_FILE end
  if agent == "agy" then return ANTIGRAVITY_APP, COMMAND_FILE end
  return nil, COMMAND_FILE
end

-- project: for a link that takes one; without it that link can't be opened.
local function openTarget(target, folder, request, project)
  local what = REPO .. "/.engine/bin/" .. folder .. ".command"
  if target.projectParam then
    if not project then return false end
    what = target.link .. "?" .. target.projectParam .. "=" .. urlEncode(project) ..
      "&" .. target.textParam .. "=" .. urlEncode(request)
  elseif target.link then
    what = target.link .. "?" .. target.folderParam .. "=" .. urlEncode(REPO .. "/" .. folder) ..
      "&" .. target.textParam .. "=" .. urlEncode(request)
  end
  local _, opened = hs.execute('open "' .. what .. '"')
  return opened
end

-- These belong to Settings, further down, where loadSettings is defined.
local settings = {}   -- NAME -> { value = "…", isDefault = true|false }
local agents = {}     -- from `meetingrec agents`: { cmd, name, path, app }, in its order
local loadSettings

local function parseAgents(list)
  local found = {}
  for cmd, name, path, app in list:gmatch("([^\t\n]*)\t([^\t\n]*)\t([^\t\n]*)\t([^\t\n]*)") do
    found[#found + 1] = { cmd = cmd, name = name, path = path, app = app }
  end
  return found
end

-- Whether an agent meetingrec knows has no command on this Mac, only its app:
-- then Terminal can't start it, and the app is the only way in.
local function appOnly(cmd)
  for _, a in ipairs(agents) do
    if a.cmd == cmd then return a.path == "" and a.app ~= "" end
  end
  return false
end

local function writeUp(folder, request)
  local dir = REPO .. "/" .. folder
  -- Asked rather than assumed, so a change made from Terminal counts at once.
  run({ "config", "list" }, function(exitCode, stdOut)
    local agent = exitCode == 0 and stdOut:match("NOTES_AGENT\t([^\t\n]*)") or "claude"
    -- Settings shows the agent from its cache. Bring that up to date when the
    -- agent was changed from Terminal since the menu loaded.
    if not settings.NOTES_AGENT or settings.NOTES_AGENT.value ~= agent then loadSettings() end
    local app, terminal = writeUpTargets(agent)
    local terminalFirst = exitCode == 0 and stdOut:match("WRITEUP_IN\tterminal\t") ~= nil
    -- noCommand: the agent's app is here but its command isn't, so the Terminal
    -- window would only say it's missing. The app goes first, whatever the
    -- setting. (Claude's Terminal is a link that doesn't open without the
    -- claude command, so it falls back to the app by itself.)
    local function open(project, noCommand)
      local order = { app, terminal }
      if not app or (terminalFirst and not noCommand) then order = { terminal, app } end
      for _, target in ipairs(order) do
        if openTarget(target, folder, request, project) then
          log("write-up: %s in %s", target.link and target.name or (agent .. " in Terminal"), dir)
          if terminalFirst and noCommand and target == app then
            notify("MeetingRec", "Opened in the " .. app.name .. ": Terminal needs the " .. agent ..
              " command, which isn't on this Mac.")
          -- Having no app is normal; asking for Terminal and not getting it isn't.
          elseif terminalFirst and target == app then
            notify("MeetingRec", "Couldn't open Terminal, so this opened in the " .. app.name .. "." ..
              app.insteadOfTerminal)
          elseif (not terminalFirst or noCommand) and app and app.projectParam and not project then
            local home = os.getenv("HOME")
            local shown = dir:sub(1, #home + 1) == home .. "/" and "~" .. dir:sub(#home + 1) or dir
            notify("MeetingRec", "Opened in Terminal: Antigravity has no project for " .. shown ..
              ". To use the Antigravity app, add that folder as a project in Antigravity once.")
          end
          return true
        end
      end
      return false
    end
    local function finish(opened)
      if opened then return end
      if agent == "claude" then
        log("write-up: nothing handles claude:// or claude-cli:// links")
        notify("MeetingRec", "Couldn't open Claude. Install the Claude app, or type " ..
          folder .. " in Terminal.")
      else
        log("write-up: couldn't open %s.command", folder)
        notify("MeetingRec", "Couldn't open a Terminal window for " .. agent .. ". Type " ..
          folder .. " in Terminal.")
      end
    end
    local function withProject(noCommand)
      if app and app.projectParam then
        run({ "antigravity-project", dir }, function(found, out)
          local project = found == 0 and out:match("^(%S+)") or nil
          if not project then log("write-up: no Antigravity project holds %s", dir) end
          finish(open(project, noCommand))
        end)
      else
        finish(open(nil, noCommand))
      end
    end
    -- Asked now, not taken from the cache: the command may have been installed
    -- or removed since the menu loaded.
    if app and terminal == COMMAND_FILE then
      run({ "agents" }, function(found, list)
        if found == 0 then agents = parseAgents(list) end
        local noCommand = appOnly(agent)
        if noCommand then log("write-up: %s has its app but no command", agent) end
        withProject(noCommand)
      end)
    else
      withProject(false)
    end
  end)
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

-- The agents found on this Mac are asked for too, each time: one installed
-- since the menu loaded should show up in Settings without a reload.
loadSettings = function(after)
  run({ "config", "list" }, function(exitCode, stdOut)
    if exitCode == 0 then
      for name, value, kind in stdOut:gmatch("([%w_]+)\t([^\t\n]*)\t(%a+)") do
        settings[name] = { value = value, isDefault = (kind == "default") }
      end
    end
    run({ "agents" }, function(found, list)
      if found == 0 then agents = parseAgents(list) end
      if after then after() end
    end)
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
      " stay there; ask your agent to move them if you like."
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
  local function save(p) saveSetting(name, p, function() folderChanged(name, label, old) end) end
  if name == "OUTPUT_ROOT" then save(path) return end
  -- A folder inside a vault (often its own meeting-notes) would put notes a
  -- level too deep, where the vault's notes table can't see them.
  run({ "vault-root", path }, function(exitCode, stdOut)
    local better = exitCode == 0 and stdOut:match("^([^\n]+)")
    if better then
      local button = hs.dialog.blockAlert("Use " .. tilde(better) .. " instead?",
        "Notes go in a meeting-notes folder inside the folder you pick, so " .. tilde(path) ..
          " would put them in " .. tilde(path) .. "/meeting-notes.",
        "Use " .. tilde(better), "Keep my choice")
      if button ~= "Keep my choice" then path = better end
    end
    save(path)
  end)
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

-- The installer and the skill create personal.md; if someone opens it before
-- either has, make it now.
local function openPersonal(folder)
  local dir = REPO .. "/" .. folder .. "/settings"
  local file = dir .. "/personal.md"
  if not exists(file) then
    hs.execute('cp -n "' .. dir .. '/personal.example.md" "' .. file .. '"')
  end
  -- The user's default app for .md files; the plain-text editor if there is none.
  hs.execute('open "' .. file .. '" || open -t "' .. file .. '"')
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
    -- Notes folders picked outside meetingrec's own are never deleted; say so,
    -- or "delete your notes" reads as covering them too.
    local outside = {}
    for dir in stdOut:gmatch("\noutside ([^\n]+)") do outside[#outside + 1] = tilde(dir) end
    local outsideText = ""
    if #outside == 1 then
      outsideText = "\n\nYour notes in " .. outside[1] .. " aren't touched. Delete them yourself if you don't want them."
    elseif #outside > 1 then
      outsideText = "\n\nYour notes and recordings in these folders aren't touched. Delete them yourself if you don't want them:\n" ..
        table.concat(outside, "\n")
    end
    local button = hs.dialog.blockAlert("Uninstall meetingrec?",
      "This removes meetingrec's programs, settings and commands, and this menu-bar button" ..
        (hsAction == "remove" and ", and Hammerspoon, which the installer added for it" or "") .. ".\n\n" ..
        "These stay on your Mac: " .. stays .. "." ..
        (claudeOffer == "offer" and " You'll be asked about Claude Code." or "") .. outsideText,
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
  local writeUpIn = settings.WRITEUP_IN
  local inTerminal = writeUpIn ~= nil and writeUpIn.value == "terminal"
  -- Which agent writes the notes: the ones meetingrec knows, greyed out when
  -- they aren't on this Mac, and any other command typed in.
  local agent = settings.NOTES_AGENT and settings.NOTES_AGENT.value or "claude"
  local agentItems, known = {}, false
  for _, a in ipairs(agents) do
    local installed = a.path ~= "" or a.app ~= ""
    known = known or a.cmd == agent
    agentItems[#agentItems + 1] = {
      title = a.name .. (installed and "" or " (not installed)"),
      checked = a.cmd == agent, disabled = not installed and a.cmd ~= agent,
      fn = function() saveSetting("NOTES_AGENT", a.cmd) end }
  end
  if not known then
    agentItems[#agentItems + 1] = { title = agent, checked = true }
  end
  agentItems[#agentItems + 1] = { title = "-" }
  agentItems[#agentItems + 1] = { title = "Other command…", fn = function()
      local button, typed = hs.dialog.textPrompt("Agent",
        "The command that starts the coding agent, with any options, as you'd type it in " ..
          "Terminal. The request is added after it. No quotes.",
        known and "" or agent, "Save", "Cancel")
      if button == "Save" and typed and typed:match("%S") then saveSetting("NOTES_AGENT", typed) end
    end }
  -- The app-or-Terminal choice is for the agents that have an app link. Any
  -- other always opens in Terminal.
  local app, terminal = writeUpTargets(agent)
  local writeUpItem = { title = "Write up notes opens in Terminal", disabled = true }
  if app then
    -- With only the app on this Mac, Terminal can't start the agent: shown
    -- greyed out, and the app checked, since that's where it opens.
    local noCommand = terminal == COMMAND_FILE and appOnly(agent)
    local terminalTitle = noCommand and ("Terminal (needs the " .. agent .. " command)") or "Terminal"
    writeUpItem = { title = "Write up notes opens in", menu = {
        { title = app.name, checked = not inTerminal or noCommand, fn = function() saveSetting("WRITEUP_IN", "app") end },
        { title = terminalTitle, checked = inTerminal and not noCommand, disabled = noCommand,
          fn = function() saveSetting("WRITEUP_IN", "terminal") end },
      } }
  end
  return {
    { title = "Check for updates daily", checked = autoOn, fn = function()
        local want = autoOn and "off" or "on"
        saveSetting("AUTO_UPDATE_CHECK", want, function()
          if want == "on" then startAutoCheck() else stopAutoCheck() end
        end)
      end },
    { title = "Agent", menu = agentItems },
    writeUpItem,
    { title = "-" },
    folderMenu("NOTES_VAULT", "Personal notes"),
    folderMenu("TEAM_VAULT", "Team notes"),
    folderMenu("OUTPUT_ROOT", "Recordings"),
    { title = "-" },
    { title = "Edit my rules and names…", fn = function() openPersonal("scribe") end },
    { title = "Edit team rules and names…", fn = function() openPersonal("teamnotes") end },
    { title = "Team profiles…", fn = function()
        hs.execute('open "' .. REPO .. '/teamnotes/settings/profiles"')
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
