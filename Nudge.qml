import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// The pet's conscience. When keyboard and mouse have been quiet for
// settings.idleMinutes it starts bugging you: it acts up (fidgets, makes a
// noise), sometimes sends a notification, and sometimes gets mischievous and
// opens a link from your bookmarks or your own list. "Take a break" silences
// all of it until the break runs out.
//
// Idle comes from the compositor's ext-idle-notify (the same thing hypridle
// listens to), so it works with locking and screensavers switched off.
//
// Commands executed (fixed argv):
//   head -c N <bookmarks file>   read the browser's bookmarks
//   xdg-open <url>               open a link (http/https only)
Item {
  id: root

  property var petService: null

  readonly property var cfg: petService ? petService.settings : ({})

  // --- settings, sanitised ---------------------------------------------------

  readonly property real idleMinutes: {
    var v = Number(cfg.idleMinutes)
    return isFinite(v) ? Math.max(1, Math.min(240, v)) : 10
  }
  readonly property real mischiefChance: {
    var v = Number(cfg.mischiefChance)
    return isFinite(v) ? Math.max(0, Math.min(1, v)) : 0.25
  }
  readonly property real notifyChance: 0.5

  // --- break mode ------------------------------------------------------------

  property double nowMs: Date.now()
  readonly property double breakUntilMs: Number(cfg.breakUntilMs) || 0
  readonly property bool onBreak: breakUntilMs > nowMs
  readonly property int breakMinutesLeft: onBreak
    ? Math.ceil((breakUntilMs - nowMs) / 60000) : 0

  Timer {
    interval: 15000
    running: root.breakUntilMs > 0
    repeat: true
    triggeredOnStart: true
    onTriggered: root.nowMs = Date.now()
  }

  function startBreak(minutes) {
    if (!petService) return
    nowMs = Date.now()
    petService.updateSettings({ breakUntilMs: nowMs + minutes * 60000 })
    settle()
  }

  function endBreak() {
    if (!petService) return
    petService.updateSettings({ breakUntilMs: 0 })
  }

  // --- idle watching ---------------------------------------------------------

  readonly property bool watching: !!petService && petService.initialized
    && cfg.nudgesEnabled !== false && !onBreak

  // True for a while after a nudge: views make the pet fidget.
  property bool restless: false

  IdleMonitor {
    id: monitor
    enabled: root.watching
    timeout: Math.round(root.idleMinutes * 60)
    // A video or an inhibitor app must not stop it noticing you left.
    respectInhibitors: false
    onIsIdleChanged: {
      if (isIdle) {
        root.nudge()
        repeatTimer.restart()
      } else {
        repeatTimer.stop()
        root.settle()
      }
    }
  }

  // Still away? It keeps pestering, at a gentler pace than the first nudge.
  Timer {
    id: repeatTimer
    interval: Math.max(2, Math.min(5, root.idleMinutes / 2)) * 60000
    repeat: true
    onTriggered: if (monitor.isIdle && root.watching) root.nudge()
  }

  Timer {
    id: calmTimer
    interval: 45000
    onTriggered: root.restless = false
  }

  // Back to normal: you are here, or a break has started.
  function settle() {
    calmTimer.stop()
    restless = false
    repeatTimer.stop()
  }

  onWatchingChanged: {
    if (!watching) settle()
  }

  // --- the nudge -------------------------------------------------------------

  readonly property var nagLines: [
    "Hey. You've been away from the keyboard. Work?",
    "Psst. Remember what you were doing?",
    "The scrolling isn't going to build itself a project.",
    "I'm bored. Let's get back to it.",
    "Ten minutes of nothing. Come on.",
    "Your future self is watching. Disappointed, but watching."
  ]

  function pick(list) {
    return list[Math.floor(Math.random() * list.length)]
  }

  // Always acts up; sometimes notifies; sometimes gets into mischief.
  function nudge() {
    if (!watching || !petService) return
    var sleepingPet = petService.sleeping
    if (!sleepingPet && petService.stage !== "egg") {
      restless = true
      calmTimer.restart()
      petService.playSound(pick(["stun", "grab", "hum"]))
    }
    var doLink = Math.random() < mischiefChance
    var doNotify = doLink || sleepingPet || Math.random() < notifyChance
    if (doLink) {
      var url = pickLink()
      if (url !== "") {
        openLink(url)
        petService.notify("Ciangotchi", "I found something for you: " + hostOf(url))
        return
      }
    }
    if (doNotify) petService.notify("Ciangotchi", pick(nagLines))
  }

  // --- links -----------------------------------------------------------------

  readonly property string bookmarksPath: {
    var p = cfg.bookmarksPath
    if (typeof p === "string" && p !== "") return p
    return (Quickshell.env("HOME") || "")
      + "/.config/BraveSoftware/Brave-Browser/Default/Bookmarks"
  }

  property var bookmarkUrls: []

  function isWebUrl(u) {
    return typeof u === "string" && /^https?:\/\/\S+$/.test(u)
  }

  function hostOf(url) {
    var m = /^https?:\/\/([^\/?#]+)/.exec(url)
    return m ? m[1].replace(/^www\./, "") : url
  }

  function collect(node, out) {
    if (!node) return
    if (node.type === "url" && isWebUrl(node.url)) out.push(node.url)
    var kids = node.children || []
    for (var i = 0; i < kids.length; i++) collect(kids[i], out)
  }

  function parseBookmarks(text) {
    var out = []
    try {
      var roots = JSON.parse(text).roots || {}
      for (var name in roots) collect(roots[name], out)
    } catch (e) {
      console.warn("ciangotchi: bookmarks unreadable (" + e + ")")
    }
    bookmarkUrls = out
  }

  function customLinks() {
    var list = Array.isArray(cfg.links) ? cfg.links : []
    var out = []
    for (var i = 0; i < list.length; i++) if (isWebUrl(list[i])) out.push(list[i])
    return out
  }

  // Half the time one of your own links (fmhy, X bookmarks, YouTube Watch
  // Later…), half the time a random browser bookmark; whichever list exists
  // if the other is empty.
  function pickLink() {
    var mine = customLinks()
    var marks = cfg.includeBookmarks === false ? [] : bookmarkUrls
    if (mine.length === 0 && marks.length === 0) return ""
    var useMine = marks.length === 0 || (mine.length > 0 && Math.random() < 0.5)
    return pick(useMine ? mine : marks)
  }

  function openLink(url) {
    if (!isWebUrl(url)) return
    Quickshell.execDetached(["xdg-open", url])
  }

  Process {
    id: bookmarksReader
    command: ["head", "-c", "8000000", root.bookmarksPath]
    stdout: StdioCollector { id: bookmarksOut }
    onExited: function(exitCode) {
      if (exitCode === 0) root.parseBookmarks(bookmarksOut.text)
    }
  }

  // Bookmarks change slowly: read once the pet is up, then hourly.
  Timer {
    interval: 60 * 60 * 1000
    running: !!root.petService && root.petService.initialized
    repeat: true
    triggeredOnStart: true
    onTriggered: bookmarksReader.running = true
  }
}
