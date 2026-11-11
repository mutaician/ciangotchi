import QtQuick
import QtQuick.Effects

// One animated 1-bit sprite: the two frames (a/b) of `anim` for `form`,
// tinted live with the theme's colors. If an animation's frames are not in
// assets/sprites/ yet, it falls back (to `fallbackAnim`, then to the form's
// idle, which always exists) — so sprites can land in the repo gradually
// without ever breaking a view.
Item {
  id: root

  property string form: "egg"
  property string anim: "idle"
  // What to try when `anim`'s frames are missing (e.g. "walk" for a climb).
  property string fallbackAnim: "idle"
  property int frameMs: 500
  property bool playing: true
  property color tint: "white"
  // Second layer (hair, aura, ki): "" = none, "dim" = a dimmed tint, or any
  // colour string. Drawn from assets/sprites/accent/ when the frame has one.
  property string accent: ""
  readonly property color accentTint: accent === "dim"
    ? Qt.alpha(tint, 0.55) : (accent === "" ? "transparent" : accent)
  property bool mirrored: false

  property int frame: 0
  // The animation actually shown once fallbacks are applied.
  property string resolvedAnim: anim

  function restart() {
    resolvedAnim = anim
    frame = 0
  }

  function applyFallback() {
    if (image.status !== Image.Error) return
    if (resolvedAnim !== fallbackAnim) resolvedAnim = fallbackAnim
    else if (resolvedAnim !== "idle") resolvedAnim = "idle"
  }

  onAnimChanged: restart()
  onFormChanged: restart()

  Image {
    id: image
    anchors.fill: parent
    source: Qt.resolvedUrl("assets/sprites/" + root.form + "_" + root.resolvedAnim
      + "_" + (root.frame === 0 ? "a" : "b") + ".png")
    // Nearest-neighbour scaling keeps the pixels crisp.
    smooth: false
    mipmap: false
    fillMode: Image.PreserveAspectFit
    mirror: root.mirrored
    visible: false

    // Deferred: writing resolvedAnim during the source evaluation that
    // triggered the status change would be a binding loop.
    onStatusChanged: if (status === Image.Error) Qt.callLater(root.applyFallback)
  }

  MultiEffect {
    anchors.fill: image
    source: image
    colorization: 1
    colorizationColor: root.tint
  }

  // Accent layer: same frame name under accent/. A frame without accent
  // pixels has no file, which just leaves the layer hidden.
  Image {
    id: accentImage
    anchors.fill: parent
    source: root.accent === "" ? "" : Qt.resolvedUrl("assets/sprites/accent/" + root.form
      + "_" + root.resolvedAnim + "_" + (root.frame === 0 ? "a" : "b") + ".png")
    smooth: false
    mipmap: false
    fillMode: Image.PreserveAspectFit
    mirror: root.mirrored
    visible: false
  }

  MultiEffect {
    anchors.fill: accentImage
    source: accentImage
    visible: accentImage.status === Image.Ready
    colorization: 1
    colorizationColor: root.accentTint
  }

  Timer {
    interval: root.frameMs
    running: root.playing && root.visible
    repeat: true
    onTriggered: root.frame = root.frame === 0 ? 1 : 0
  }
}
