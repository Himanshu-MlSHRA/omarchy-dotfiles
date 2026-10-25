import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "BarModel.js" as BarModel
import "IslandBridge.js" as IslandBridge

Item {
  id: root

  // The omarchy-shell host injects omarchyPath from OMARCHY_PATH.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  // Injected by the host shell so bar slots can resolve enabled widgets.
  property var barWidgetRegistry: fallbackBarWidgetRegistry
  // Read-only registry view for third-party full bars; the built-in bar does
  // not otherwise need it, but declaring it keeps clone construction atomic.
  property var pluginRegistry: null
  // Injected by the host shell every time shell.json is reloaded. Holds the
  // `bar:` subtree: position, centerAnchor, layout. The host owns file IO;
  // the bar just renders whatever it's handed. The bar font follows the
  // OS-level fontconfig monospace binding — it is not stored in shell.json.
  property var barConfig: ({})
  // Injected by the host shell. Used for shell-wide actions such as opening
  // settings and persisting inline widget state.
  property var shell: null
  // Manifest for the active bar option. Present for custom bars and useful for
  // diagnostics; the built-in bar does not otherwise need it.
  property var manifest: null
  QtObject {
    id: fallbackBarWidgetRegistry
    property var widgets: ({})
    property int revision: 0
    function metadataFor(id) { return null }
  }
  // Mirrors the on-disk `bar-off` flag so the user can hide the bar without
  // killing the entire shell. Hidden panels stay mapped but park off-screen
  // without an exclusion zone; updated by the FileView watcher further down.
  property bool barHidden: false
  property string home: Quickshell.env("HOME")
  property string stateHome: home + "/.local/state"
  property string omarchyConfigDir: home + "/.config/omarchy"
  property var fallbackBarConfig: ({
    position: "top",
    transparent: false,
    centerAnchor: "omarchy.clock",
    layout: { left: [], center: [], right: [] }
  })
  property var layoutConfig: fallbackBarConfig.layout
  property string centerAnchor: ""
  property bool requestedTransparent: false
  property bool useTransparentForeground: false
  property bool transparent: false
  property bool centerSectionHovered: false
  // One bar surface exists per monitor and each reports into this count, so a
  // pointer crossing from one monitor's bar to another's stays counted however
  // the enter and leave interleave. A single shared bool would be left false by
  // whichever event landed last.
  property int barHoverCount: 0
  // True while the pointer is over any bar, widgets included.
  readonly property bool barHovered: barHoverCount > 0
  property bool centerSectionRevealHeld: false
  property bool centerHoverRevealSuppressed: false
  property int barConfigSerial: 0
  property string position: "top"
  // Resolves through fontconfig at paint time (Style.font.family defaults
  // to "monospace"), so changing the system font (via `omarchy-font-set`)
  // updates the bar without a reload.
  property string fontFamily: Style.font.family
  // Bound to the central Color singleton so the bar tracks shell.toml's
  // [bar] section. Property names kept for the rest of this file's bindings.
  property color themeForeground: Color.bar.text
  property color themeContrastForeground: Color.background
  property color transparentForeground: Color.bar.text
  property color foreground: themeForeground
  property color barForeground: useTransparentForeground ? transparentForeground : themeForeground
  property bool foregroundAnimationEnabled: true
  property color background: Color.bar.background
  property color urgent: Color.bar.active

  Behavior on barForeground { enabled: root.foregroundAnimationEnabled; ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  Behavior on background { ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  Behavior on urgent { ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  property var tooltipTarget: null
  property var pendingTooltipTarget: null
  property string tooltipText: ""
  property string pendingTooltipText: ""
  property bool tooltipShown: false
  property int tooltipRequest: 0
  property var activePopout: null
  property var barDragSource: null
  property var barDragTarget: null
  property var barDragTargetGeometry: null
  property bool barDragAfter: false
  property var barDragWindow: null
  property var barDragScreen: null
  property url barDragImageUrl: ""
  property real barDragSceneX: 0
  property real barDragSceneY: 0
  property real barDragScreenX: 0
  property real barDragScreenY: 0
  property real barDragOffsetX: 0
  property real barDragOffsetY: 0
  property bool barMoveActive: false
  property string barMoveCandidate: ""
  property var barMoveWindow: null
  property var barMoveScreen: null
  property var clickTargets: []
  property var moduleSlots: []
  property var pluginBarApis: ({})
  property var pluginObjectOwners: []

  Component {
    id: pluginBarApiComponent
    PluginBarApi { }
  }

  function publicLayoutConfig() {
    return JSON.parse(JSON.stringify(root.layoutConfig || {}))
  }

  function bindPluginBarApi(api) {
    if (!api) return
    api.foreground = Qt.binding(function() { return root.foreground })
    api.barForeground = Qt.binding(function() { return root.barForeground })
    api.background = Qt.binding(function() { return root.background })
    api.urgent = Qt.binding(function() { return root.urgent })
    api.fontFamily = Qt.binding(function() { return root.fontFamily })
    api.position = Qt.binding(function() { return root.position })
    api.vertical = Qt.binding(function() { return root.vertical })
    api.barSize = Qt.binding(function() { return root.barSize })
    api.transparent = Qt.binding(function() { return root.transparent })
    api.foregroundAnimationEnabled = Qt.binding(function() { return root.foregroundAnimationEnabled })
    api.centerSectionRevealHeld = Qt.binding(function() { return root.centerSectionRevealHeld })
    api._centerHoverRevealSuppressed = Qt.binding(function() { return root.centerHoverRevealSuppressed })
    root.syncPluginBarApiObjects(api)
  }

  function syncPluginBarApiObjects(api) {
    if (!api) return
    api.activePopout = root.pluginOwnsBarObject(api.pluginId, root.activePopout)
      ? root.activePopout : (root.activePopout ? api.foreignPopoutMarker : null)
    api.clickTargets = root.pluginClickTargets(api.pluginId)
    api.layoutConfig = root.publicLayoutConfig()
  }

  function pluginObjectRecord(target) {
    for (var i = 0; i < pluginObjectOwners.length; i++) {
      var record = pluginObjectOwners[i]
      if (record && record.target === target) return record
    }
    return null
  }

  function markPluginObject(pluginId, target, role) {
    var key = String(pluginId || "")
    if (!key || !target) return false
    var record = root.pluginObjectRecord(target)
    if (record && record.pluginId !== key) return false
    var next = []
    for (var i = 0; i < pluginObjectOwners.length; i++) {
      var existing = pluginObjectOwners[i]
      if (!existing || existing.target !== target) next.push(existing)
    }
    var updated = record || { target: target, pluginId: key, clickTarget: false, popout: false }
    updated[role] = true
    next.push(updated)
    pluginObjectOwners = next
    return true
  }

  function unmarkPluginObject(pluginId, target, role) {
    var key = String(pluginId || "")
    var next = []
    for (var i = 0; i < pluginObjectOwners.length; i++) {
      var record = pluginObjectOwners[i]
      if (!record || record.target !== target || record.pluginId !== key) {
        next.push(record)
        continue
      }
      record[role] = false
      if (record.clickTarget || record.popout) next.push(record)
    }
    pluginObjectOwners = next
  }

  function pluginOwnsBarObject(pluginId, target) {
    var record = target ? root.pluginObjectRecord(target) : null
    return !!record && record.pluginId === String(pluginId || "")
  }

  function pluginClickTargets(pluginId) {
    var out = []
    for (var i = 0; i < root.clickTargets.length; i++) {
      var target = root.clickTargets[i]
      if (root.pluginOwnsBarObject(pluginId, target)) out.push(target)
    }
    return out
  }

  function syncAllPluginBarApiObjects() {
    for (var id in pluginBarApis) root.syncPluginBarApiObjects(pluginBarApis[id])
  }

  function registerPluginClickTarget(pluginId, target) {
    if (!root.markPluginObject(pluginId, target, "clickTarget")) return
    root.registerClickTarget(target)
  }

  function unregisterPluginClickTarget(pluginId, target) {
    if (!root.pluginOwnsBarObject(pluginId, target)) return
    root.unregisterClickTarget(target)
    root.unmarkPluginObject(pluginId, target, "clickTarget")
  }

  function requestPluginPopout(pluginId, owner) {
    if (!root.markPluginObject(pluginId, owner, "popout")) return
    root.requestPopout(owner)
  }

  function releasePluginPopout(pluginId, owner) {
    if (!root.pluginOwnsBarObject(pluginId, owner)) return
    root.releasePopout(owner)
    root.unmarkPluginObject(pluginId, owner, "popout")
  }

  function pluginBarApiFor(pluginId, moduleName, registered) {
    var key = String(pluginId || "")
    if (!key) return null

    var pluginShell = null
    if (registered && root.shell && typeof root.shell.pluginShellForId === "function") {
      // Only the trusted built-in bar receives ShellRoot and can request a
      // service-capable facade for the widget it is instantiating.
      pluginShell = root.shell.pluginShellForId(moduleName)
    } else if (root.shell && typeof root.shell.pluginShellForBarEntry === "function") {
      // Replacement bars receive a service-less entry facade. Giving an
      // untrusted bar a generic facade factory would let it retrieve another
      // third-party plugin's live service object.
      pluginShell = root.shell.pluginShellForBarEntry(key, moduleName)
    }

    if (pluginBarApis[key]) {
      pluginBarApis[key].shell = pluginShell
      return pluginBarApis[key]
    }

    var api = pluginBarApiComponent.createObject(null, {
      pluginId: key,
      moduleName: String(moduleName || ""),
      shell: pluginShell,
      _showTooltip: function(target, text) { root.showTooltip(target, text) },
      _hideTooltip: function(target) { root.hideTooltip(target) },
      _registerClickTarget: function(target) { root.registerPluginClickTarget(key, target) },
      _unregisterClickTarget: function(target) { root.unregisterPluginClickTarget(key, target) },
      _requestPopout: function(owner) { root.requestPluginPopout(key, owner) },
      _releasePopout: function(owner) { root.releasePluginPopout(key, owner) },
      _switchPanelFrom: function(owner, direction) { return root.switchPanelFrom(owner, direction) },
      _targetBelongsToWindow: function(target, window) { return root.targetBelongsToWindow(target, window) },
      _moduleWidgets: function(requestedId) {
        return String(requestedId || "") === String(moduleName || "")
          ? root.moduleWidgets(moduleName) : []
      },
      _run: function(command) { root.run(command) },
      _setCenterHoverRevealSuppressed: function(value) {
        root.centerHoverRevealSuppressed = !!value
      }
    })
    if (!api) return null
    root.bindPluginBarApi(api)

    var next = ({})
    for (var id in pluginBarApis) next[id] = pluginBarApis[id]
    next[key] = api
    pluginBarApis = next
    return api
  }

  function pluginBarApiUsed(pluginId) {
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (slot && slot.pluginApiId === pluginId) return true
    }
    return false
  }

  function releasePluginObjects(pluginId) {
    var owned = pluginObjectOwners.slice()
    for (var i = 0; i < owned.length; i++) {
      var record = owned[i]
      if (!record || record.pluginId !== pluginId) continue
      if (record.clickTarget) root.unregisterClickTarget(record.target)
      if (record.popout && root.activePopout === record.target) root.releasePopout(record.target)
    }
    pluginObjectOwners = pluginObjectOwners.filter(function(record) {
      return record && record.pluginId !== pluginId
    })
  }

  function prunePluginBarApis() {
    var next = ({})
    for (var id in pluginBarApis) {
      var api = pluginBarApis[id]
      if (root.pluginBarApiUsed(id)) {
        next[id] = api
        continue
      }
      root.releasePluginObjects(id)
      if (api && typeof api.destroy === "function") api.destroy()
    }
    pluginBarApis = next
  }

  onActivePopoutChanged: syncAllPluginBarApiObjects()
  onClickTargetsChanged: syncAllPluginBarApiObjects()
  onLayoutConfigChanged: syncAllPluginBarApiObjects()
  onModuleSlotsChanged: Qt.callLater(prunePluginBarApis)

  Component.onDestruction: {
    for (var id in pluginBarApis) {
      root.releasePluginObjects(id)
      if (pluginBarApis[id] && typeof pluginBarApis[id].destroy === "function")
        pluginBarApis[id].destroy()
    }
    pluginBarApis = ({})
  }

  function registerClickTarget(target) {
    if (!target || clickTargets.indexOf(target) !== -1) return
    var next = clickTargets.slice()
    next.push(target)
    clickTargets = next
  }

  function unregisterClickTarget(target) {
    var next = clickTargets.filter(function(item) { return item !== target })
    clickTargets = next
  }

  function registerModuleSlot(slot) {
    if (!slot || moduleSlots.indexOf(slot) !== -1) return
    var next = moduleSlots.slice()
    next.push(slot)
    moduleSlots = next
  }

  function unregisterModuleSlot(slot) {
    var next = moduleSlots.filter(function(item) { return item !== slot })
    moduleSlots = next
  }

  function debugBarGeometry() {
    var out = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem) continue
      var point = { x: slot.x, y: slot.y }
      try {
        point = slot.mapToItem(null, 0, 0)
      } catch (e) {
      }
      out.push({
        id: slot.moduleName,
        section: slot.region,
        x: Math.round(point.x),
        y: Math.round(point.y),
        width: Math.round(slot.width),
        height: Math.round(slot.height),
        visible: slot.visible === true && slot.width > 0 && slot.height > 0,
        itemVisible: slot.activeItem.visible === true,
        itemWidth: Math.round(slot.activeItem.implicitWidth || 0),
        itemHeight: Math.round(slot.activeItem.implicitHeight || 0)
      })
    }
    return out
  }

  function targetWindow(target) {
    return target && target.QsWindow ? target.QsWindow.window : null
  }

  function targetBelongsToWindow(target, window) {
    return !!target && !!window && targetWindow(target) === window
  }

  function slotWindow(slot) {
    if (!slot) return null
    return targetWindow(slot.activeItem) || targetWindow(slot)
  }

  function sameWindow(left, right) {
    if (!left || !right) return false
    if (left === right) return true
    return !!left.screen && !!right.screen && !!left.screen.name && !!right.screen.name && left.screen.name === right.screen.name
  }

  function targetTooltipHovered(target) {
    return !!target && target.visible !== false && target.opacity !== 0 && target.tooltipHovered === true
  }

  function clearTooltip() {
    tooltipTimer.stop()
    pendingTooltipTarget = null
    pendingTooltipText = ""
    tooltipTarget = null
    tooltipText = ""
    tooltipShown = false
  }

  function clearBarDrag() {
    barDragSource = null
    barDragWindow = null
    barDragScreen = null
    barDragImageUrl = ""
    barDragTarget = null
    barDragTargetGeometry = null
    barDragAfter = false
    barDragSceneX = 0
    barDragSceneY = 0
    barDragScreenX = 0
    barDragScreenY = 0
    barDragOffsetX = 0
    barDragOffsetY = 0
  }

  function windowScreenPoint(scenePoint, window) {
    var x = scenePoint ? scenePoint.x : 0
    var y = scenePoint ? scenePoint.y : 0
    if (!window || !window.screen) return { x: x, y: y }

    if (root.position === "bottom")
      y += Math.max(0, window.screen.height - window.height)
    else if (root.position === "right")
      x += Math.max(0, window.screen.width - window.width)

    return { x: x, y: y }
  }

  function barDragScreenPoint(scenePoint) {
    return windowScreenPoint(scenePoint, barDragWindow)
  }

  function dropMarkerRect(slot, after) {
    if (!slot) return null

    try {
      var slotPoint = slot.mapToItem(null, 0, 0)
      var screenPoint = barDragScreenPoint(slotPoint)
      var thickness = Style.spacing.xs
      if (vertical) {
        return {
          x: screenPoint.x,
          y: screenPoint.y + (after ? slot.height : 0) - thickness / 2,
          width: slot.width,
          height: thickness
        }
      }

      return {
        x: screenPoint.x + (after ? slot.width : 0) - thickness / 2,
        y: screenPoint.y,
        width: thickness,
        height: slot.height
      }
    } catch (e) {
      return null
    }
  }

  // Split the screen along its diagonals (in normalized space, so widescreens
  // don't bias toward left/right): whichever triangle holds the cursor names
  // the candidate edge.
  function nearestScreenEdge(point, screen) {
    var nx = screen.width > 0 ? Util.clamp(point.x / screen.width, 0, 1) : 0.5
    var ny = screen.height > 0 ? Util.clamp(point.y / screen.height, 0, 1) : 0.5

    var edge = "top"
    var best = ny
    if (1 - ny < best) { edge = "bottom"; best = 1 - ny }
    if (nx < best) { edge = "left"; best = nx }
    if (1 - nx < best) { edge = "right"; best = 1 - nx }
    return edge
  }

  function beginBarMove(window) {
    barMoveWindow = window
    barMoveScreen = window ? window.screen : null
    barMoveCandidate = position
    barMoveActive = true
  }

  function updateBarMove(screenPoint) {
    if (!barMoveActive || !barMoveScreen) return
    barMoveCandidate = nearestScreenEdge(screenPoint, barMoveScreen)
  }

  function clearBarMove() {
    barMoveActive = false
    barMoveCandidate = ""
    barMoveWindow = null
    barMoveScreen = null
  }

  function finishBarMove() {
    var edge = barMoveCandidate
    if (!barMoveActive || !edge || edge === position) {
      clearBarMove()
      return
    }

    clearBarMove()
    setBarPosition(edge)
  }

  function setBarPosition(value) {
    var next = normalizePosition(value)
    if (root.shell && typeof root.shell.mutateShellConfig === "function") {
      root.shell.mutateShellConfig(function(config) {
        if (!Util.isPlainObject(config.bar)) config.bar = {}
        config.bar.position = next
      })
    } else {
      root.position = next
    }
  }

  function captureBarDragGhost(slot) {
    var item = slot && slot.activeItem ? slot.activeItem : null
    barDragImageUrl = ""
    if (!item || typeof item.grabToImage !== "function") return

    var grabWidth = Math.max(1, Math.ceil(item.width || item.implicitWidth || slot.width || 1))
    var grabHeight = Math.max(1, Math.ceil(item.height || item.implicitHeight || slot.height || 1))
    item.grabToImage(function(result) {
      if (root.barDragSource !== slot || !result || !result.url) return
      root.barDragImageUrl = result.url
    }, Qt.size(grabWidth, grabHeight))
  }

  function requestPopout(owner) {
    if (activePopout === owner) return
    if (activePopout) {
      if ("closeForPopoutSwitch" in activePopout) activePopout.closeForPopoutSwitch()
      else if ("close" in activePopout) activePopout.close()
    }
    activePopout = owner
  }

  function releasePopout(owner) {
    if (activePopout === owner) activePopout = null
  }

  readonly property bool vertical: position === "left" || position === "right"
  // What the compositor reserves. For the island that is its collapsed
  // footprint plus its top margin, held constant across states so expanding
  // never reflows tiled windows. The layer surface itself is taller (see
  // islandTokens.windowHeight); input is masked to the glass.
  readonly property int barSize: vertical ? Style.bar.sizeVertical : islandTokensObject.reservedHeight

  function normalizePosition(value) {
    return BarModel.normalizePosition(value)
  }

  // Apply tray-pinning on top of the shared layout normalization so the
  // bar host and scriptable config helpers can't drift on entry shape.
  function normalizeLayout(layout) {
    var normalized = Util.normalizeLayout(Util.isPlainObject(layout) ? layout : fallbackBarConfig.layout)
    return {
      left:   pinTrayToInner(normalized.left,   "left"),
      center: pinTrayToInner(normalized.center, "center"),
      right:  pinTrayToInner(normalized.right,  "right")
    }
  }

  // The tray drawer reveals inward (away from the bar edge). Place it at the
  // section's inner edge: start of the right section, end of the left/center
  // sections. The drawer's reserved space then sits next to the bar center,
  // not stranded mid-section.
  function pinTrayToInner(entries, section) {
    return BarModel.pinTrayToInner(entries, section)
  }

  function applyBarConfig() {
    var config = Util.isPlainObject(barConfig) ? barConfig : fallbackBarConfig

    position = normalizePosition(config.position)
    setRequestedTransparency(config.transparent === true)
    centerAnchor = Util.canonicalWidgetId(config.centerAnchor || "")

    // layoutEntries feeds plain JS arrays to the module Repeaters, and QML
    // cannot diff those: reassigning layoutConfig rebuilds every widget on
    // every monitor. When a shell.json write only changed inline widget
    // settings, patch the live layout and running widgets in place instead.
    var next = normalizeLayout(config.layout)
    var delta = BarModel.inlineSettingsDelta(layoutConfig, next)
    if (delta) {
      applySettingsDelta(delta)
      return
    }
    layoutConfig = next
    barConfigSerial++
  }

  function applySettingsDelta(delta) {
    for (var i = 0; i < delta.length; i++) {
      var change = delta[i]
      layoutConfig[change.region][change.index] = change.entry
      var settings = entrySettings(change.entry)
      for (var s = 0; s < moduleSlots.length; s++) {
        var slot = moduleSlots[s]
        if (!slot || slot.region !== change.region || slot.moduleName !== entryId(change.entry)) continue
        var item = slot.activeItem
        if (item && "settings" in item) item.settings = settings
      }
    }
  }

  onBarConfigChanged: applyBarConfig()

  function layoutEntries(region) {
    var serial = barConfigSerial
    var entries = layoutConfig ? layoutConfig[region] : null
    return Array.isArray(entries) ? entries : []
  }

  // Tab order for the panels in one bar region. Scoped to a single bar surface
  // so tabbing walks the bar the open panel belongs to instead of hopping the
  // panel to another monitor's copy of the same widget.
  function panelNavigationSlots(region, window) {
    var entries = layoutEntries(region)
    var slots = []
    for (var i = 0; i < entries.length; i++) {
      var id = entryId(entries[i])
      for (var j = 0; j < moduleSlots.length; j++) {
        var slot = moduleSlots[j]
        if (!slot || slot.region !== region || slot.moduleName !== id) continue
        if (window && !sameWindow(slotWindow(slot), window)) continue
        var item = slot.activeItem
        if (!item || item.visible !== true || slot.visible !== true || slot.width <= 0 || slot.height <= 0) continue
        if (typeof item.open !== "function" || typeof item.close !== "function" || item.opened === undefined) continue
        slots.push(slot)
        break
      }
    }
    return slots
  }

  // The Nth panel in a bar region, counted the way the bar reads: layout order,
  // and only the panels actually on screen. A widget with no panel (the tray)
  // and one that is hiding itself are passed over, so the number lands on the
  // Nth panel icon the user can see rather than the Nth layout entry.
  // One-based, because it exists for hotkeys; anything else lands on no slot.
  //
  // Counting any bar surface is enough: every monitor lays its bar out from the
  // one layout, and summoning the id routes through pickPanelSlot, which opens
  // the focused monitor's copy whichever surface was counted.
  function panelWidgetIdAt(region, index) {
    var slots = panelNavigationSlots(String(region || ""), null)
    var slot = slots[Math.round(Number(index)) - 1]
    return slot ? String(slot.moduleName || "") : ""
  }

  function switchPanelFrom(owner, direction) {
    if (!owner) return false

    var currentSlot = null
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (slot && slot.activeItem === owner) {
        currentSlot = slot
        break
      }
    }
    if (!currentSlot) return false

    var slots = panelNavigationSlots(currentSlot.region, slotWindow(currentSlot))
    if (slots.length < 2) return false

    var currentIndex = -1
    for (var j = 0; j < slots.length; j++) {
      if (slots[j] === currentSlot) {
        currentIndex = j
        break
      }
    }
    if (currentIndex < 0) return false

    var step = direction < 0 ? -1 : 1
    var nextSlot = slots[(currentIndex + step + slots.length) % slots.length]
    if (!nextSlot || !nextSlot.activeItem || nextSlot.activeItem === owner) return false

    nextSlot.activeItem.open()
    return true
  }

  // Every live instance of a widget id. A bar surface is built per monitor, so
  // a widget that appears once in the layout is still live once per screen.
  function moduleWidgets(pluginId) {
    var id = String(pluginId || "")
    var items = []
    if (!id) return items
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem || slot.moduleName !== id) continue
      items.push(slot.activeItem)
    }
    return items
  }

  function slotScreenName(slot) {
    var window = slotWindow(slot)
    return window && window.screen ? String(window.screen.name || "") : ""
  }

  // The output Hyprland has focused, which is where a keyboard-summoned panel
  // belongs. Empty until Hyprland reports one, which leaves panel routing on
  // its per-monitor fallback rather than guessing at an output.
  function focusedScreenName() {
    var monitor = Hyprland.focusedMonitor
    return monitor ? String(monitor.name || "") : ""
  }

  // Resolve the live bar-widget instance for a plugin id (e.g. "omarchy.bluetooth").
  // Only widgets that expose popup open/close methods count; plain indicators
  // (clock, workspaces, tray) return null. Used by shell.summon/toggle so
  // panel hotkeys route through the bar instead of a per-target IPC handler
  // that only reaches whichever per-monitor instance claimed the target.
  function findPanelWidget(pluginId) {
    var id = String(pluginId || "")
    if (!id) return null
    var candidates = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem) continue
      if (slot.moduleName !== id) continue
      var item = slot.activeItem
      if (typeof item.open !== "function" || typeof item.close !== "function" || item.opened === undefined) continue
      candidates.push({ slot: slot, screenName: slotScreenName(slot), opened: item.opened === true })
    }
    // One copy per monitor, plus a zero-size placeholder for anchored center
    // modules. See BarModel.pickPanelSlot for which one a hotkey acts on.
    var chosen = BarModel.pickPanelSlot(candidates, focusedScreenName())
    return chosen ? chosen.activeItem : null
  }

  function summonBarWidget(pluginId) {
    var item = findPanelWidget(pluginId)
    if (!item || typeof item.open !== "function") return false
    item.open()
    return true
  }

  function hideBarWidget(pluginId) {
    var item = findPanelWidget(pluginId)
    if (!item || typeof item.close !== "function") return false
    item.close()
    return true
  }

  function isBarWidgetOpen(pluginId) {
    var item = findPanelWidget(pluginId)
    return !!item && item.opened === true
  }

  function entrySettings(entry) {
    return BarModel.entrySettings(entry)
  }

  function entryId(entry) {
    return BarModel.entryId(entry)
  }

  function moduleString(entry, key, fallback) {
    return BarModel.moduleString(entry, key, fallback)
  }

  function entryIndex(entries, name) {
    return BarModel.entryIndex(entries, name)
  }

  function entriesBefore(entries, name) {
    return BarModel.entriesBefore(entries, name)
  }

  function entriesAfter(entries, name) {
    return BarModel.entriesAfter(entries, name)
  }

  function canonicalWidgetId(name) {
    return Util.canonicalWidgetId(name)
  }

  function expandPath(path) {
    return BarModel.expandPath(path, home)
  }

  function customModuleSafeName(name) {
    return BarModel.customModuleSafeName(name)
  }

  function customModuleType(entry) {
    return BarModel.customModuleType(entry)
  }

  function customModuleSource(entry) {
    var source = BarModel.customModulePath(entry, home, omarchyConfigDir)
    return source ? Util.fileUrl(source) : ""
  }

  Component.onCompleted: { applyBarConfig(); IslandBridge.bar = root }

  // Revealing the indicators widens their section, which can slide a neighbour
  // under a stationary pointer. Collapsing on that un-hover would move it back
  // out and re-open the peek, so hold until the pointer leaves the bar.
  function setCenterSectionHovered(hovered) {
    centerSectionHovered = hovered
    if (hovered) {
      centerSectionRevealTimer.stop()
      centerSectionRevealHeld = true
    } else {
      centerSectionRevealTimer.restart()
    }
  }

  function setBarHovered(hovered) {
    barHoverCount = Math.max(0, barHoverCount + (hovered ? 1 : -1))
    if (barHoverCount === 0) centerSectionRevealTimer.restart()
  }

  // ---- Dynamic island ------------------------------------------------------
  // The island has three content states and one surface. `islandExpanded` is
  // the user's own state, set by clicking; `islandStatus.bannerActive` is the
  // system's, set by an event and released on a timer. The user's outranks the
  // system's, which is why a banner is dropped rather than queued while the
  // island is open.
  // Exposed as properties, not just ids: the bar's panel components and the
  // island's own children reach them through `root`.
  readonly property var islandTokens: islandTokensObject
  readonly property var islandSystem: islandSystemObject
  readonly property var islandStatus: islandStatusObject
  // Written by the island surface; read back over IPC by anshu.menu's genie.
  property real islandMouthWidth: 0
  // The island as it is drawn this frame (mid-morph included), for the
  // window flights' cut-out: total width (fillets included), height, radii.
  property real islandLiveWidth: 0
  property real islandLiveHeight: 0
  property real islandLiveTopRadius: 0
  property real islandLiveBottomRadius: 0

  IslandTokens { id: islandTokensObject }

  // ---- the island becoming the menu (Panacea's settings morph) -------------
  // anshu.menu sets islandAway the frame its card starts growing out of the
  // pill: the pill is gone because it *is* the card. When the card is back
  // home it clears it; the pill reappears in place, its content fades in and
  // the concave corners return a beat later (Panacea: animMs + 40).
  property bool islandAway: false
  property bool islandCornersOn: true
  onIslandAwayChanged: {
    if (islandAway) { cornerRevealTimer.stop(); islandCornersOn = false }
    else cornerRevealTimer.restart()
  }
  Timer { id: cornerRevealTimer; interval: 40; onTriggered: root.islandCornersOn = true }
  // Set by the menu for the hand-back: the card already arrived wearing the
  // pill's content, so the island shows its own at full strength at once.
  property bool islandSnap: false
  onIslandSnapChanged: if (islandSnap) islandSnapTimer.restart()
  Timer { id: islandSnapTimer; interval: 120; onTriggered: root.islandSnap = false }
  // The pill's own rectangle (without the corners), for the menu's morph.
  property real islandPillWidth: 0
  // The island's live surface colour (tinted while recording etc.), so the
  // card that leaves it is exactly the same colour.
  property color islandSurfaceColor: islandTokensObject.surface

  IslandSystem { id: islandSystemObject }

  // Windows are thrown out of the island on open and pulled back in on close.
  // Off with {"windowFlight": false} in ~/.config/omarchy/island.json.
  property bool islandWindowFlight: true
  FileView {
    path: root.home + "/.config/omarchy/island.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.islandWindowFlight = JSON.parse(text()).windowFlight !== false } catch (e) { root.islandWindowFlight = true }
    }
    onLoadFailed: root.islandWindowFlight = true
  }
  Loader {
    active: root.islandWindowFlight
    sourceComponent: islandFlightComponent
  }
  Component {
    id: islandFlightComponent
  IslandFlight {
    tk: root.islandTokens
    islandWidth: root.islandLiveWidth > 0 ? root.islandLiveWidth
      : (root.islandMouthWidth > 0 ? root.islandMouthWidth : root.islandTokens.px(200))
    islandHeight: root.islandLiveHeight > 0 ? root.islandLiveHeight : root.islandTokens.collapsedHeight
    islandTopRadius: root.islandLiveHeight > 0 ? root.islandLiveTopRadius : root.islandTokens.collapsedTopRadius
    islandBottomRadius: root.islandLiveHeight > 0 ? root.islandLiveBottomRadius : root.islandTokens.collapsedBottomRadius
  }
  }

  IslandStatus {
    id: islandStatusObject
    tk: islandTokens
    shell: root.shell
    sys: islandSystem
    suppressed: root.islandExpanded
  }

  // Pitch-black backdrop -> beige island. island-backdrop.sh reports how bright
  // the desktop right behind the island is (the Shan Shui paper when that
  // painting is on, else the static wallpaper's top band, cached per file).
  Process {
    id: backdropProc
    command: [Qt.resolvedUrl("island-backdrop.sh").toString().replace("file://", "")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var b = JSON.parse(String(text || "").trim())
          // Hysteresis so a wallpaper right at the edge does not flicker.
          var lum = Number(b.lum)
          if (islandTokensObject.light) islandTokensObject.light = lum < 0.08
          else islandTokensObject.light = lum < 0.05
        } catch (e) {}
      }
    }
  }
  Timer {
    interval: 3000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: if (!backdropProc.running) backdropProc.running = true
  }

  property bool islandExpanded: false
  // The open island's page (IslandTray): 0 overview + now playing, 1 Claude/system/toggles.
  property int islandPage: 0
  function setIslandPage(p) {
    var n = 2
    islandPage = ((p % n) + n) % n
  }
  // "" while the card row is showing; otherwise the card whose detail has
  // taken over the surface. Escape steps back one level at a time:
  // detail -> cards -> closed.
  property string islandDetail: ""

  // The island stays open until it is dismissed — by clicking away, by
  // Escape, or by the toggle. Nothing times out from under the user.
  function toggleIsland() {
    if (islandExpanded) closeIsland()
    else {
      islandExpanded = true
      islandStatus.dismiss()
    }
  }

  function closeIsland() {
    islandExpanded = false
  }

  // The height the open surface takes for the detail currently showing. Each
  // panel is sized to its own content instead of to the tallest one, so a
  // battery readout no longer opens a box two-thirds empty.
  readonly property int islandDetailHeight: islandTokens.detailHeightFor(islandDetail)

  // True while the Wi-Fi password field is up. The bar's layer surface takes
  // the keyboard exactly while this holds — see the BarPanel below.
  property bool islandKeyboard: false
  // Mirrors of the password field's focus and length, for `probe`.
  property bool islandDetailFieldFocused: false
  property int islandDetailFieldLength: 0

  function openIslandDetail(kind) {
    islandDetail = String(kind || "")
    // The extra work a detail view needs stays idle until one asks for it:
    // the Wi-Fi scanner, Bluetooth discovery and the faster usage refresh are
    // all switched on here and off again on the way out.
    islandSystem.netDetailWanted = (islandDetail === "network")
    islandSystem.btDetailWanted = (islandDetail === "bluetooth")
    islandSystem.claudeDetailWanted = (islandDetail === "claude")
  }

  // One step back, for Escape and for the detail view's own affordance. The
  // password prompt is a level of its own: Escape cancels it and leaves the
  // network list up, rather than closing the panel out from under a half-typed
  // password.
  function islandBack() {
    if (islandDetail === "network" && islandSystem.promptActive) {
      islandSystem.cancelPrompt()
      return
    }
    if (islandDetail !== "") openIslandDetail("")
    else closeIsland()
  }

  onIslandExpandedChanged: {
    // Every open starts on the overview.
    if (!islandExpanded) islandPage = 0
    // Escape comes from a Hyprland submap rather than from a keyboard grab on
    // the island's own surface: an exclusive-focus layer surface ignores its
    // input mask, which made the scrim swallow every click meant for a card.
    // A submap leaves unbound keys going to the focused window, so typing is
    // unaffected while the island is open.
    // This Hyprland routes `hyprctl dispatch` through Lua, so the dispatcher
    // has to be spelled as a Lua call rather than as bare arguments.
    Quickshell.execDetached(["hyprctl", "dispatch",
      "hl.dsp.submap(\"" + (islandExpanded ? "island" : "reset") + "\")"])
    if (!islandExpanded) openIslandDetail("")
  }

  // Leaving the Wi-Fi panel with a prompt still up would strand the keyboard
  // grab on the bar, so the prompt is dropped whenever the panel changes.
  onIslandDetailChanged: if (islandDetail !== "network") islandSystem.cancelPrompt()

  function setCenterHoverRevealSuppressed(value) {
    centerHoverRevealSuppressed = !!value
  }

  Timer {
    id: centerSectionRevealTimer
    interval: 120
    // Collapse only. Opening the peek is the center section's own gesture, done
    // in setCenterSectionHovered, so a timer left pending by a pointer that dipped
    // off the bar and came back cannot reveal indicators it never pointed at.
    onTriggered: if (!root.centerSectionHovered && !root.barHovered) root.centerSectionRevealHeld = false
  }

  function run(command) {
    if (!command) return

    Util.execDetached(command)
  }

  function toggleTransparency() {
    var nextTransparent = !(root.requestedTransparent === true)
    if (root.shell && typeof root.shell.mutateShellConfig === "function") {
      root.shell.mutateShellConfig(function(config) {
        if (!Util.isPlainObject(config.bar)) config.bar = {}
        config.bar.transparent = nextTransparent
      })
    } else {
      root.setRequestedTransparency(nextTransparent)
    }
  }

  function rawLayoutSection(config, region) {
    if (!Util.isPlainObject(config.bar)) config.bar = {}
    if (!Util.isPlainObject(config.bar.layout)) config.bar.layout = {}
    if (!Array.isArray(config.bar.layout[region])) config.bar.layout[region] = []

    return config.bar.layout[region]
  }

  function rawEntryIndex(entries, name) {
    for (var i = 0; i < entries.length; i++) {
      if (root.entryId(entries[i]) === name) return i
    }

    return -1
  }

  function moveModuleInConfig(config, fromRegion, fromName, toRegion, beforeName) {
    var fromEntries = rawLayoutSection(config, fromRegion)
    var toEntries = rawLayoutSection(config, toRegion)
    var fromIndex = rawEntryIndex(fromEntries, fromName)
    if (fromIndex < 0) return false

    var toIndex = beforeName ? rawEntryIndex(toEntries, beforeName) : toEntries.length
    if (toIndex < 0) toIndex = toEntries.length

    if (fromRegion === toRegion && fromIndex === toIndex) return false

    var movedEntry = fromEntries[fromIndex]
    fromEntries.splice(fromIndex, 1)

    if (fromRegion === toRegion && fromIndex < toIndex) toIndex -= 1
    if (toIndex < 0) toIndex = 0
    if (toIndex > toEntries.length) toIndex = toEntries.length
    if (fromRegion === toRegion && fromIndex === toIndex) {
      fromEntries.splice(fromIndex, 0, movedEntry)
      return false
    }

    toEntries.splice(toIndex, 0, movedEntry)
    return true
  }

  function dropBarModule(source, toRegion, beforeName) {
    if (!source || !source.region || !source.moduleName || !toRegion) return false
    if (source.region === toRegion && source.moduleName === beforeName) return false
    if (!root.shell || typeof root.shell.mutateShellConfig !== "function") return false

    var changed = false
    root.shell.mutateShellConfig(function(config) {
      changed = moveModuleInConfig(config, source.region, source.moduleName, toRegion, beforeName)
    })
    return changed
  }

  function moduleDropAtScene(scenePoint, sourceSlot) {
    var sourceWindow = root.slotWindow(sourceSlot) || root.barDragWindow
    if (sourceWindow && sourceWindow.contentItem) {
      var barPoint = sourceWindow.contentItem.mapFromItem(null, scenePoint.x, scenePoint.y)
      if (barPoint.x < 0 || barPoint.x > sourceWindow.contentItem.width ||
          barPoint.y < 0 || barPoint.y > sourceWindow.contentItem.height)
        return null
    }

    var candidates = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || slot === sourceSlot || !slot.visible || slot.width <= 0 || slot.height <= 0) continue
      if (sourceWindow && !root.sameWindow(root.slotWindow(slot), sourceWindow)) continue

      var slotPoint = { x: slot.x, y: slot.y }
      try {
        slotPoint = slot.mapToItem(null, 0, 0)
      } catch (e) {
      }

      candidates.push({
        slot: slot,
        x: slotPoint.x,
        y: slotPoint.y,
        width: slot.width,
        height: slot.height
      })
    }

    return BarModel.nearestDropTarget(candidates, scenePoint, root.vertical)
  }

  function visibleModuleSlot(region, name, sourceSlot) {
    var sourceWindow = root.slotWindow(sourceSlot) || root.barDragWindow
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || slot === sourceSlot || slot.region !== region || slot.moduleName !== name ||
          !slot.visible || slot.width <= 0 || slot.height <= 0) continue
      if (sourceWindow && !root.sameWindow(root.slotWindow(slot), sourceWindow)) continue
      return slot
    }

    return null
  }

  function nextVisibleModuleName(region, afterName, sourceSlot) {
    var entries = layoutEntries(region)
    var found = false
    for (var i = 0; i < entries.length; i++) {
      var name = entryId(entries[i])
      if (!found) {
        found = name === afterName
        continue
      }

      if (visibleModuleSlot(region, name, sourceSlot)) return name
    }

    return ""
  }

  function dropBarModuleAtTarget(sourceSlot, targetSlot, afterTarget) {
    if (!sourceSlot || !targetSlot) return false

    var beforeName = afterTarget ? nextVisibleModuleName(targetSlot.region, targetSlot.moduleName, sourceSlot) : targetSlot.moduleName
    return dropBarModule(sourceSlot, targetSlot.region, beforeName)
  }

  function moduleTargetClickable(target) {
    return target
      && target.visible !== false
      && target.opacity !== 0
      && target.interactive !== false
      && target.pressable !== false
      && target.concealed !== true
      && typeof target.triggerPress === "function"
  }

  function moduleClickTargetAt(slot, localX, localY) {
    for (var i = clickTargets.length - 1; i >= 0; i--) {
      var target = clickTargets[i]
      if (!moduleTargetClickable(target)) continue

      var targetPoint = { x: localX, y: localY }
      try {
        targetPoint = slot.mapToItem(target, localX, localY)
      } catch (e) {
        continue
      }

      if (targetPoint.x >= 0 && targetPoint.x <= target.width &&
          targetPoint.y >= 0 && targetPoint.y <= target.height) {
        return target
      }
    }

    if (moduleTargetClickable(slot.activeItem)) return slot.activeItem
    return null
  }

  function pressModuleClickTarget(slot, button, localX, localY) {
    var target = moduleClickTargetAt(slot, localX, localY)
    if (!target) return false

    target.triggerPress(button)
    return true
  }

  function colorHex(colorValue) {
    var c = colorValue
    if (typeof c === "string") c = Qt.color(c)
    function hexChannel(value) {
      var s = Math.round(Util.clamp(value, 0, 1) * 255).toString(16)
      return s.length < 2 ? "0" + s : s
    }
    return "#" + hexChannel(c.r) + hexChannel(c.g) + hexChannel(c.b)
  }

  function setRequestedTransparency(value) {
    var nextTransparent = value === true
    requestedTransparent = nextTransparent
    if (!nextTransparent) {
      foregroundAnimationEnabled = false
      useTransparentForeground = false
      transparent = false
      transparentForeground = themeForeground
      restoreForegroundAnimation()
      return
    }
    scheduleTransparentForegroundRefresh()
  }

  function restoreForegroundAnimation() {
    Qt.callLater(function() {
      Qt.callLater(function() { root.foregroundAnimationEnabled = true })
    })
  }

  function scheduleTransparentForegroundRefresh() {
    if (!requestedTransparent) {
      transparentForeground = themeForeground
      return
    }
    transparentForegroundTimer.restart()
  }

  function refreshTransparentForeground() {
    if (!requestedTransparent || transparentForegroundProc.running) return

    transparentForegroundProc.command = [
      "omarchy-bar-text-color",
      root.position,
      String(root.barSize),
      colorHex(root.themeForeground),
      colorHex(root.themeContrastForeground)
    ]
    transparentForegroundProc.running = true
  }

  onRequestedTransparentChanged: scheduleTransparentForegroundRefresh()
  onPositionChanged: scheduleTransparentForegroundRefresh()
  onThemeForegroundChanged: scheduleTransparentForegroundRefresh()
  onThemeContrastForegroundChanged: scheduleTransparentForegroundRefresh()

  Timer {
    id: transparentForegroundTimer
    interval: 120
    repeat: false
    onTriggered: root.refreshTransparentForeground()
  }

  Process {
    id: transparentForegroundProc
    stdout: SplitParser {
      onRead: function(line) {
        var value = String(line || "").trim()
        if (!/^#[0-9A-Fa-f]{6}$/.test(value)) return

        root.foregroundAnimationEnabled = false
        root.transparentForeground = value
        if (root.requestedTransparent) {
          root.useTransparentForeground = true
          root.transparent = true
        }
        root.restoreForegroundAnimation()
      }
    }
  }

  FileView {
    path: root.stateHome + "/omarchy/current"
    watchChanges: true
    printErrors: false
    onFileChanged: root.scheduleTransparentForegroundRefresh()
  }

  function runProcess(process) {
    if (!process.running)
      process.running = true
  }

  function showTooltip(target, text) {
    clearTooltip()

    if (!targetTooltipHovered(target) || !text) {
      tooltipRequest += 1
      return
    }

    var request = tooltipRequest + 1
    tooltipRequest = request
    pendingTooltipTarget = target
    pendingTooltipText = text

    Qt.callLater(function() {
      if (request !== tooltipRequest) return
      if (!targetTooltipHovered(pendingTooltipTarget)) {
        clearTooltip()
        return
      }
      tooltipTarget = pendingTooltipTarget
      tooltipText = pendingTooltipText
      pendingTooltipTarget = null
      pendingTooltipText = ""
      tooltipTimer.restart()
    })
  }

  function hideTooltip(target) {
    if (tooltipTarget !== target && pendingTooltipTarget !== target) return

    tooltipRequest += 1
    clearTooltip()
  }

  Timer {
    id: tooltipTimer
    interval: 400
    onTriggered: {
      if (root.targetTooltipHovered(root.tooltipTarget)) root.tooltipShown = true
      else root.clearTooltip()
    }
  }

  Timer {
    interval: 100
    running: root.tooltipShown
    repeat: true
    onTriggered: if (!root.targetTooltipHovered(root.tooltipTarget)) root.hideTooltip(root.tooltipTarget)
  }

  // Presence of the `bar-off` flag = bar hidden. Watching the parent toggles
  // directory because FileView can't observe a file that doesn't exist yet,
  // and the flag is created/removed by `omarchy-toggle-bar`.
  Process {
    id: barHiddenProbe
    running: true
    command: ["bash", "-c", "[[ -f $HOME/.local/state/omarchy/toggles/bar-off ]] && echo yes || echo no"]
    stdout: SplitParser { onRead: function(line) { root.barHidden = String(line).trim() === "yes" } }
  }
  FileView {
    path: root.home + "/.local/state/omarchy/toggles"
    watchChanges: true
    printErrors: false
    onFileChanged: barHiddenProbe.running = true
  }

  // The directory watch can permanently stop delivering events after flag
  // changes land in quick succession, stranding the bar off screen until the
  // shell restarts. `omarchy-toggle-bar` nudges this after flipping the flag
  // so the probe re-reads it even when the watch has gone quiet.
  IpcHandler {
    target: "omarchy.bar"

    // Start rather than restart: a probe already in flight was launched by the
    // directory watch after the flag flipped, so its answer is current, and
    // killing it here can swallow the result entirely.
    function syncHidden(): void {
      barHiddenProbe.running = true
    }

    // Drive the island from a keybinding or a script:
    //   omarchy-shell ipc call omarchy.bar island toggle
    // Accepts expand | collapse | toggle | dismiss (dismiss clears a banner
    // without touching the expanded state).
    function island(action: string): string {
      var what = String(action || "toggle")
      if (what === "expand") root.islandExpanded = true
      else if (what === "collapse") root.closeIsland()
      else if (what === "dismiss") root.islandStatus.dismiss()
      else if (what === "back") root.islandBack()
      else if (what === "demo:charge") root.islandStatus.demoCharge()
      // Tab / Shift+Tab in the island submap. Only flips pages on the card
      // view; a detail view stays put.
      else if (what === "page:next" || what === "page:prev") {
        if (root.islandExpanded && root.islandDetail === "")
          root.setIslandPage(root.islandPage + (what === "page:next" ? 1 : -1))
      }
      else if (what.indexOf("page:") === 0) {
        root.islandExpanded = true
        root.setIslandPage(Number(what.slice(5)) || 0)
      }
      else if (what === "status") { /* read-only probe */ }
      // "<width> <height>" of the collapsed island: the mouth anshu.menu's
      // genie pours its card out of.
      else if (what === "geometry")
        return Math.round(root.islandMouthWidth) + " " + Math.round(root.islandTokens.collapsedHeight)
      else if (what.indexOf("detail:") === 0) {
        root.islandExpanded = true
        root.openIslandDetail(what.slice(7))
      }
      else root.toggleIsland()
      if (!root.islandExpanded) return "collapsed"
      return root.islandDetail !== "" ? "detail:" + root.islandDetail : "expanded"
    }


    // A read-only dump of what the panels are showing. There is no
    // click-injection tool on this box, so this is how the detail views get
    // verified: open a panel over IPC, then read back the same values the
    // panel is bound to.
    //
    //   omarchy-shell -q omarchy.bar probe network
    function probe(what: string): string {
      var sys = root.islandSystem
      var kind = String(what || "all")
      var out = []

      if (kind === "network" || kind === "all") {
        out.push("net.kind=" + sys.netKind + " value=" + sys.netValue + " detail=" + sys.netDetail)
        out.push("net.wifiEnabled=" + sys.wifiEnabled + " blocked=" + sys.wifiBlocked
          + " scanning=" + (sys.wifiDevice ? sys.wifiDevice.scannerEnabled : "-"))
        out.push("net.ip=" + (sys.netDetail2.ip || "") + " rate=" + (sys.netDetail2.rate || ""))
        out.push("net.busy=" + sys.netBusyName + " error=" + sys.netError + " notice=" + sys.netNotice)
        out.push("net.prompt=" + sys.promptActive + " promptName=" + sys.promptName)
        var L = sys.wifiNetworks
        out.push("net.count=" + L.length)
        for (var i = 0; i < L.length; i++)
          out.push("  " + L[i].name + " | known=" + L[i].known + " conn=" + L[i].connected
            + " sec=" + sys.wifiSecurityLabel(L[i].security)
            + " sig=" + Math.round(L[i].signalStrength * 100) + "%")
      }

      if (kind === "bluetooth" || kind === "all") {
        out.push("bt.enabled=" + sys.btEnabled + " scanning=" + sys.btScanning
          + " owns=" + sys.btOwnsDiscovery + " value=" + sys.btValue)
        out.push("bt.busy=" + sys.btBusyAddress + " verb=" + sys.btBusyVerb)
        out.push("bt.error=" + sys.btError)
        out.push("bt.notice=" + sys.btNotice)
        var P = sys.btDevices
        for (var j = 0; j < P.length; j++)
          out.push("  paired: " + sys.btLabel(P[j]) + " conn=" + P[j].connected
            + " glyph=" + sys.btGlyphFor(P[j]))
        var N = sys.btNearby
        for (var k = 0; k < N.length; k++)
          out.push("  nearby: " + sys.btLabel(N[k]) + " glyph=" + sys.btGlyphFor(N[k]))
      }

      if (kind === "battery" || kind === "all") {
        out.push("bat.value=" + sys.batteryValue + " state=" + sys.batteryState
          + " detail=" + sys.batteryDetail)
        out.push("bat.time=" + sys.batteryTime + " draw=" + sys.batteryRate
          + " health=" + sys.batteryHealth + " cap=" + sys.batteryCapacity
          + " cell=" + sys.batteryModel)
      }

      if (kind === "claude" || kind === "all") {
        out.push("claude.ready=" + sys.claudeReady + " session=" + sys.claudePercent
          + "% weekly=" + sys.claudeWeeklyPercent + "% tier=" + sys.claudeTier)
        out.push("claude.age=" + sys.claudeAge + " sessionReset=" + sys.claudeSessionReset
          + " weeklyReset=" + sys.claudeWeeklyReset)
        out.push("claude.prompts=" + sys.claudeTodayPrompts
          + " tokens=" + sys.compactNumber(sys.claudeTodayTokens))
      }

      if (kind === "geometry" || kind === "all") {
        out.push("prompt.focused=" + root.islandDetailFieldFocused
          + " typed=" + root.islandDetailFieldLength)
        out.push("geom.detail=" + root.islandDetail
          + " height=" + root.islandDetailHeight
          + " width=" + root.islandTokens.expandedWidth
          + " keyboard=" + root.islandKeyboard)
      }

      return out.join("\n")
    }

    // Join a network by name, optionally with a password, so the whole connect
    // path can be exercised without a pointer.
    function wifi(name: string, psk: string): string {
      var sys = root.islandSystem
      var net = sys.networkByName(String(name))
      if (!net) return "no such network: " + name
      if (String(psk || "") !== "") {
        sys.beginPrompt(net, "")
        sys.submitPassword(String(psk))
        return "submitted psk for " + name
      }
      sys.activateNetwork(net)
      return "activated " + name + " prompt=" + sys.promptActive + " busy=" + sys.netBusyName
    }

    // Tap a Bluetooth device row by name.
    function bt(name: string): string {
      var sys = root.islandSystem
      var all = sys.btDevices.concat(sys.btNearby)
      for (var i = 0; i < all.length; i++) {
        if (sys.btLabel(all[i]).toLowerCase().indexOf(String(name).toLowerCase()) >= 0) {
          sys.activateDevice(all[i])
          return "activated " + sys.btLabel(all[i]) + " verb=" + sys.btBusyVerb
        }
      }
      return "no such device: " + name
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      BarPanel {
        required property var modelData

        screen: modelData
      }
    }
  }

  // A masked layer surface cannot see a click that lands outside it, so
  // "click away to close" needs something covering the rest of the screen.
  // This is that: fully transparent, present only while the island is open,
  // with the island's own rectangle subtracted from its input region so
  // clicks on the island still reach the bar. It also holds the keyboard,
  // which is what makes Escape work.
  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: scrim
        required property var modelData

        screen: modelData
        visible: root.islandExpanded && !root.vertical
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "omarchy-island-scrim"
        WlrLayershell.layer: WlrLayer.Top

        anchors { top: true; bottom: true; left: true; right: true }

        readonly property real holeWidth: root.islandTokens.expandedWidth
        readonly property real holeHeight: root.islandDetail !== ""
          ? root.islandDetailHeight : root.islandTokens.expandedHeight

        // Geometry comes from this item, not from the window: a PanelWindow's
        // own `width`/`height` read 0 here, which made the base region empty —
        // and an empty mask is treated as no mask at all, so the scrim
        // swallowed every click meant for the island.
        Item {
          id: scrimBody
          anchors.fill: parent
          focus: true

          Keys.onEscapePressed: root.islandBack()

          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: root.closeIsland()
          }
        }

        readonly property int holeX: Math.round((scrimBody.width - scrim.holeWidth) / 2)

        // Built as the three strips around the island rather than as the
        // screen minus it: a Subtract child of an empty base region is
        // silently dropped, and the base is empty on the frame the surface is
        // created — which left the scrim covering the island and eating every
        // click meant for a card.
        mask: Region {
          x: 0
          y: 0
          width: scrim.holeX
          height: scrimBody.height

          Region {
            intersection: Intersection.Combine
            x: scrim.holeX + scrim.holeWidth
            y: 0
            width: Math.max(0, scrimBody.width - scrim.holeX - scrim.holeWidth)
            height: scrimBody.height
          }

          Region {
            intersection: Intersection.Combine
            x: scrim.holeX
            y: scrim.holeHeight
            width: scrim.holeWidth
            height: Math.max(0, scrimBody.height - scrim.holeHeight)
          }
        }
      }
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      DragGhostPanel {
        required property var modelData

        screen: modelData
        ghostScreen: modelData
      }
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      BarMoveGhostPanel {
        required property var modelData

        screen: modelData
        ghostScreen: modelData
      }
    }
  }

  component BarPanel: PanelWindow {
    id: barWindow

    // Hiding parks the bar just past its screen edge instead of unmapping it.
    // Unmapping frees the layer surface and the whole scene graph, so every
    // reveal has to rebuild them — new surface, re-shaped glyphs, re-uploaded
    // textures — which measures ~150ms against ~20ms to tear down. Parking
    // keeps the surface alive, so showing is only a margin change.
    visible: !remapGuard.remapping
    exclusionMode: root.barHidden ? ExclusionMode.Ignore : ExclusionMode.Normal

    ScreenMoveRemap {
      id: remapGuard
      window: barWindow
    }

    readonly property int parkOffset: root.vertical ? root.barSize : root.islandTokens.windowHeight

    margins {
      top: root.barHidden && root.position === "top" ? -barWindow.parkOffset : 0
      bottom: root.barHidden && root.position === "bottom" ? -barWindow.parkOffset : 0
      left: root.barHidden && root.position === "left" ? -barWindow.parkOffset : 0
      right: root.barHidden && root.position === "right" ? -barWindow.parkOffset : 0
    }

    anchors {
      top: root.position === "top" || root.vertical
      bottom: root.position === "bottom" || root.vertical
      left: root.position === "left" || !root.vertical
      right: root.position === "right" || !root.vertical
    }

    implicitWidth: root.vertical ? root.barSize : 0
    implicitHeight: root.vertical ? 0 : root.islandTokens.windowHeight
    // The island floats; only a vertical bar still paints a panel behind itself.
    color: root.vertical && !root.transparent ? root.background : "transparent"

    // Explicit rather than Auto: the surface is taller than the strip the
    // island actually occupies, and Auto would reserve all of it.
    exclusiveZone: root.barHidden ? 0 : (root.vertical ? root.barSize : root.islandTokens.reservedHeight)

    // Everything outside the glass stays click-through, so the empty width of
    // the surface never swallows a click meant for the desktop or a window.
    readonly property bool hasIslandRect: !root.vertical && barContent.item && barContent.item.hitW !== undefined

    mask: Region {
      x: barWindow.hasIslandRect ? Math.floor(barContent.item.hitX) : 0
      y: barWindow.hasIslandRect ? Math.floor(barContent.item.hitY) : 0
      width: barWindow.hasIslandRect ? Math.ceil(barContent.item.hitW) : barWindow.width
      height: barWindow.hasIslandRect ? Math.ceil(barContent.item.hitH) : barWindow.height
    }
    surfaceFormat.opaque: false
    WlrLayershell.namespace: "omarchy-bar"
    WlrLayershell.layer: WlrLayer.Top

    // Normally None, so the bar never takes the keyboard from the focused
    // window. The Wi-Fi password field is the one thing that needs it, and it
    // needs `Exclusive`: under `OnDemand` Hyprland only hands a layer surface
    // the keyboard when it is clicked, and the field would sit there looking
    // focused while every keystroke went to the window behind it.
    //
    // Exclusive also makes the compositor ignore this surface's input mask, so
    // for as long as the prompt is up the whole width of the bar's strip stops
    // being click-through. That is the reason it is scoped to the prompt rather
    // than left on: it is a deliberate modal moment, and Escape or Cancel ends
    // it. Do not widen this condition without re-checking the mask.
    WlrLayershell.keyboardFocus: root.islandKeyboard && !root.vertical
      ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Loader {
      id: barContent
      anchors.fill: parent
      sourceComponent: root.vertical ? verticalBar : horizontalBar

      // A child of the loader, not a sibling of the sections: an ancestor stays
      // hovered while the pointer is over a widget, where a sibling would lose
      // hover to the section the pointer entered.
      HoverHandler {
        onHoveredChanged: root.setBarHovered(hovered)
        // Unplugging a monitor destroys its bar without a leave event, which
        // would strand this surface's tally and hold the peek open for good.
        Component.onDestruction: if (hovered) root.setBarHovered(false)
      }
    }

    PopupWindow {
      id: tooltipWindow

      visible: root.tooltipShown && root.tooltipTarget !== null && root.tooltipText !== "" && root.targetBelongsToWindow(root.tooltipTarget, barWindow)
      color: "transparent"
      implicitWidth: Math.ceil(tooltipBubble.implicitWidth)
      implicitHeight: Math.ceil(tooltipBubble.implicitHeight)

      anchor {
        id: tooltipAnchor
        window: barWindow
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.width: 1
        rect.height: 1

        onAnchoring: {
          var target = root.tooltipTarget
          if (!root.targetBelongsToWindow(target, barWindow)) return

          var popupWidth = tooltipWindow.implicitWidth
          var popupHeight = tooltipWindow.implicitHeight
          var localX = target.width / 2 - popupWidth / 2
          var localY = target.height + 6

          if (root.position === "bottom") {
            localY = -popupHeight - 6
          } else if (root.position === "left") {
            localX = target.width + 6
            localY = target.height / 2 - popupHeight / 2
          } else if (root.position === "right") {
            localX = -popupWidth - 6
            localY = target.height / 2 - popupHeight / 2
          }

          var point = barWindow.contentItem.mapFromItem(target, localX, localY)
          tooltipAnchor.rect.x = Math.round(point.x)
          tooltipAnchor.rect.y = Math.round(point.y)
        }
      }

      BorderSurface {
        id: tooltipBubble
        implicitWidth: tooltipLabel.implicitWidth + 20
        implicitHeight: tooltipLabel.implicitHeight + 14
        color: Color.tooltip.background
        borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
        radius: Style.cornerRadius

        Text {
          id: tooltipLabel
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: root.tooltipText
          color: Color.tooltip.text
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }
      }
    }

    Component {
      id: horizontalBar

      Item {
        id: islandBar
        anchors.fill: parent

        // The window is masked to this rectangle, so it is both the island's
        // hit target and the only part of the surface that is not
        // click-through. It is published as plain numbers rather than as the
        // item itself: a Region bound to an item does not re-read the item's
        // geometry while that geometry is animating, which left the input
        // region frozen at the collapsed pill and made the open island's
        // cards unclickable.
        readonly property real hitX: surface.x
        readonly property real hitY: surface.y
        readonly property real hitW: surface.width
        readonly property real hitH: surface.height

        readonly property var tk: root.islandTokens
        readonly property bool expanded: root.islandExpanded
        readonly property string detail: root.islandDetail
        readonly property bool detailOpen: expanded && detail !== ""
        // A banner only takes the island over when the user is not holding it
        // open; manual state always wins.
        readonly property bool banner: root.islandStatus.bannerActive && !expanded

        // Panacea: max(content + 2 x 18, 420), rounded to an even number so the
        // centred pill and its corners land on whole pixels; the surface also
        // carries the two 12px concave corners.
        readonly property real pillWidth:
          Math.round(Math.max(tk.pillMinWidth, collapsedContent.implicitWidth + tk.collapsedPadX * 2) / 2) * 2
        readonly property real collapsedWidth: pillWidth + tk.flare * 2
        onCollapsedWidthChanged: { root.islandMouthWidth = collapsedWidth; root.islandPillWidth = pillWidth }
        Component.onCompleted: { root.islandMouthWidth = collapsedWidth; root.islandPillWidth = pillWidth }
        readonly property real bannerWidth:
          Math.min(Math.max(tk.bannerMaxWidth, tk.notificationWidth),
                   Math.max(tk.minWidth, bannerContent.implicitWidth
                     + (bannerContent.isNotification ? tk.notificationPadX : tk.bannerPadX) * 2))

        readonly property real targetWidth: expanded ? tk.expandedWidth
          : (banner ? bannerWidth : collapsedWidth)
        readonly property real targetHeight: detailOpen ? root.islandDetailHeight
          : expanded ? tk.expandedHeight
          : (banner ? bannerContent.preferredHeight : tk.collapsedHeight)

        // The open content is laid out once, at the size it will settle at,
        // and the pane is animated around it. Re-running a six-card layout on
        // every frame of the morph is what made the old version stutter.
        readonly property real contentWidth: tk.expandedWidth - tk.expandedPadX * 2
        readonly property real trayHeight: tk.expandedHeight - tk.expandedPadTop - tk.expandedPadBottom
        readonly property real detailHeight: root.islandDetailHeight - tk.expandedPadTop - tk.expandedPadBottom

        Item {
          id: surface

          // Centred on the screen at every size, so growth radiates from the
          // middle in both directions rather than anchoring to one edge.
          x: Math.round((islandBar.width - width) / 2)
          y: islandBar.tk.topMargin
          width: islandBar.targetWidth
          height: islandBar.targetHeight
          // Gone at once while it is the menu card (no fade: the card is
          // drawn exactly over it on that frame).
          opacity: root.islandAway ? 0 : 1

          readonly property int duration: islandBar.expanded || islandBar.banner
            ? islandBar.tk.expandDuration : islandBar.tk.collapseDuration

          Behavior on width {
            NumberAnimation {
              duration: surface.duration
              easing.type: Easing.BezierSpline
              easing.bezierCurve: islandBar.tk.springCurve
            }
          }
          Behavior on height {
            NumberAnimation {
              duration: surface.duration
              easing.type: Easing.BezierSpline
              easing.bezierCurve: islandBar.tk.springCurve
            }
          }

          Binding { target: root; property: "islandLiveWidth"; value: surface.width }
          Binding { target: root; property: "islandLiveHeight"; value: surface.height }
          Binding { target: root; property: "islandLiveTopRadius"; value: glass.topRadius }
          Binding { target: root; property: "islandLiveBottomRadius"; value: glass.bottomRadius }
          Binding { target: root; property: "islandSurfaceColor"; value: glass.surfaceColor }

          IslandGlass {
            id: glass
            anchors.fill: parent
            tk: islandBar.tk
            topRadius: islandBar.expanded ? islandBar.tk.expandedTopRadius : islandBar.tk.collapsedTopRadius
            bottomRadius: islandBar.expanded ? islandBar.tk.expandedBottomRadius : islandBar.tk.collapsedBottomRadius
            tint: root.islandStatus.surfaceTint
            tintStrength: root.islandStatus.surfaceTintStrength
            cornersOn: root.islandCornersOn

            Behavior on topRadius {
              NumberAnimation {
                duration: islandBar.tk.radiusDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: islandBar.tk.springCurve
              }
            }
            Behavior on bottomRadius {
              NumberAnimation {
                duration: islandBar.tk.radiusDuration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: islandBar.tk.springCurve
              }
            }
            Behavior on tintStrength {
              NumberAnimation { duration: islandBar.tk.colorDuration }
            }
          }

          // Content is clipped to the pane so the fixed-size open layout is
          // revealed by the pane growing over it, never squeezed by it.
          Item {
            id: contentClip
            anchors.fill: parent
            clip: true

            // ---------------------------------------------------- collapsed
            // Panacea's pill: hidden the instant the island opens (it becomes
            // the page), faded back in over animFast when it closes.
            IslandPill {
              id: collapsedContent
              anchors.verticalCenter: parent.verticalCenter
              x: islandBar.tk.flare + islandBar.tk.collapsedPadX
              width: islandBar.pillWidth - islandBar.tk.collapsedPadX * 2
              height: islandBar.tk.pillH
              tk: islandBar.tk
              sys: root.islandSystem
              status: root.islandStatus
              readonly property bool shown: !islandBar.expanded && !islandBar.banner && !root.islandAway
              visible: opacity > 0
              opacity: shown ? 1 : 0
              Behavior on opacity {
                enabled: collapsedContent.shown && !root.islandSnap
                NumberAnimation { duration: islandBar.tk.contentInDuration; easing.type: Easing.OutCubic }
              }
            }

            // ------------------------------------------------------- banner
            IslandBanner {
              id: bannerContent
              anchors.centerIn: parent
              width: implicitWidth
              height: implicitHeight
              tk: islandBar.tk
              revealed: islandBar.banner
              mode: root.islandStatus.bannerMode
              glyph: root.islandStatus.bannerGlyph
              title: root.islandStatus.bannerTitle
              detail: root.islandStatus.bannerDetail
              tint: root.islandStatus.bannerTint
              progress: root.islandStatus.bannerProgress
              app: root.islandStatus.bannerApp
              image: root.islandStatus.bannerImage
              appIcon: root.islandStatus.bannerAppIcon
              urgency: root.islandStatus.bannerUrgency
              count: root.islandStatus.notificationCount
              onShotAction: function(act) { root.islandStatus.screenshotAction(act) }
              visible: opacity > 0
            }

            // -------------------------------------------------- open: cards
            IslandTray {
              id: trayContent
              x: islandBar.tk.expandedPadX
              y: islandBar.tk.expandedPadTop
              width: islandBar.contentWidth
              height: islandBar.trayHeight
              tk: islandBar.tk
              sys: root.islandSystem
              revealed: islandBar.expanded && !islandBar.detailOpen

              onOpenDetail: function(kind) { root.openIslandDetail(kind) }
              status: root.islandStatus
              page: root.islandPage
              onPageRequested: function(p) { root.setIslandPage(p) }
              onCloseRequested: root.closeIsland()
              onOpenApp: function(kind) {
                root.closeIsland()
                if (kind === "whatsapp")
                  Quickshell.execDetached(["omarchy-shell", "io.github.moizibnyousaf.omawhatsapp", "openApp", "{}"])
              }
              onNudgeVolume: function(steps) {
                root.islandSystem.setVolume(root.islandSystem.volume + steps * 0.05)
              }
            }

            // ------------------------------------------------- open: detail
            // Lives on the same surface as the cards, one layer up. Opening a
            // detail lifts the card row out and drops this in; nothing about
            // the island opens outside the island.
            IslandDetail {
              id: detailContent
              x: islandBar.tk.expandedPadX
              y: islandBar.tk.expandedPadTop
              width: islandBar.contentWidth
              height: islandBar.detailHeight
              tk: islandBar.tk
              sys: root.islandSystem
              kind: islandBar.detail
              revealed: islandBar.detailOpen

              visible: opacity > 0
              opacity: islandBar.detailOpen ? 1 : 0
              transform: Translate { y: detailContent.opacity === 1 ? 0 : islandBar.tk.px(14) }

              Behavior on opacity {
                SequentialAnimation {
                  PauseAnimation { duration: islandBar.detailOpen ? islandBar.tk.contentInDelay : 0 }
                  NumberAnimation {
                    duration: islandBar.detailOpen
                      ? islandBar.tk.contentInDuration : islandBar.tk.contentOutDuration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: islandBar.tk.fadeCurve
                  }
                }
              }

              onBack: root.islandBack()

              // The prompt owns the keyboard only while it is actually on
              // screen and revealed, so a closing animation never leaves the
              // grab behind.
              onKeyboardWantedChanged: root.islandKeyboard = keyboardWanted
              onPromptFieldFocusedChanged: root.islandDetailFieldFocused = promptFieldFocused
              onPromptFieldLengthChanged: root.islandDetailFieldLength = promptFieldLength
            }
          }

          // ---------------------------------------------------- behaviour
          // Below the content, so a card click never also toggles the island.
          MouseArea {
            anchors.fill: parent
            z: -1
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: function(mouse) {
              var onNote = islandBar.banner && root.islandStatus.bannerKind === "notification"
              // A notification behaves like the toast it replaces: click opens
              // it (default action / focus the app), right click dismisses it.
              if (onNote) {
                if (mouse.button === Qt.RightButton) root.islandStatus.dismissNotification()
                else root.islandStatus.invokeNotification()
                return
              }
              if (mouse.button === Qt.RightButton) {
                root.islandStatus.dismiss()
                return
              }
              if (islandBar.banner) root.islandStatus.dismiss()
              if (islandBar.detailOpen) root.islandBack()
              else root.toggleIsland()
            }
          }
        }
      }
    }

    Component {
      id: verticalBar

      Item {
        id: verticalRoot
        anchors.fill: parent

        CenterModules { anchors.fill: parent }

        LeftModules {
          anchors.top: parent.top
          anchors.topMargin: Style.space(8)
          anchors.horizontalCenter: parent.horizontalCenter
        }

        RightModules {
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(8)
          anchors.horizontalCenter: parent.horizontalCenter
        }
      }
    }
  }

  Component { id: emptyModuleComponent; Item { implicitWidth: 0; implicitHeight: 0; visible: false } }

  component DragGhostPanel: PanelWindow {
    id: ghostWindow

    required property var ghostScreen
    readonly property bool screenMatches: root.barDragScreen === ghostScreen ||
      (root.barDragScreen && ghostScreen && root.barDragScreen.name && ghostScreen.name && root.barDragScreen.name === ghostScreen.name)
    readonly property bool active: root.barDragSource && root.barDragScreen && screenMatches
    readonly property var sourceItem: root.barDragSource ? root.barDragSource.activeItem : null
    readonly property int ghostPadding: Style.space(1)
    readonly property int ghostWidth: sourceItem ? Math.max(1, Math.ceil(sourceItem.width)) : 1
    readonly property int ghostHeight: sourceItem ? Math.max(1, Math.ceil(sourceItem.height)) : 1

    visible: active && sourceItem !== null
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-bar-drag-ghost"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // Visual-only drag feedback. Keep the input region empty so the ghost can
    // sit under the cursor without stealing the MouseArea's active pointer grab.
    mask: Region {}

    Item {
      visible: ghostWindow.visible
      x: Math.round(root.barDragScreenX - root.barDragOffsetX - ghostWindow.ghostPadding)
      y: Math.round(root.barDragScreenY - root.barDragOffsetY - ghostWindow.ghostPadding)
      width: ghostWindow.ghostWidth + ghostWindow.ghostPadding * 2
      height: ghostWindow.ghostHeight + ghostWindow.ghostPadding * 2

      BorderSurface {
        anchors.fill: parent
        color: root.transparent ? "transparent" : root.background
        borderSpec: Border.flat(root.barForeground, 1)
        radius: Math.min(Style.cornerRadius, height / 2)
        opacity: root.transparent ? 0.45 : 0.94
      }

      Image {
        anchors.fill: parent
        anchors.margins: ghostWindow.ghostPadding
        source: root.barDragImageUrl
        fillMode: Image.Stretch
        smooth: true
        opacity: 0.84
      }
    }

    Rectangle {
      readonly property var targetRect: root.barDragTargetGeometry

      visible: ghostWindow.active && targetRect !== null
      x: targetRect ? Math.round(targetRect.x) : 0
      y: targetRect ? Math.round(targetRect.y) : 0
      width: targetRect ? targetRect.width : 0
      height: targetRect ? targetRect.height : 0
      color: Color.accent
      radius: Math.min(width, height) / 2
    }
  }

  component BarMoveGhostPanel: PanelWindow {
    id: moveGhostWindow

    required property var ghostScreen
    readonly property bool screenMatches: root.barMoveScreen === ghostScreen ||
      (root.barMoveScreen && ghostScreen && root.barMoveScreen.name && ghostScreen.name && root.barMoveScreen.name === ghostScreen.name)
    visible: root.barMoveActive && screenMatches
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-bar-move-ghost"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // Visual-only preview of the candidate edge. Keep the input region empty
    // so the overlay never steals the gesture area's active pointer grab.
    mask: Region {}

    // One fixed-geometry slab per edge, crossfaded on candidate changes.
    // Resizing a single slab between edges repaints mid-transition and
    // flickers; fading between static ones does not.
    Repeater {
      model: ["top", "bottom", "left", "right"]

      BorderSurface {
        id: edgeSlab

        required property string modelData
        readonly property bool edgeVertical: modelData === "left" || modelData === "right"
        readonly property int edgeSize: edgeVertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal

        x: modelData === "right" ? parent.width - edgeSize : 0
        y: modelData === "bottom" ? parent.height - edgeSize : 0
        width: edgeVertical ? edgeSize : parent.width
        height: edgeVertical ? parent.height : edgeSize
        color: root.transparent ? "transparent" : root.background
        borderSpec: Border.flat(root.barForeground, 1)
        visible: opacity > 0
        opacity: root.barMoveCandidate === modelData ? (root.transparent ? 0.45 : 0.7) : 0

        Behavior on opacity {
          NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
      }
    }
  }

  function findCenterAnchorEntry() {
    var entries = root.layoutEntries("center")
    var idx = root.entryIndex(entries, root.centerAnchor)
    return idx === -1 ? null : entries[idx]
  }

  component LeftModules: ModuleList {
    entries: root.layoutEntries("left")
    region: "left"
  }

  component RightModules: ModuleList {
    entries: root.layoutEntries("right")
    region: "right"
  }

  component CenterModules: Item {
    id: centerRoot

    property real contentWidth: 0
    property real contentLeft: 0

    property var entries: root.layoutEntries("center")
    readonly property bool hasAnchor: root.entryIndex(entries, root.centerAnchor) !== -1
    readonly property var anchorEntry: root.findCenterAnchorEntry()

    Loader {
      anchors.fill: parent
      sourceComponent: root.vertical ? verticalCenterModules : horizontalCenterModules
    }

    Component {
      id: horizontalCenterModules

      Item {
        anchors.fill: parent

        Binding {
          target: centerRoot
          property: "contentWidth"
          value: centerRoot.hasAnchor
            ? centerBefore.width + centerAnchorModule.width + centerAfter.width
            : centerPlain.width
        }

        Binding {
          target: centerRoot
          property: "contentLeft"
          value: centerRoot.hasAnchor
            ? centerAnchorModule.x - centerBefore.width
            : centerPlain.x
        }

        CenterGestureArea { anchors.fill: parent }

        HoverHandler {
          onHoveredChanged: root.setCenterSectionHovered(hovered)
        }

        ModuleList {
          id: centerPlain
          visible: !centerRoot.hasAnchor
          entries: centerRoot.entries
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          id: centerBefore
          visible: centerRoot.hasAnchor
          entries: root.entriesBefore(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.right: centerAnchorModule.left
          anchors.verticalCenter: centerAnchorModule.verticalCenter
        }

        ModuleSlot {
          id: centerAnchorModule
          visible: centerRoot.hasAnchor
          entry: centerRoot.anchorEntry
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          id: centerAfter
          visible: centerRoot.hasAnchor
          entries: root.entriesAfter(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.left: centerAnchorModule.right
          anchors.verticalCenter: centerAnchorModule.verticalCenter
        }
      }
    }

    Component {
      id: verticalCenterModules

      Item {
        anchors.fill: parent

        CenterGestureArea { anchors.fill: parent }

        HoverHandler {
          onHoveredChanged: root.setCenterSectionHovered(hovered)
        }

        ModuleList {
          visible: !centerRoot.hasAnchor
          entries: centerRoot.entries
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesBefore(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.bottom: centerAnchorModule.top
          anchors.horizontalCenter: centerAnchorModule.horizontalCenter
        }

        ModuleSlot {
          id: centerAnchorModule
          visible: centerRoot.hasAnchor
          entry: centerRoot.anchorEntry
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesAfter(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.top: centerAnchorModule.bottom
          anchors.horizontalCenter: centerAnchorModule.horizontalCenter
        }
      }
    }
  }

  component CenterGestureArea: MouseArea {
    id: gestureArea

    property bool dragging: false
    property bool suppressClick: false
    property real pressedX: 0
    property real pressedY: 0
    readonly property real dragThreshold: Style.space(4)

    acceptedButtons: Qt.LeftButton
    cursorShape: dragging ? Qt.ClosedHandCursor : Qt.ArrowCursor
    pressAndHoldInterval: 200

    function startDrag(x, y) {
      if (dragging) return
      dragging = true
      root.beginBarMove(root.targetWindow(gestureArea))
      var scenePoint = gestureArea.mapToItem(null, x, y)
      root.updateBarMove(root.windowScreenPoint(scenePoint, root.barMoveWindow))
    }

    onPressed: function(mouse) {
      dragging = false
      suppressClick = false
      pressedX = mouse.x
      pressedY = mouse.y
    }

    onPressAndHold: function(mouse) {
      // A widget above us propagates its composed press-and-hold down here without
      // ever handing over the grab, so we'd get no release or cancel to end the move.
      if (!gestureArea.pressed) return
      startDrag(mouse.x, mouse.y)
    }

    onPositionChanged: function(mouse) {
      if (!(mouse.buttons & Qt.LeftButton)) return

      if (!dragging) {
        var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
        if (distance < dragThreshold) return
        startDrag(mouse.x, mouse.y)
        return
      }

      var scenePoint = gestureArea.mapToItem(null, mouse.x, mouse.y)
      root.updateBarMove(root.windowScreenPoint(scenePoint, root.barMoveWindow))
    }

    onReleased: function(mouse) {
      if (!dragging) return
      dragging = false
      suppressClick = true
      root.finishBarMove()
      mouse.accepted = true
    }

    onCanceled: {
      dragging = false
      suppressClick = false
      root.clearBarMove()
    }

    onClicked: function(mouse) {
      if (suppressClick) {
        suppressClick = false
        mouse.accepted = true
      }
    }

    onDoubleClicked: function(mouse) {
      if (suppressClick) {
        suppressClick = false
        return
      }
      if (mouse.button === Qt.LeftButton) {
        root.toggleTransparency()
        mouse.accepted = true
      }
    }
  }

  component ModuleList: Loader {
    id: moduleListRoot

    property var entries: []
    property string region: ""

    visible: entries.length > 0
    // A hidden list must not build its modules. The center section declares
    // both an anchored and an unanchored arrangement and shows whichever
    // fits, so leaving the other one loaded mounts every center module
    // twice — two IPC handlers registered for the same target, two clocks
    // ticking, two of every timer and fetch behind them.
    active: visible && entries.length > 0
    sourceComponent: root.vertical ? verticalModuleList : horizontalModuleList
    width: item ? item.implicitWidth : 0
    height: item ? item.implicitHeight : 0

    Component {
      id: horizontalModuleList

      Row {
        spacing: 0

        Repeater {
          model: moduleListRoot.entries

          ModuleSlot {
            required property var modelData
            entry: modelData
            region: moduleListRoot.region
          }
        }
      }
    }

    Component {
      id: verticalModuleList

      Column {
        spacing: 0

        Repeater {
          model: moduleListRoot.entries

          ModuleSlot {
            required property var modelData
            entry: modelData
            region: moduleListRoot.region
          }
        }
      }
    }
  }

  component ModuleSlot: Item {
    id: slot

    required property var entry
    property string region: ""
    readonly property string moduleName: root.entryId(entry)
    readonly property var moduleSettings: root.entrySettings(entry)
    readonly property string customType: root.customModuleType(entry)
    readonly property var registryMetadata: root.barWidgetRegistry.metadataFor(root.canonicalWidgetId(moduleName))
    readonly property bool firstParty: registryMetadata && registryMetadata.firstParty === true
    readonly property string pluginApiId: registered ? root.canonicalWidgetId(moduleName) : "bar-entry:" + moduleName
    // Re-evaluate when the registry mutates (Component reference changes,
    // plugin enabled/disabled, etc.). Reading the `widgets` property creates
    // the binding dependency — the wrapped function call alone wouldn't.
    readonly property var registryComponent: {
      var w = root.barWidgetRegistry.widgets
      if (customType) return null
      var registryName = root.canonicalWidgetId(moduleName)
      return w[registryName] ? w[registryName].component : null
    }
    readonly property bool qmlCustom: customType === "qml"
    readonly property bool commandCustom: customType === "command"
    readonly property bool registered: registryComponent !== null
    readonly property var activeItem: {
      if (registered) return registryLoader.item
      if (qmlCustom) return qmlLoader.item
      return componentLoader.item
    }
    readonly property bool hovered: moduleHover.hovered
    readonly property bool dragSource: root.barDragSource === slot
    readonly property bool panelOpen: root.activePopout === slot.activeItem
    // Modules bigger than the mark they want (a text label in a padded slot,
    // a multi-line stack on a vertical bar) can say how long the open-panel
    // dot should be along the bar, so it tracks what the module paints
    // instead of a fraction of whatever slot it happens to fill.
    readonly property real panelIndicatorExtent: {
      var key = root.vertical ? "openPanelIndicatorHeight" : "openPanelIndicatorWidth"
      var hint = activeItem && key in activeItem ? activeItem[key] : undefined
      if (hint !== undefined && hint !== null && hint > 0) return Math.round(hint)
      return Math.max(Style.space(10), Math.round((root.vertical ? slot.height : slot.width) * 0.55))
    }
    implicitWidth: activeItem && activeItem.visible ? (root.vertical ? root.barSize : activeItem.implicitWidth) : 0
    implicitHeight: activeItem && activeItem.visible ? activeItem.implicitHeight : 0
    width: implicitWidth
    height: implicitHeight
    z: modulePointer.dragging ? 100 : 0

    Component.onCompleted: root.registerModuleSlot(slot)
    Component.onDestruction: {
      if (root.barDragSource === slot) root.clearBarDrag()
      root.unregisterModuleSlot(slot)
    }

    HoverHandler { id: moduleHover }

    BorderSurface {
      visible: slot.dragSource
      anchors.fill: parent
      anchors.margins: Style.space(1)
      color: root.transparent ? "transparent" : root.background
      borderSpec: Border.flat(root.barForeground, 1)
      radius: Math.min(Style.cornerRadius, height / 2)
      opacity: root.transparent ? 0.22 : 0.32
    }

    Loader {
      id: componentLoader
      active: !slot.qmlCustom && !slot.registered
      sourceComponent: slot.commandCustom ? customCommandModuleComponent : emptyModuleComponent
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Loader {
      id: registryLoader
      active: slot.registered
      sourceComponent: slot.registered ? slot.registryComponent : null
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Loader {
      id: qmlLoader
      active: slot.qmlCustom
      source: slot.qmlCustom ? root.customModuleSource(slot.entry) : ""
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Rectangle {
      id: openPanelIndicator

      readonly property int inset: Style.space(2)

      visible: opacity > 0
      opacity: slot.panelOpen && !slot.dragSource ? 0.9 : 0
      color: Color.accent
      radius: Math.min(width, height) / 2
      width: root.vertical ? Style.space(2) : slot.panelIndicatorExtent
      height: root.vertical ? slot.panelIndicatorExtent : Style.space(2)
      // The mark sits on the module's inner edge — the one facing the
      // desktop — so it underlines a top bar, overlines a bottom one, and
      // points inward from a left or right one. It reads as pointing at the
      // panel that opens on that side.
      x: root.vertical
        ? (root.position === "left" ? parent.width - width - inset : inset)
        : Math.round((parent.width - width) / 2)
      y: root.vertical
        ? Math.round((parent.height - height) / 2)
        : (root.position === "top" ? parent.height - height - inset : inset)
      z: 50

      Behavior on opacity {
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
      }
    }

    MouseArea {
      id: modulePointer

      property bool dragging: false
      property bool suppressClick: false
      property real pressedX: 0
      property real pressedY: 0
      readonly property bool canReorder: root.shell && typeof root.shell.mutateShellConfig === "function"
      readonly property real dragThreshold: Style.space(4)

      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      enabled: slot.visible && slot.width > 0 && slot.height > 0
      propagateComposedEvents: true
      cursorShape: root.moduleClickTargetAt(slot, mouseX, mouseY) ? Qt.PointingHandCursor : Qt.ArrowCursor
      // Do not assign drag.target here: ModuleSlot is owned by Row/Column
      // positioners, and mutating slot.x/slot.y can leave stale offsets that
      // make neighboring modules overlap after a small aborted drag.

      onPressed: function(mouse) {
        dragging = false
        suppressClick = false
        pressedX = mouse.x
        pressedY = mouse.y
        root.clearBarDrag()
      }

      onPositionChanged: function(mouse) {
        if (!canReorder || !(mouse.buttons & Qt.LeftButton)) return

        var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
        if (distance >= dragThreshold) {
          if (!dragging) {
            root.barDragWindow = root.targetWindow(slot.activeItem) || root.targetWindow(slot)
            root.barDragScreen = root.barDragWindow ? root.barDragWindow.screen : null
            root.barDragOffsetX = pressedX
            root.barDragOffsetY = pressedY
            root.captureBarDragGhost(slot)
            root.barDragSource = slot
          }
          dragging = true
          root.hideTooltip(slot.activeItem)
        }

        if (dragging) {
          var scenePoint = slot.mapToItem(null, mouse.x, mouse.y)
          var screenPoint = root.barDragScreenPoint(scenePoint)
          root.barDragSceneX = scenePoint.x
          root.barDragSceneY = scenePoint.y
          root.barDragScreenX = screenPoint.x
          root.barDragScreenY = screenPoint.y

          var drop = root.moduleDropAtScene(scenePoint, slot)
          root.barDragTarget = drop ? drop.slot : null
          root.barDragAfter = drop ? drop.after : false
          root.barDragTargetGeometry = drop ? root.dropMarkerRect(drop.slot, drop.after) : null
        }
      }

      onReleased: function(mouse) {
        var wasDragging = dragging
        var targetSlot = root.barDragTarget
        var afterTarget = root.barDragAfter

        if (wasDragging) suppressClick = true

        dragging = false
        root.clearBarDrag()

        if (wasDragging && targetSlot) {
          root.dropBarModuleAtTarget(slot, targetSlot, afterTarget)
          mouse.accepted = true
        } else if (!wasDragging) {
          mouse.accepted = false
        }
      }

      onCanceled: {
        dragging = false
        suppressClick = false
        root.clearBarDrag()
      }

      onClicked: function(mouse) {
        if (suppressClick) {
          suppressClick = false
          mouse.accepted = true
          return
        }

        if (!root.pressModuleClickTarget(slot, mouse.button, mouse.x, mouse.y)) mouse.accepted = false
      }
    }

    onActiveItemChanged: Qt.callLater(injectProps)
    onModuleSettingsChanged: injectProps()

    function injectProps() {
      var target = activeItem
      if (!target) return
      if ("bar" in target) target.bar = firstParty
        ? root : root.pluginBarApiFor(pluginApiId, moduleName, registered)
      if ("moduleName" in target) target.moduleName = moduleName
      if ("settings" in target) target.settings = moduleSettings
    }

    Component {
      id: customCommandModuleComponent
      CustomCommandModule { entry: slot.entry }
    }
  }

  component CustomCommandModule: WidgetButton {
    id: customRoot

    required property var entry
    readonly property string moduleName: root.entryId(entry)
    readonly property var settings: root.entrySettings(entry)
    property string outputText: ""
    property string outputTooltip: ""
    property bool outputActive: false

    function setting(name, fallback) {
      var value = settings ? settings[name] : undefined
      return value === undefined || value === null ? fallback : value
    }

    function update(raw) {
      var data = Util.parseModuleJson(raw)
      var klass = data.class || data.alt || ""

      outputText = data.text || String(raw || "").trim()
      outputTooltip = data.tooltip || String(setting("tooltip", ""))
      outputActive = klass === "active" || (Array.isArray(klass) && klass.indexOf("active") !== -1)
    }

    bar: root
    text: outputText || String(setting("text", ""))
    tooltipText: outputTooltip || String(setting("tooltip", ""))
    active: outputActive
    keepSpace: setting("keepSpace", false) === true
    horizontalMargin: Number(setting("horizontalMargin", 7.5))
    verticalPadding: Number(setting("verticalPadding", 6))
    fontSize: Number(setting("fontSize", 12))

    onPressed: function(button) {
      var command = ""
      if (button === Qt.RightButton)
        command = String(setting("onRightClick", ""))
      else if (button === Qt.MiddleButton)
        command = String(setting("onMiddleClick", ""))
      else
        command = String(setting("onClick", ""))

      if (command) root.run(command)
    }

    Process {
      id: customProc
      command: ["bash", "-lc", String(customRoot.setting("exec", ""))]
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: customRoot.update(text)
      }
    }

    Timer {
      interval: Math.max(1, Number(customRoot.setting("interval", 5))) * 1000
      running: String(customRoot.setting("exec", "")) !== ""
      repeat: true
      triggeredOnStart: true
      onTriggered: root.runProcess(customProc)
    }
  }
}
