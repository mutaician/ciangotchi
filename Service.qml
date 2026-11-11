import QtQuick
import Quickshell
import Quickshell.Io

// Headless pet brain. Loaded once at shell startup, independent of the bar
// widget, so the pet keeps living (and roaming) with the panel closed.
//
// Needs follow the classic loop: they rise with active shell time so there is
// always something to do, whatever the hardware. System state only flavors the
// pace — pending updates make it hungrier faster, orphaned packages make it
// get dirty faster. Nothing here depends on absolute machine performance.
//
// Commands executed (all fixed argv, read-only, no interpolation):
//   checkupdates              pending official updates
//   pacman -Qdtq              orphaned packages
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME")
    || ((Quickshell.env("HOME") || "") + "/.local/state")
  readonly property string stateDir: stateHome + "/omarchy"
  readonly property string settingsPath: stateDir + "/ciangotchi-settings.json"
  readonly property string petPath: stateDir + "/ciangotchi-state.json"

  readonly property var defaultSettings: ({
    roamEnabled: false,
    // Art pixels are drawn this many screen pixels big (sprites are 32x32).
    roamScale: 2,
    // Which output the pet roams on, named as Hyprland names it (whatever
    // `hyprctl monitors` prints, e.g. "DP-1"). Empty keeps the default: the
    // largest screen.
    roamScreen: "",
    soundVolume: 0.5,
    // --- ciangotchi: idle nudges (see Nudge.qml) ---
    nudgesEnabled: true,
    idleMinutes: 10,
    // Chance that a nudge opens a link as well.
    mischiefChance: 0.25,
    // Epoch ms until which nudges are paused; 0 = not on a break.
    breakUntilMs: 0,
    breakMinutes: 30,
    // Random links the pet may open, plus your browser's bookmarks.
    includeBookmarks: true,
    bookmarksPath: "",
    // Random FMHY links (a daily-refreshed list, see tools/refresh-fmhy.sh).
    includeFmhy: true,
    // Clicking the roaming pet fetches a random link.
    clickOpensLink: true,
    links: []
  })
  // Effects volume, 0 (mute) to 1.
  readonly property real soundVolume: {
    var v = Number(settings.soundVolume)
    return isFinite(v) ? Math.max(0, Math.min(1, v)) : 0.5
  }
  property var settings: defaultSettings

  // --- persistent pet facts --------------------------------------------------

  property double hatchedAtMs: 0
  property double lastPetMs: 0

  // Growth, Gen1-chart style: the stage advances with active shell minutes,
  // and the branch taken depends on average happiness over the stage.
  property string stage: "pod"     // pod | base | ssj | ssj2 | god | blue | ego
  property string form: "pod"      // sprite prefix in assets/sprites/
  property real ageMinutes: 0
  // Minutes of real work (see Nudge.focused). This is what powers it up.
  property real focusMinutes: 0
  property real careSum: 0
  property int careCount: 0
  property int generation: 1

  // Need levels, 0 = fine, 100 = critical. All persisted.
  property real hungerLevel: 0
  property real dirtLevel: 0
  property real tirednessLevel: 0
  property real boredomLevel: 0
  property real lonelinessLevel: 0
  property bool sleeping: false

  // The power ladder: a form is reached after this many focused minutes.
  // pod = the Saiyan space pod it hatches from. majin is not on the ladder:
  // it is a roaming event (see eventForm).
  readonly property var ladder: [
    { stage: "pod",   at: 0,    label: "Saiyan pod" },
    { stage: "base",  at: 5,    label: "Saiyan" },
    { stage: "ssj",   at: 120,  label: "Super Saiyan" },
    { stage: "ssj2",  at: 480,  label: "Super Saiyan 2" },
    { stage: "god",   at: 1200, label: "Super Saiyan God" },
    { stage: "blue",  at: 2400, label: "Super Saiyan Blue" },
    { stage: "ego",   at: 4800, label: "Ultra Ego" }
  ]
  readonly property var knownForms: ["pod", "base", "ssj", "ssj2", "god", "blue", "ego"]

  // Hair/aura colour per form; "dim" = a dimmed theme tint.
  readonly property var formAccents: ({
    pod: "#ff5d7a", base: "#4b5366", ssj: "#ffd23c", ssj2: "#ffd23c",
    god: "#ff4d5e", blue: "#3fb8ff", ego: "#c04dff", majin: "#ffd23c"
  })
  // A temporary form shown over the real one (Majin, while roaming).
  property string eventForm: ""
  readonly property string displayForm: eventForm !== "" ? eventForm : form
  readonly property string displayAccent: formAccents[displayForm] || ""

  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || ""
  readonly property string notificationExecutable: omarchyPath !== ""
    ? omarchyPath + "/bin/omarchy-notification-send"
    : "omarchy-notification-send"

  // --- probe results ---------------------------------------------------------

  property int pendingUpdates: 0
  property int orphanCount: 0
  property double nowMs: Date.now()

  property bool initialized: false
  // State files are read through `head -c` so a huge or symlinked file can
  // never be pulled whole into the shell; the plugin writes a few hundred
  // bytes, anything hitting the cap is treated as corrupt.
  readonly property int maxStateBytes: 65536
  property bool settingsFileLoaded: false
  property bool petFileLoaded: false
  property string loadedSettingsText: ""
  property string loadedPetText: ""
  property string petReadProblem: ""

  // --- derived needs ---------------------------------------------------------

  readonly property real hunger: Math.max(0, Math.min(100, hungerLevel))
  // Hygiene was removed from ciangotchi: the pet never gets dirty.
  readonly property real dirtiness: 0
  readonly property real tiredness: Math.max(0, Math.min(100, tirednessLevel))
  readonly property real boredom: Math.max(0, Math.min(100, boredomLevel))
  // Affection is a cuddle-session need: it fills over active time and each
  // petting only takes a bite out of it — a truly lonely pet wants a real
  // fuss, not a single tap.
  readonly property real loneliness: Math.max(0, Math.min(100, lonelinessLevel))

  readonly property bool roaming: canRoam && settings.roamEnabled === true

  readonly property real worstNeed: Math.max(hunger, dirtiness, tiredness,
    boredom, loneliness)
  readonly property real happiness: Math.round(100 - worstNeed)

  readonly property real careAverage: careCount > 0 ? careSum / careCount : 100
  readonly property bool canRoam: stage !== "pod"
  readonly property string stageLabel: {
    for (var i = 0; i < ladder.length; i++) if (ladder[i].stage === stage) return ladder[i].label
    return stage
  }
  readonly property real focusHours: focusMinutes / 60

  // Where the pet left its panel, in screen coordinates (center x, feet y),
  // so the roaming window can pick up the fall right under the card. Negative
  // x means "no handoff": spawn at the usual floor spot.
  property real handoffX: -1
  property real handoffY: -1
  property string handoffScreen: ""
  // The screen Go play / Come home was last clicked on. Runtime-only: after
  // a shell restart the playground falls back to the usual screen choice.
  property string requestedScreenName: ""

  // Set by the panel to call the pet home through the tractor beam; the roam
  // window beams it up to the handoff spot, then clears this and fires
  // arrivedHome so the panel can play the entrance.
  property bool returnRequested: false
  signal arrivedHome()

  // Short-lived animation for a care action ("eat", "wash"), shown by the
  // panel and the roaming pet, then cleared.
  property string transientAnim: ""
  Timer {
    id: transientTimer
    interval: 2500
    onTriggered: root.endCare()
  }

  function endCare() {
    transientAnim = ""
    // Woken up for a meal or a bath? It stays up a little while, then goes
    // back to bed if it is still sleepy. The flag survives until the pet
    // actually dozes back off, so chained cares (feed then wash) re-arm it.
    if (wokenForCare) resleepTimer.restart()
  }
  Timer {
    id: resleepTimer
    interval: 30000
    onTriggered: {
      // Mid-meal or mid-scrub: stay up, endCare re-arms the timer.
      if (root.sleeping || root.eating || root.transientAnim !== "") return
      root.wokenForCare = false
      if (root.tirednessLevel < 60 || root.roaming) return
      root.sleeping = true
      root.playSound("sleep")
      root.flushPet()
    }
  }

  // A meal is eaten bite by bite: hunger drains over ~6 s from full while
  // the eat frames play, then a last chew before the animation ends.
  readonly property bool eating: eatTimer.running
  Timer {
    id: eatTimer
    interval: 100
    repeat: true
    onTriggered: {
      root.hungerLevel = Math.max(0, root.hungerLevel - 100 / 60)
      if (root.hungerLevel > 0) return
      stop()
      transientTimer.interval = 600
      transientTimer.restart()
      root.flushPet()
    }
  }

  // The shared emote bubbles, one glyph per complaining need. When several
  // needs complain at once the bubble cycles through them every few seconds.
  // Views hide the bubble when the file doesn't exist yet.
  readonly property var activeEmotes: {
    if (!initialized || sleeping || stage === "pod") return []
    var list = []
    if (hunger >= 60) list.push("emote_hungry")
    if (dirtiness >= 60) list.push("emote_dirty")
    if (tiredness >= 60) list.push("emote_sleepy")
    if (boredom >= 60) list.push("emote_bored")
    if (loneliness >= 60) list.push("emote_sad")
    return list
  }
  property int emoteCycle: 0
  readonly property string emoteName: activeEmotes.length === 0
    ? "" : activeEmotes[emoteCycle % activeEmotes.length]

  Timer {
    interval: 3000
    running: root.initialized && root.activeEmotes.length > 1
    repeat: true
    onTriggered: root.emoteCycle += 1
  }

  // The idle-state animation views should show (falls back to plain idle in
  // PetSprite when the dedicated sprite doesn't exist yet).
  readonly property string stateAnim: {
    if (!initialized || stage === "pod") return "idle"
    if (sleeping) return "sleep"
    if (nudge.restless) return "rage"
    switch (mood) {
    case "hungry": return "hungry"
    case "dirty": return "dirty"
    case "sleepy": return "sleepy"
    case "bored": return "bored"
    case "lonely": return "sad"
    default: return "idle"
    }
  }

  // Priority order: sleep is a state, then the loudest complaint wins.
  readonly property string mood: {
    if (!initialized) return "sleeping"
    if (stage === "pod") return "pod"
    if (sleeping) return "sleeping"
    if (hunger >= 60) return "hungry"
    if (dirtiness >= 60) return "dirty"
    if (tiredness >= 60) return "sleepy"
    if (boredom >= 60) return "bored"
    if (loneliness >= 60) return "lonely"
    if (worstNeed >= 35) return "meh"
    return "happy"
  }

  readonly property string moodLabel: {
    switch (mood) {
    case "pod": return "A pod. Something is stirring inside…"
    case "sleeping": return "Zzz…"
    case "hungry": return pendingUpdates > 0
      ? "Hungry. Those " + pendingUpdates + " pending updates look edible"
      : "I need food. A Saiyan needs to eat."
    case "dirty": return orphanCount > 0
      ? "Feeling gross — the " + orphanCount + " orphaned packages don't help"
      : "Feeling gross — bath time?"
    case "sleepy": return "Tired. Even a prince has limits."
    case "bored": return "I need a fight. Let me out to train."
    case "lonely": return "Where is my respect?"
    case "meh": return "Hmph. Acceptable."
    case "happy": return "At full power."
    default: return "Ciangotchi"
    }
  }

  // --- the minute tick -------------------------------------------------------

  // Per-stage personalities: babies nap constantly, children burst with
  // energy and want out, teens raid the fridge and stay in. See ROADMAP §3.
  readonly property var stageRates: ({
    adult: { hunger: 1, dirt: 1, tired: 1, fun: 1 }
  })

  // Per-active-minute rates. System state flavors the pace: pending updates
  // and orphans speed up hunger/dirt, roaming is fun but tiring.
  function applyMinute() {
    if (stage === "pod") return // a pod has no needs yet
    var rates = stageRates[stage] || stageRates.adult

    // Out and about, it hums to itself once or twice an hour…
    if (roaming && !sleeping && Math.random() < 1.5 / 60) playSound("hum")
    // …and now and then Babidi's influence takes hold: Majin Vegeta, for a minute.
    if (roaming && !sleeping && eventForm === "" && Math.random() < 1 / 90) {
      eventForm = "majin"
      majinTimer.restart()
      playSound("evolve")
    }

    hungerLevel = Math.min(100,
      hungerLevel + (pendingUpdates > 0 ? 0.5 : 0.33) * rates.hunger)
    dirtLevel = Math.min(100,
      dirtLevel + (orphanCount > 0 ? 0.33 : 0.21) * rates.dirt)

    if (sleeping) {
      tirednessLevel = Math.max(0, tirednessLevel - 6)   // a short nap: a Saiyan prince does not sleep in
      if (tirednessLevel <= 5) {
        sleeping = false
        // A little hum tells the user it woke up on its own.
        playSound("hum")
      }
    } else {
      tirednessLevel = Math.min(100,
        tirednessLevel + (roaming ? 0.3 : 0.15) * rates.tired)
      if (tirednessLevel >= 90) {
        sleeping = true
        playSound("sleep")
      } else if (tirednessLevel >= 60 && !roaming && !resleepTimer.running) {
        // Sleepy at home with nothing better to do: doze off shortly.
        // The timer re-checks (eating, care animation) before committing.
        resleepTimer.restart()
      }
    }

    boredomLevel = roaming
      ? Math.max(0, boredomLevel - 2.0)
      : Math.min(100, boredomLevel + 0.45 * rates.fun)

    // Full in ~14 active hours; each petting takes 10 off.
    lonelinessLevel = Math.min(100, lonelinessLevel + 0.12)
  }

  // --- growth ----------------------------------------------------------------

  readonly property var evolveLines: ({
    base:  "Hmph. The pod opened. I am Vegeta.",
    ssj:   "Super Saiyan. Behold the prince's power!",
    ssj2:  "Super Saiyan 2. My power keeps rising.",
    god:   "Super Saiyan God. Divine ki, and it is mine.",
    blue:  "Super Saiyan Blue. Look at what hard work can do.",
    ego:   "Ultra Ego. The stronger the enemy, the stronger I get."
  })

  // One step up the ladder per call, when focused minutes allow it.
  function maybeEvolve() {
    var idx = -1
    for (var i = 0; i < ladder.length; i++) if (ladder[i].stage === stage) idx = i
    if (idx < 0 || idx >= ladder.length - 1) return
    var next = ladder[idx + 1]
    if (focusMinutes >= next.at) evolve(next.stage, next.stage, evolveLines[next.stage])
  }

  function evolve(nextStage, nextForm, message) {
    stage = nextStage
    form = nextForm
    careSum = 0
    careCount = 0
    flushPet()
    playSound(nextStage === "base" ? "hatch" : "evolve")
    notify("Ciangotchi", message)
  }

  // --- sounds ----------------------------------------------------------------

  // One short clip per event, named after the event so better sounds can be
  // dropped in without touching code. The current set is placeholders reused
  // from the tomato-timer plugin's library — see CREDITS.md.
  // One file per event, or a list to pick from at random (see CREDITS.md).
  readonly property var eventSounds: ({
    hatch: "hatch.wav",
    evolve: "evolve.wav",
    eat: "eat.wav",
    wash: "wash.wav",
    pet: ["pet.wav", "pet2.wav"],
    hum: "humming.wav",
    grab: "grab.wav",
    sleep: "sleep.mp3",
    stun: "stun.mp3",
    land: "fall.wav",
    beamCharge: "subbass.wav",
    beam: "tractorbeam.wav",
    ball: "balloon.wav",
    farewell_ace: "farewell_ace.wav",
    farewell_ok: "farewell_ok.mp3",
    farewell_gremlin: "farewell_gremlin.mp3"
  })

  // pw-play wants a filesystem path, not a file:// URL.
  function soundPath(relativePath) {
    var url = Qt.resolvedUrl(relativePath).toString()
    if (url.indexOf("file://") === 0) url = url.substring(7)
    return decodeURIComponent(url)
  }

  function playSound(event) {
    if (soundVolume <= 0) return
    var file = eventSounds[event]
    if (Array.isArray(file)) file = file[Math.floor(Math.random() * file.length)]
    if (!file) return
    Quickshell.execDetached(["pw-play", "--volume", soundVolume.toFixed(2),
      soundPath("sounds/" + file)])
  }

  function notify(title, body) {
    Quickshell.execDetached([
      notificationExecutable,
      "--app-name", "ciangotchi",
      "-u", "normal",
      title,
      body
    ])
  }

  // --- actions ---------------------------------------------------------------

  // Care wakes a sleeping pet first; once the fuss is over it dozes back
  // off if it is still sleepy (see transientTimer).
  property bool wokenForCare: false

  function wakeForCare() {
    // A pending doze interrupted by more care still counts as one to resume.
    if (resleepTimer.running) wokenForCare = true
    resleepTimer.stop()
    if (!sleeping) return
    sleeping = false
    wokenForCare = true
  }

  function feedNow() {
    if (eating) return
    wakeForCare()
    transientAnim = "eat"
    transientTimer.stop()
    playSound("eat")
    if (hungerLevel > 0) eatTimer.restart()
    else {
      // Nothing to eat: a polite nibble, then back to whatever it was doing.
      transientTimer.interval = 1200
      transientTimer.restart()
    }
  }

  // Washing is a scrubbing gesture: the panel feeds it mouse travel and the
  // dirt comes off progressively. Persisted by the caller on gesture end.
  function scrub(amount) {
    if (dirtLevel <= 0) return
    wakeForCare()
    dirtLevel = Math.max(0, dirtLevel - amount)
    transientAnim = "wash"
    transientTimer.interval = 2500
    transientTimer.restart()
    if (dirtLevel === 0) flushPet()
  }

  // The Tamagotchi farewell: the adult sets off into the world, a new egg appears, and
  // the generation counter carries the legacy.
  // Letting go is a little ceremony: the adult leaves its room (if home),
  // walks to the nearest screen corner, says goodbye in its own voice and
  // walks off the screen. Only then does the new egg appear.
  property bool farewellPending: false

  function beginFarewell() {
    if (stage !== "ego" || farewellPending) return
    wakeUp()
    farewellPending = true
  }

  function farewellSoundEvent() {
    return "farewell_ace"
  }

  function sendOff() {
    if (stage !== "ego") return
    farewellPending = false
    generation += 1
    stage = "pod"
    form = "pod"
    ageMinutes = 0
    focusMinutes = 0
    careSum = 0
    careCount = 0
    hungerLevel = 0
    dirtLevel = 0
    tirednessLevel = 0
    boredomLevel = 0
    lonelinessLevel = 0
    sleeping = false
    hatchedAtMs = Date.now()
    lastPetMs = hatchedAtMs
    // The adult may leave from outdoors; the egg must not inherit a stale
    // "out playing" state (disabled Come home button, surprise exit at
    // the child stage).
    updateSettings({ roamEnabled: false })
    flushPet()
    notify("Ciangotchi", "The prince has moved on. A new Saiyan pod landed. (Gen " + generation + ")")
  }

  // A deliberate wake-up — petting, grabbing, or sending it out — unlike
  // wakeForCare it does not tuck the pet back in afterwards.
  function wakeUp() {
    if (!sleeping) return
    resleepTimer.stop()
    sleeping = false
    wokenForCare = false
    flushPet()
  }

  function petThePet() {
    wakeUp()
    lastPetMs = Date.now()
    nowMs = lastPetMs
    lonelinessLevel = Math.max(0, lonelinessLevel - 10)
    // Cuddles only entertain a pet too little to go out; once it can
    // roam, boredom is cured outside.
    if (!canRoam) boredomLevel = Math.max(0, boredomLevel - 10)
    playSound("pet")
    flushPet()
  }

  function setRoamEnabled(value) {
    updateSettings({ roamEnabled: value === true })
    // Brought home already sleepy? It settles in for a moment, then dozes
    // off — no need to hit rock bottom first.
    if (value !== true && !sleeping && tirednessLevel >= 60)
      resleepTimer.restart()
  }

  // A big fall hurts its feelings too: the inverse of a petting.
  // A big fall: the thud first, the dizzy jingle right after it.
  function stunShock() {
    lonelinessLevel = Math.min(100, lonelinessLevel + 10)
    playSound("land")
    stunSoundTimer.restart()
    flushPet()
  }
  Timer {
    id: stunSoundTimer
    interval: 450
    onTriggered: root.playSound("stun")
  }

  // The tractor beam: a low thrum powering up, then the beam itself. On the
  // way home it is mirrored: the beam plays out (~2.7 s), then the thrum.
  function playBeamSound(homeward) {
    beamSoundTimer.second = homeward ? "beamCharge" : "beam"
    beamSoundTimer.interval = homeward ? 2700 : 650
    playSound(homeward ? "beam" : "beamCharge")
    beamSoundTimer.restart()
  }
  Timer {
    id: beamSoundTimer
    property string second: "beam"
    onTriggered: root.playSound(second)
  }

  function updateSettings(patch) {
    var merged = {}
    for (var key in defaultSettings) merged[key] = defaultSettings[key]
    // Only known keys survive a write: retired settings (soundEnabled…) drop
    // out of the file on their own.
    for (var current in settings) if (current in merged) merged[current] = settings[current]
    for (var change in patch) if (change in merged) merged[change] = patch[change]
    settings = merged
    settingsFile.setText(JSON.stringify(settings, null, 2) + "\n")
  }

  function flushPet() {
    petFile.setText(JSON.stringify({
      hatchedAtMs: hatchedAtMs,
      lastPetMs: lastPetMs,
      stage: stage,
      form: form,
      ageMinutes: ageMinutes,
      focusMinutes: focusMinutes,
      careSum: careSum,
      careCount: careCount,
      generation: generation,
      hungerLevel: hungerLevel,
      dirtLevel: dirtLevel,
      tirednessLevel: tirednessLevel,
      boredomLevel: boredomLevel,
      lonelinessLevel: lonelinessLevel,
      sleeping: sleeping
    }, null, 2) + "\n")
  }

  // --- init ------------------------------------------------------------------

  function initializeIfReady() {
    if (initialized || !settingsFileLoaded || !petFileLoaded) return

    try {
      var parsedSettings = loadedSettingsText !== "" ? JSON.parse(loadedSettingsText) : {}
      updateSettingsInMemory(parsedSettings)
    } catch (error) {
      console.warn("ciangotchi: settings file unreadable (" + error + "), using defaults")
      settings = defaultSettings
    }

    var hatch = false
    var saveProblem = petReadProblem
    // Persisted numbers must be finite and non-negative; anything else
    // (NaN, Infinity, negatives, strings) reads as 0.
    function num(v) { var n = Number(v); return isFinite(n) && n > 0 ? n : 0 }
    try {
      var pet = loadedPetText !== "" ? JSON.parse(loadedPetText) : {}
      hatchedAtMs = num(pet.hatchedAtMs)
      lastPetMs = num(pet.lastPetMs)
      stage = typeof pet.stage === "string" ? pet.stage : "pod"
      form = typeof pet.form === "string" ? pet.form : "pod"
      ageMinutes = num(pet.ageMinutes)
      focusMinutes = num(pet.focusMinutes)
      careSum = num(pet.careSum)
      careCount = Math.round(num(pet.careCount))
      generation = Math.max(1, Math.round(num(pet.generation)))
      hungerLevel = num(pet.hungerLevel)
      dirtLevel = num(pet.dirtLevel)
      tirednessLevel = num(pet.tirednessLevel)
      boredomLevel = num(pet.boredomLevel)
      if (pet.lonelinessLevel !== undefined) {
        lonelinessLevel = num(pet.lonelinessLevel)
      } else {
        // Soft migration from the old wall-clock model: seed the stored level
        // from the time since the last petting.
        var hours = Number(pet.lastPetMs) > 0
          ? Math.max(0, (Date.now() - Number(pet.lastPetMs)) / 3600000) : 0
        lonelinessLevel = Math.min(100, hours / 24 * 100)
      }
      sleeping = pet.sleeping === true
    } catch (petError) {
      hatchedAtMs = 0; lastPetMs = 0
      saveProblem = "not valid JSON (" + petError + ")"
    }
    // Saves from the old growing-pet model (egg, baby, teen…) or a hand-edited
    // form start again as a fresh pod, quietly: that is a migration, not damage.
    if (knownForms.indexOf(form) < 0 || knownForms.indexOf(stage) < 0) {
      stage = "pod"
      form = "pod"
      ageMinutes = 0
      focusMinutes = 0
      careSum = 0
      careCount = 0
      hatch = true   // persist the migration right away
    }
    if (hatchedAtMs === 0) {
      hatchedAtMs = Date.now()
      lastPetMs = hatchedAtMs
      hatch = true
    }

    initialized = true
    if (saveProblem !== "") {
      console.warn("ciangotchi: save file " + petPath + " " + saveProblem + " — starting over")
      notify("Ciangotchi couldn't read its save file",
             "It was corrupt or oversized, so a fresh pod takes over.")
    }
    if (hatch) flushPet()

    updatesProc.running = true
    orphansProc.running = true
  }

  function updateSettingsInMemory(parsed) {
    var merged = {}
    for (var key in defaultSettings) merged[key] = defaultSettings[key]
    for (var loaded in parsed) if (loaded in merged) merged[loaded] = parsed[loaded]
    settings = merged
  }

  // --- probes ----------------------------------------------------------------

  Process {
    id: updatesProc
    command: ["checkupdates"]
    stdout: StdioCollector { id: updatesOut }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        var text = updatesOut.text.trim()
        root.pendingUpdates = text === "" ? 0 : text.split("\n").length
      } else if (exitCode === 2) {
        root.pendingUpdates = 0
      }
      // exit 1 = error (offline, db lock): keep the previous value.
    }
  }

  Process {
    id: orphansProc
    command: ["pacman", "-Qdtq"]
    stdout: StdioCollector { id: orphansOut }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        var text = orphansOut.text.trim()
        root.orphanCount = text === "" ? 0 : text.split("\n").length
      } else {
        root.orphanCount = 0
      }
    }
  }

  // The heartbeat: needs, age, care sampling and evolution, every minute.
  Timer {
    interval: 60 * 1000
    running: root.initialized
    repeat: true
    onTriggered: {
      root.nowMs = Date.now()
      root.applyMinute()
      root.ageMinutes += 1
      if (nudge.focused) root.focusMinutes += 1
      root.careSum += root.happiness
      root.careCount += 1
      root.maybeEvolve()
      if (root.careCount % 5 === 0) root.flushPet()
    }
  }
  // Both probes only flavor the pace, so every 30 minutes is plenty (and
  // checkupdates syncs its own db copy each time).
  Timer {
    interval: 30 * 60 * 1000
    running: root.initialized
    repeat: true
    onTriggered: orphansProc.running = true
  }
  Timer {
    interval: 30 * 60 * 1000
    running: root.initialized
    repeat: true
    onTriggered: updatesProc.running = true
  }

  // --- ciangotchi: idle nudges -------------------------------------------------

  // Majin Vegeta: a short roaming event that puts the pet in its Majin form.
  Timer {
    id: majinTimer
    interval: 60000
    onTriggered: root.eventForm = ""
  }

  // --- TEMP: form testing, remove once the forms are approved ----------------
  // Cycles pod -> … -> ego -> majin -> pod. It rewrites the saved form and
  // focus minutes, so a real run restarts from the pod afterwards.
  function testCycleForm() {
    var order = knownForms.concat(["majin"])
    var current = eventForm !== "" ? "majin" : form
    var next = order[(order.indexOf(current) + 1) % order.length]
    majinTimer.stop()
    if (next === "majin") {
      eventForm = "majin"
      return
    }
    eventForm = ""
    stage = next
    form = next
    for (var i = 0; i < ladder.length; i++) if (ladder[i].stage === next) focusMinutes = ladder[i].at
    flushPet()
  }
  function testRage() { nudge.previewRestless() }

  readonly property alias restless: nudge.restless
  readonly property alias onBreak: nudge.onBreak
  readonly property alias breakMinutesLeft: nudge.breakMinutesLeft
  readonly property alias breakLabel: nudge.breakLabel
  readonly property int breakMinutes: {
    var v = Number(settings.breakMinutes)
    return isFinite(v) && v > 0 ? Math.min(480, Math.round(v)) : 30
  }
  // minutes: how long; 0 = until the user ends it.
  function startBreak(minutes) { nudge.startBreak(minutes) }
  function endBreak() { nudge.endBreak() }
  function requestLink() { nudge.requestLink() }
  Nudge {
    id: nudge
    petService: root
  }

  // --- roaming ---------------------------------------------------------------

  // Outputs coming and going (monitors powered off, lock, unplug) destroy the
  // roam layer surface while QML still believes the window is visible — the
  // pet keeps "roaming" with nowhere to be drawn, and the return sequence's
  // visible-gated timers never fire. Dropping visibility for a beat after the
  // screen list settles forces Quickshell to map a fresh surface.
  property bool screensSettled: true
  Connections {
    target: Quickshell
    function onScreensChanged() {
      root.screensSettled = false
      screensSettleTimer.restart()
    }
  }
  Timer {
    id: screensSettleTimer
    interval: 1000
    onTriggered: root.screensSettled = true
  }

  // Deliberately a static window with a visibility binding, not a Loader:
  // dynamically created windows leak a zombie layer surface across the shell's
  // plugin hot-reload, which then wedges screencopy (grim) on that output.
  RoamWindow {
    petService: root
    visible: root.initialized && root.roaming && root.screensSettled
  }

  // --- persistence -----------------------------------------------------------

  // Bounded reads: at most maxStateBytes per file, once at startup. A file
  // that fills the cap (or can't be read) counts as empty → defaults.
  function boundedText(collector, exitCode) {
    if (exitCode !== 0) return ""
    var text = collector.text
    return text.length >= maxStateBytes ? "" : text
  }

  Process {
    id: settingsReader
    command: ["head", "-c", String(root.maxStateBytes), root.settingsPath]
    running: true
    stdout: StdioCollector { id: settingsOut }
    onExited: function(exitCode) {
      root.loadedSettingsText = root.boundedText(settingsOut, exitCode)
      root.settingsFileLoaded = true
      root.initializeIfReady()
    }
  }

  Process {
    id: petReader
    command: ["head", "-c", String(root.maxStateBytes), root.petPath]
    running: true
    stdout: StdioCollector { id: petOut }
    onExited: function(exitCode) {
      root.loadedPetText = root.boundedText(petOut, exitCode)
      if (exitCode === 0 && petOut.text.length >= root.maxStateBytes)
        root.petReadProblem = "exceeds " + root.maxStateBytes + " bytes"
      root.petFileLoaded = true
      root.initializeIfReady()
    }
  }

  // Write-only views: preload off, text() is never called, so the shell
  // never maps these files itself.
  FileView {
    id: settingsFile
    path: root.settingsPath
    preload: false
    watchChanges: false
    atomicWrites: true
    printErrors: false
  }

  FileView {
    id: petFile
    path: root.petPath
    preload: false
    watchChanges: false
    atomicWrites: true
    printErrors: false
  }
}
