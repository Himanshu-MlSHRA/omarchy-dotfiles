import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

// Live system readouts for the island's expanded state.
//
// Every value here comes from a source that actually reports it: Pipewire,
// UPower, BlueZ, NetworkManager, Open-Meteo, and the usage record that
// `omarchy-agent-usage-update` writes for Claude Code. Nothing is estimated,
// and a source that has nothing to say leaves its field empty rather than
// inventing a placeholder.
//
// Reads are event-driven wherever the source offers events (Pipewire, UPower
// and BlueZ push; `nmcli monitor` streams). Only weather is on a timer, and
// it is cached to disk so a shell restart costs no request.
Item {
  id: sys
  visible: false

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy"

  // ------------------------------------------------------------------ audio
  readonly property var sink: Pipewire.defaultAudioSink
  readonly property bool audioReady: !!(sink && sink.audio)
  readonly property real volume: audioReady ? sink.audio.volume : 0
  readonly property bool muted: audioReady ? sink.audio.muted : false
  readonly property int volumePercent: Math.round(volume * 100)
  readonly property string audioDevice: sink ? String(sink.description || sink.nickname || sink.name || "") : ""
  readonly property string audioValue: muted ? "Muted" : volumePercent + "%"
  readonly property string audioGlyph: muted || volumePercent === 0 ? "󰝟"
    : volumePercent < 34 ? "󰕿" : volumePercent < 67 ? "󰖀" : "󰕾"

  PwObjectTracker { objects: sys.sink ? [sys.sink] : [] }

  function setVolume(v) {
    if (!sys.audioReady) return
    sys.sink.audio.volume = Math.max(0, Math.min(1, v))
  }
  function toggleMute() {
    if (sys.audioReady) sys.sink.audio.muted = !sys.sink.audio.muted
  }

  // ---------------------------------------------------------------- battery
  // `UPower.displayDevice` is a synthetic aggregate: it carries a percentage
  // and a change rate but no model, no health and no native path, which is why
  // half the battery detail read "—". The real laptop battery has all of it,
  // so the readouts come from that and fall back to the aggregate only if no
  // physical battery is enumerated yet.
  readonly property var upowerDevices: UPower.devices ? UPower.devices.values : []
  readonly property var realBattery: {
    var ds = upowerDevices
    for (var i = 0; i < ds.length; i++) {
      var d = ds[i]
      if (d && d.isLaptopBattery && d.isPresent) return d
    }
    return null
  }
  readonly property var batteryDevice: realBattery ? realBattery : UPower.displayDevice
  readonly property bool hasBattery: !!(batteryDevice && batteryDevice.isLaptopBattery && batteryDevice.isPresent)
  readonly property int batteryPercent: hasBattery ? Math.round(batteryDevice.percentage * 100) : -1
  readonly property bool charging: hasBattery
    ? batteryDevice.state === UPowerDeviceState.Charging
    : !UPower.onBattery
  readonly property bool batteryFull: hasBattery
    && batteryDevice.state === UPowerDeviceState.FullyCharged
  readonly property bool batteryLow: hasBattery && batteryPercent <= 15 && !charging
  readonly property string batteryValue: hasBattery ? batteryPercent + "%" : "—"
  readonly property string batteryGlyph: {
    if (!hasBattery) return "󰚥"
    if (charging) return "󰂄"
    var steps = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"]
    return steps[Math.max(0, Math.min(9, Math.floor(batteryPercent / 10.5)))]
  }
  // The remaining-time estimate on its own, empty when UPower has none yet.
  readonly property string batteryTime: {
    if (!hasBattery) return ""
    var secs = charging ? batteryDevice.timeToFull : batteryDevice.timeToEmpty
    if (!secs || secs <= 0) return ""
    var h = Math.floor(secs / 3600)
    var m = Math.round((secs % 3600) / 60)
    return h > 0 ? h + "h " + m + "m" : m + "m"
  }

  readonly property string batteryDetail: {
    if (!hasBattery) return "On AC power"
    if (batteryFull) return "Fully charged"
    if (batteryTime === "") return charging ? "Charging" : "On battery"
    return charging ? batteryTime + " to full" : batteryTime + " left"
  }
  readonly property string batteryState: !hasBattery ? "AC power"
    : batteryFull ? "Full"
    : charging ? "Charging"
    : "Discharging"

  // -------------------------------------------------------------- bluetooth
  readonly property var btAdapter: Bluetooth.defaultAdapter
  readonly property bool btAvailable: !!btAdapter
  readonly property bool btEnabled: btAvailable && btAdapter.enabled
  readonly property var btConnected: {
    if (!btEnabled || !btAdapter.devices) return []
    var out = []
    var values = btAdapter.devices.values || []
    for (var i = 0; i < values.length; i++)
      if (values[i] && values[i].connected) out.push(values[i])
    return out
  }
  readonly property string btValue: {
    if (!btAvailable) return "—"
    if (!btEnabled) return "Off"
    if (btConnected.length === 0) return "On"
    if (btConnected.length === 1)
      return String(btConnected[0].deviceName || btConnected[0].name || "1 device")
    return btConnected.length + " devices"
  }
  readonly property string btGlyph: !btEnabled ? "󰂲" : (btConnected.length > 0 ? "󰂱" : "󰂯")
  readonly property string btDetail: !btEnabled ? "Disabled"
    : btConnected.length > 0 ? "Connected" : "No devices"

  function toggleBluetooth() {
    if (!sys.btAvailable) return
    btError = ""
    btNotice = ""
    sys.btAdapter.enabled = !sys.btAdapter.enabled
  }

  // ---- discovery ----------------------------------------------------------
  // A device that has never been paired only exists on the bus while the
  // adapter is discovering, so pairing something new was impossible while
  // nothing ever turned discovery on. It runs while the Bluetooth detail is
  // open and is switched off again on the way out — a scan is expensive and
  // interferes with A2DP audio if left running.
  property bool btDetailWanted: false
  readonly property bool btScanning: btAvailable && btAdapter.discovering

  onBtDetailWantedChanged: {
    applyDiscovery()
    if (!btDetailWanted) { btError = ""; btNotice = "" }
  }
  onBtEnabledChanged: applyDiscovery()

  // Only ever stops a scan this panel started. `anshu.bluetooth` manages the
  // same adapter flag for its own panel, and clearing it on the way out
  // regardless would cut a scan that belongs to something else.
  property bool btOwnsDiscovery: false

  function applyDiscovery() {
    if (!btAvailable) return
    var want = btDetailWanted && btEnabled
    if (want) {
      if (!btAdapter.discovering) { btAdapter.discovering = true; btOwnsDiscovery = true }
      return
    }
    if (btOwnsDiscovery) {
      btOwnsDiscovery = false
      if (btAdapter.discovering) btAdapter.discovering = false
    }
  }

  // BlueZ ends an inquiry on its own after a while, and refuses StartDiscovery
  // outright while the adapter is still powering up, so the same re-assert the
  // Wi-Fi scanner needs applies here.
  Timer {
    interval: 5000
    running: sys.btDetailWanted && sys.btEnabled
    repeat: true
    onTriggered: sys.applyDiscovery()
  }

  // The device an operation is in flight for, plus the last outcome. BlueZ
  // refuses a connection for reasons the user can act on ("the buds are in the
  // case", "the phone already owns them"), so the reason is surfaced verbatim
  // rather than swallowed.
  property string btBusyAddress: ""
  property string btBusyVerb: ""
  property string btError: ""
  property string btNotice: ""

  function btIsBusy(device) {
    return !!device && btBusyAddress === String(device.address || "")
  }

  // Tapping a device row: disconnect what is connected, connect what is
  // paired, pair what is not. Pairing a fresh device also trusts it, which is
  // what lets it reconnect on its own afterwards.
  function activateDevice(device) {
    if (!device) return
    btError = ""
    btNotice = ""
    if (device.connected) { runBluetooth(device, "disconnect"); return }
    if (device.pairing) { device.cancelPair(); return }
    if (device.paired || device.bonded) { runBluetooth(device, "connect"); return }
    runBluetooth(device, "pair")
  }

  function forgetDevice(device) {
    if (!device) return
    btError = ""
    var label = btLabel(device)
    device.forget()
    btNotice = "Removed " + label
  }

  // The device's own icon hint, so a headset does not look like a mouse.
  function btGlyphFor(device) {
    if (!device) return "󰂯"
    var icon = String(device.icon || "")
    var glyph = "󰂯"
    if (/headset|headphone/i.test(icon)) glyph = "󰋋"
    else if (/audio|speaker/i.test(icon)) glyph = "󰓃"
    else if (/mouse/i.test(icon)) glyph = "󰍽"
    else if (/keyboard/i.test(icon)) glyph = "󰌌"
    else if (/phone/i.test(icon)) glyph = "󰄜"
    else if (/computer/i.test(icon)) glyph = "󰟀"
    else if (/watch|wearable/i.test(icon)) glyph = "󰖉"
    else if (/input-gaming/i.test(icon)) glyph = "󰊗"
    else if (/printer/i.test(icon)) glyph = "󰐪"
    // An unpaired device in range reads as available rather than as connected.
    if (glyph === "󰂯" && !device.paired && !device.bonded) return "󰂰"
    return glyph
  }

  function btLabel(device) {
    if (!device) return ""
    var name = String(device.deviceName || device.name || "").trim()
    return name !== "" ? name : String(device.address || "")
  }

  // Driven through `bluetoothctl` rather than the object's own connect(), for
  // one reason: the D-Bus call reports failure by simply not connecting, while
  // bluetoothctl prints the BlueZ error — "br-connection-refused" and friends —
  // which is the only version of this the user can do anything about.
  Process {
    id: btAction
    property string address: ""
    property string verb: ""
    property string output: ""

    stdout: StdioCollector { waitForEnd: true; onStreamFinished: btAction.output += text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: btAction.output += text }

    onExited: function(code) {
      var text = String(btAction.output || "")
      sys.btBusyAddress = ""
      sys.btBusyVerb = ""
      var device = sys.deviceByAddress(btAction.address)
      var label = device ? sys.btLabel(device) : btAction.address

      if (/Failed to |not available|org\.bluez\.Error/i.test(text) || code !== 0) {
        sys.btError = sys.btFailText(text, btAction.verb) + " · " + label
        return
      }
      if (btAction.verb === "pair") {
        // Pairing alone does not make it usable: trust it so it may reconnect
        // by itself, then bring it up.
        if (device) { device.trusted = true; sys.runBluetooth(device, "connect") }
        return
      }
      if (btAction.verb === "connect") sys.btNotice = "Connected to " + label
      else if (btAction.verb === "disconnect") sys.btNotice = "Disconnected " + label
    }
  }

  function runBluetooth(device, verb) {
    if (!device || btAction.running) return
    btAction.address = String(device.address || "")
    btAction.verb = String(verb)
    btAction.output = ""
    btBusyAddress = btAction.address
    btBusyVerb = btAction.verb
    btAction.command = ["bluetoothctl", String(verb), btAction.address]
    btAction.running = true
  }

  // BlueZ error strings, turned into something actionable.
  function btFailText(text, verb) {
    if (/br-connection-refused/i.test(text))
      return "Refused the connection — take it out of the case, or disconnect it from your phone"
    if (/br-connection-page-timeout|Page Timeout/i.test(text))
      return "Did not answer — is it switched on and in range?"
    if (/already connected/i.test(text)) return "Already connected"
    if (/not available/i.test(text)) return "Out of range"
    if (/AuthenticationFailed|Authentication Failed/i.test(text)) return "Authentication failed"
    if (/AuthenticationRejected/i.test(text)) return "The device rejected pairing"
    if (/AuthenticationCanceled/i.test(text)) return "Pairing was cancelled"
    if (/InProgress/i.test(text)) return "Busy — try again in a moment"
    if (/profile unavailable|Protocol not available/i.test(text))
      return "No usable audio profile"
    return verb === "pair" ? "Could not pair" : "Could not " + verb
  }

  function deviceByAddress(address) {
    var all = btAllDevices
    for (var i = 0; i < all.length; i++)
      if (String(all[i].address || "") === String(address)) return all[i]
    return null
  }

  // ------------------------------------------------------------------ wi-fi
  // Live, from Quickshell's NetworkManager binding rather than from parsing
  // `nmcli` output on a timer: the device and every visible network are real
  // objects whose properties push their own changes, so a row in the list
  // updates itself. It is also the only route to `connectWithPsk`, which is
  // what lets the island join a network it has no saved profile for — the
  // thing the old shell-script version could not do at all.
  readonly property var netDevices: Networking.devices ? Networking.devices.values : []

  readonly property var wifiDevice: {
    var ds = netDevices
    for (var i = 0; i < ds.length; i++)
      if (ds[i] && ds[i].type === DeviceType.Wifi) return ds[i]
    return null
  }
  readonly property var wiredDevice: {
    var ds = netDevices
    for (var i = 0; i < ds.length; i++)
      if (ds[i] && ds[i].type === DeviceType.Wired) return ds[i]
    return null
  }

  readonly property bool wifiEnabled: Networking.wifiEnabled
  readonly property bool wifiBlocked: !Networking.wifiHardwareEnabled

  // The network the adapter is actually on, straight from the backend.
  readonly property var activeWifi: {
    var d = wifiDevice
    var nets = d && d.networks ? d.networks.values : []
    for (var i = 0; i < nets.length; i++)
      if (nets[i] && nets[i].connected) return nets[i]
    return null
  }
  readonly property bool wiredUp: !!(wiredDevice && wiredDevice.connected)

  // "" until the backend has enumerated its devices; "Offline" is a fact, not
  // a default, so it is never shown before there is something to say.
  readonly property string netKind: {
    if (Networking.backend === NetworkBackendType.None) return "disconnected"
    if (netDevices.length === 0) return ""
    if (wiredUp) return "ethernet"
    if (activeWifi) return "wifi"
    return "disconnected"
  }
  readonly property string netName: wiredUp ? String(wiredDevice.name || "")
    : (activeWifi ? String(activeWifi.name || "") : "")
  readonly property int netSignal: activeWifi ? Math.round(activeWifi.signalStrength * 100) : -1

  readonly property string netValue: netKind === "" ? "—"
    : netKind === "disconnected" ? (wifiEnabled ? "Offline" : "Wi-Fi off")
    : netName !== "" ? netName : (netKind === "ethernet" ? "Wired" : "Connected")
  readonly property string netGlyph: {
    if (netKind === "") return "󰤩"
    if (netKind === "ethernet") return "󰈀"
    if (!wifiEnabled) return "󰖪"
    if (netKind !== "wifi") return "󰤮"
    return wifiBars(netSignal)
  }
  readonly property string netDetail: netKind === "wifi" && netSignal >= 0
    ? netSignal + "% signal"
    : netKind === "ethernet" ? "Ethernet"
    : netKind === "" ? "Checking"
    : !wifiEnabled ? "Turned off" : "Not connected"

  readonly property string netScript: Quickshell.env("HOME") + "/.config/omarchy/plugins/anshu.bar/island-network.sh"

  // Detail-only fields. Nothing queries them until a detail view asks, which is
  // what `netDetailWanted` is for — an open island should not cost more than a
  // closed one when nobody is looking at the numbers.
  property bool netDetailWanted: false
  property var netDetail2: ({})

  // NetworkManager only keeps rescanning while something asks it to, so the
  // scanner runs exactly while a Wi-Fi list is on screen. Without this the
  // list held only the saved profiles, which is why joining a new network was
  // impossible: the network was never in the list to begin with.
  onNetDetailWantedChanged: {
    applyScanner()
    if (netDetailWanted) { kickRescan(); refreshNetworkDetail() }
    else clearNetworkFeedback()
  }
  onWifiDeviceChanged: applyScanner()

  // Written unconditionally rather than only when it differs: the flag reads
  // back false again once NetworkManager finishes a scan, so a guarded write
  // would skip the re-assert exactly when it is needed.
  function applyScanner() {
    if (wifiDevice) wifiDevice.scannerEnabled = netDetailWanted
  }

  // `scannerEnabled` asks NetworkManager to keep the access-point list fresh on
  // its own cadence, which can be a while. An explicit rescan when the panel
  // opens fills the list now instead of a minute from now — measurably, it is
  // the difference between two networks and every one in range. NetworkManager
  // refuses a rescan that follows too closely behind the last one; that is
  // harmless and the reply is ignored.
  Process { id: wifiRescan; command: ["nmcli", "device", "wifi", "rescan"] }

  function kickRescan() {
    if (!wifiRescan.running) wifiRescan.running = true
  }

  // `scannerEnabled` does not latch: NetworkManager finishes a scan and the
  // flag falls back to false, and once nothing is scanning it prunes the access
  // points it can no longer see — which is what made the list collapse back to
  // just the saved networks a few seconds after the panel opened. Re-asserting
  // it on a slow tick keeps the list populated for as long as someone is
  // looking at it, and costs nothing once the panel closes.
  Timer {
    interval: 5000
    running: sys.netDetailWanted
    repeat: true
    property int ticks: 0
    onTriggered: {
      sys.applyScanner()
      // A forced rescan every third tick: often enough to pick up a network
      // that has just come into range, rare enough not to disturb the link.
      // Held off entirely while a password is being typed — a rescan is what
      // prunes the very access point the prompt is for.
      if (sys.promptActive) return
      ticks += 1
      if (ticks % 3 === 0) sys.kickRescan()
    }
  }

  // Same story for the IP-level facts, which come from a script rather than
  // from a property: re-read them while the panel is open so a lease change or
  // a reconnect is reflected without closing and reopening it.
  Timer {
    interval: 10000
    running: sys.netDetailWanted
    repeat: true
    onTriggered: sys.refreshNetworkDetail()
  }

  // Re-read the IP-level facts whenever the connection itself changes; those
  // are the only numbers the backend does not expose as properties.
  onActiveWifiChanged: {
    if (activeWifi && netBusyName === String(activeWifi.name || "")) {
      netBusyName = ""
      netError = ""
    }
    if (netDetailWanted) refreshNetworkDetail()
  }
  onWiredUpChanged: if (netDetailWanted) refreshNetworkDetail()

  function refreshNetwork() { if (netDetailWanted) refreshNetworkDetail() }

  function refreshNetworkDetail() {
    if (!netDetailQuery.running) netDetailQuery.running = true
  }

  Process {
    id: netDetailQuery
    command: [sys.netScript, "detail"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var out = {}
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var parts = lines[i].split("\t")
          if (parts.length >= 2 && parts[0] !== "") out[parts[0]] = parts[1]
        }
        sys.netDetail2 = out
      }
    }
  }

  // Every visible network, strongest first within its group. The elements are
  // the backend's own objects, so a row binds straight to the live property
  // instead of to a copy that goes stale.
  readonly property var wifiNetworks: {
    var d = wifiDevice
    var nets = d && d.networks ? d.networks.values : []
    var out = []
    for (var i = 0; i < nets.length; i++) {
      var n = nets[i]
      if (!n || String(n.name || "") === "") continue
      out.push(n)
    }
    // Sorted on keys that do not drift. Signal strength moves every few
    // seconds, and sorting on it would rebuild the list's delegates — losing
    // the row under the pointer — while nothing the user cares about changed.
    out.sort(function(a, b) {
      var c = (a.connected ? 0 : 1) - (b.connected ? 0 : 1)
      if (c !== 0) return c
      var k = (a.known ? 0 : 1) - (b.known ? 0 : 1)
      if (k !== 0) return k
      return String(a.name || "").toLowerCase() < String(b.name || "").toLowerCase() ? -1 : 1
    })
    return out
  }

  function wifiBars(strength) {
    if (strength < 0) return "󰤫"
    var bars = ["󰤯", "󰤟", "󰤢", "󰤥", "󰤨"]
    return bars[Math.max(0, Math.min(4, Math.ceil(strength / 20) - 1))]
  }
  function wifiBarsFor(net) {
    return net ? wifiBars(Math.round(net.signalStrength * 100)) : "󰤫"
  }

  function wifiIsOpen(sec) {
    return sec === WifiSecurityType.Open || sec === WifiSecurityType.Owe
  }
  // 802.1X needs a certificate or an identity the island cannot collect with
  // one password box, so those are handed off rather than half-attempted.
  function wifiIsEnterprise(sec) {
    return sec === WifiSecurityType.Wpa2Eap || sec === WifiSecurityType.WpaEap
      || sec === WifiSecurityType.DynamicWep || sec === WifiSecurityType.Leap
      || sec === WifiSecurityType.Wpa3SuiteB192
  }
  function wifiSecurityLabel(sec) {
    if (sec === WifiSecurityType.Open) return "Open"
    if (sec === WifiSecurityType.Owe) return "Enhanced Open"
    if (sec === WifiSecurityType.Sae) return "WPA3"
    if (sec === WifiSecurityType.Wpa2Psk) return "WPA2"
    if (sec === WifiSecurityType.WpaPsk) return "WPA"
    if (sec === WifiSecurityType.StaticWep) return "WEP"
    if (sec === WifiSecurityType.Wpa2Eap || sec === WifiSecurityType.WpaEap) return "802.1X"
    if (sec === WifiSecurityType.DynamicWep || sec === WifiSecurityType.Leap) return "802.1X"
    if (sec === WifiSecurityType.Wpa3SuiteB192) return "WPA3 Enterprise"
    return ""
  }

  // ---- connect / disconnect ------------------------------------------------
  // The name of the network a connection attempt is in flight for, the last
  // failure, and the network whose password is being asked for. All three are
  // what the detail view reads to tell the user what is happening; the old
  // version reported nothing at all, which is why a failed join looked like a
  // dead button.
  property string netBusyName: ""
  property string netError: ""
  property string netNotice: ""
  // The prompt is keyed on the network's *name*, not on a reference to the
  // object. NetworkManager destroys a Network as soon as the access point drops
  // out of a scan, and a weak neighbouring network does that routinely — which
  // closed the prompt and dropped the keyboard grab in the middle of a
  // half-typed password. The name survives that; the object is re-resolved when
  // there is actually something to do with it.
  property bool promptOpen: false
  property string promptName: ""
  readonly property bool promptActive: promptOpen && promptName !== ""

  // Failure arrives as a signal on the network object. Hooked once per name on
  // first use rather than for every network up front: connecting a handler to
  // all of them would fire for background activity nobody asked about.
  property var netHooked: ({})

  function hookFailure(net) {
    var key = String(net.name || "")
    if (key === "" || netHooked[key]) return
    netHooked[key] = true
    net.connectionFailed.connect(function(reason) { sys.onNetworkFailed(key, reason) })
  }

  function networkByName(name) {
    var list = wifiNetworks
    for (var i = 0; i < list.length; i++)
      if (String(list[i].name || "") === String(name)) return list[i]
    return null
  }

  function netFailText(reason) {
    if (reason === ConnectionFailReason.NoSecrets) return "Wrong password"
    if (reason === ConnectionFailReason.WifiAuthTimeout) return "Authentication timed out"
    if (reason === ConnectionFailReason.WifiNetworkLost) return "Network out of range"
    if (reason === ConnectionFailReason.WifiClientFailed) return "Adapter refused the connection"
    if (reason === ConnectionFailReason.WifiClientDisconnected) return "Dropped during handshake"
    return "Could not connect"
  }

  function onNetworkFailed(name, reason) {
    if (netBusyName === name) netBusyName = ""
    // A saved profile with a stale key fails with NoSecrets too, so the
    // password box is the right answer whether or not the network is "known".
    if (reason === ConnectionFailReason.NoSecrets) {
      var net = networkByName(name)
      if (net) { beginPrompt(net, "Wrong password — try again"); return }
    }
    netError = netFailText(reason) + " · " + name
  }

  function clearNetworkFeedback() {
    netError = ""
    netNotice = ""
    cancelPrompt()
  }

  // Tapping a row. A connected network is left alone — disconnecting is its own
  // affordance, so a mis-tap cannot drop the connection.
  function activateNetwork(net) {
    if (!net || net.connected) return
    netError = ""
    netNotice = ""
    cancelPrompt()
    if (wifiIsEnterprise(net.security)) {
      netError = "802.1X — add it with nmtui first"
      return
    }
    if (net.known || wifiIsOpen(net.security)) {
      hookFailure(net)
      netBusyName = String(net.name || "")
      net.connect()
      return
    }
    beginPrompt(net, "")
  }

  function beginPrompt(net, message) {
    promptName = String(net.name || "")
    promptOpen = promptName !== ""
    netError = String(message || "")
    netBusyName = ""
  }

  function cancelPrompt() {
    promptOpen = false
    promptName = ""
  }

  function submitPassword(psk) {
    if (!promptActive) return
    var key = String(psk || "")
    if (key.length === 0) return
    // Resolved now rather than held since the prompt opened: the access point
    // may have come and gone from the scan in between.
    var net = networkByName(promptName)
    if (!net) {
      netError = promptName + " is no longer in range"
      return
    }
    // WPA-PSK keys are 8..63 characters; rejecting a short one here is a
    // clearer answer than NetworkManager's silent refusal.
    if (net.security !== WifiSecurityType.StaticWep && key.length < 8) {
      netError = "Password must be at least 8 characters"
      return
    }
    hookFailure(net)
    netBusyName = promptName
    netError = ""
    cancelPrompt()
    net.connectWithPsk(key)
  }

  function disconnectNetwork(net) {
    if (!net) return
    netError = ""
    netNotice = ""
    net.disconnect()
  }

  function forgetNetwork(net) {
    if (!net) return
    var name = String(net.name || "")
    netError = ""
    net.forget()
    netNotice = "Forgot " + name
  }

  function toggleWifi() {
    netError = ""
    cancelPrompt()
    Networking.wifiEnabled = !Networking.wifiEnabled
  }

  // ------------------------------------------------- detail: audio outputs
  // Track every node, not the filtered list: a tracker bound to a list that is
  // itself computed from the nodes' bound properties is a binding loop, and QML
  // resolves it by freezing the list at whatever subset happened to be bound
  // first — which is why the speaker and the headset went missing.
  readonly property var allNodes: Pipewire.nodes ? Pipewire.nodes.values : []

  PwObjectTracker { objects: sys.allNodes }

  readonly property var sinks: {
    var out = []
    for (var i = 0; i < allNodes.length; i++) {
      var n = allNodes[i]
      if (!n || n.isStream || !n.isSink) continue
      out.push(n)
    }
    // The default sink belongs in the list even if enumeration has not caught
    // up with it yet — it is the one the user is definitely listening to.
    if (sink && out.indexOf(sink) < 0) out.unshift(sink)
    return out
  }

  function selectSink(node) {
    if (node) Pipewire.preferredDefaultAudioSink = node
  }

  function sinkLabel(node) {
    if (!node) return ""
    var label = String(node.description || node.nickname || node.name || "")
    return label.replace(/^sof-soundwire\s+/i, "").replace(/\s+Output$/i, "")
  }

  // ---------------------------------------------- detail: bluetooth devices
  readonly property var btAllDevices: {
    if (!btEnabled || !btAdapter || !btAdapter.devices) return []
    var out = []
    var values = btAdapter.devices.values || []
    for (var i = 0; i < values.length; i++) if (values[i]) out.push(values[i])
    return out
  }

  // Everything already paired: connected first, then alphabetical. Sorted on
  // nothing that drifts, so rows are not rebuilt under the pointer.
  readonly property var btDevices: {
    var all = btAllDevices
    var out = []
    for (var i = 0; i < all.length; i++) {
      var d = all[i]
      var label = String(d.deviceName || d.name || "").trim()
      // A bare address is noise in a list meant to be read.
      if (label === "" || /^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(label)) continue
      if (!d.paired && !d.bonded && !d.connected) continue
      out.push(d)
    }
    out.sort(function(a, b) {
      var c = (b.connected ? 1 : 0) - (a.connected ? 1 : 0)
      if (c !== 0) return c
      return String(a.deviceName || a.name || "").toLowerCase()
           < String(b.deviceName || b.name || "").toLowerCase() ? -1 : 1
    })
    return out
  }

  // In range but never paired — only ever populated while discovery is on.
  readonly property var btNearby: {
    var all = btAllDevices
    var out = []
    for (var i = 0; i < all.length; i++) {
      var d = all[i]
      if (d.paired || d.bonded || d.connected) continue
      var label = String(d.deviceName || d.name || "").trim()
      if (label === "" || /^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(label)) continue
      out.push(d)
    }
    out.sort(function(a, b) {
      return String(a.deviceName || a.name || "").toLowerCase()
           < String(b.deviceName || b.name || "").toLowerCase() ? -1 : 1
    })
    return out
  }

  // Kept for callers that predate the rename.
  function toggleDevice(device) { activateDevice(device) }

  // ------------------------------------------------- detail: battery extras
  readonly property int batteryHealth: hasBattery && batteryDevice.healthSupported
    ? Math.round(batteryDevice.healthPercentage) : -1
  readonly property string batteryRate: {
    if (!hasBattery) return ""
    var w = Math.abs(batteryDevice.changeRate || 0)
    // A full battery on AC genuinely draws nothing; that is "—" only because
    // there is no number, so say the state instead.
    if (w < 0.05) return batteryFull ? "Idle" : ""
    return w.toFixed(1) + " W"
  }
  readonly property string batteryModel: hasBattery ? String(batteryDevice.model || "") : ""
  // Capacity in watt-hours, which is the honest way to show wear next to health.
  readonly property string batteryCapacity: {
    if (!hasBattery || !batteryDevice.energyCapacity) return ""
    return batteryDevice.energyCapacity.toFixed(1) + " Wh"
  }

  // -------------------------------------------------- detail: claude extras
  readonly property int claudeTodayPrompts: claudeReady ? Number(claude.todayPrompts || 0) : 0
  readonly property int claudeTodaySessions: claudeReady ? Number(claude.todaySessions || 0) : 0
  readonly property real claudeTodayTokens: claudeReady ? Number(claude.todayTotalTokens || 0) : 0
  readonly property var claudeRecentDays: claudeReady && claude.recentDays ? claude.recentDays : []
  readonly property real claudePeakDay: {
    var peak = 0
    for (var i = 0; i < claudeRecentDays.length; i++)
      peak = Math.max(peak, Number(claudeRecentDays[i].messageCount || 0))
    return peak
  }

  function compactNumber(value) {
    var v = Number(value) || 0
    if (v >= 1e9) return (v / 1e9).toFixed(1) + "B"
    if (v >= 1e6) return (v / 1e6).toFixed(1) + "M"
    if (v >= 1e3) return (v / 1e3).toFixed(1) + "K"
    return String(Math.round(v))
  }

  // No `nmcli monitor` and no signal poll any more: every value above is a
  // bound property on a backend object, so the readouts and the list follow
  // the adapter without anything here asking them to.

  // ---------------------------------------------------------------- weather
  // Open-Meteo only: no key, one request per refresh, and the response is
  // cached to disk so a shell restart repaints instantly from the last value.
  readonly property string weatherCachePath: stateDir + "/island-weather.json"
  property var weather: null
  readonly property bool hasWeather: !!weather
  readonly property string weatherValue: hasWeather ? Math.round(weather.temp) + "°" : "—"
  readonly property string weatherDetail: hasWeather
    ? weather.condition + "  ·  " + Math.round(weather.low) + "° / " + Math.round(weather.high) + "°"
    : "Unavailable"
  readonly property string weatherPlace: hasWeather ? String(weather.place || "") : ""
  readonly property string weatherGlyph: hasWeather ? weatherGlyphFor(weather.code, weather.day) : "󰼯"

  // WMO weather codes → nerd-font glyphs, day/night aware.
  function weatherGlyphFor(code, isDay) {
    var c = Number(code)
    if (c === 0) return isDay ? "󰖙" : "󰖔"
    if (c === 1 || c === 2) return isDay ? "󰖕" : "󰼱"
    if (c === 3) return "󰖐"
    if (c === 45 || c === 48) return "󰖑"
    if (c >= 51 && c <= 57) return "󰖗"
    if (c >= 61 && c <= 67) return "󰖖"
    if (c >= 71 && c <= 77) return "󰼶"
    if (c >= 80 && c <= 82) return "󰖖"
    if (c >= 85 && c <= 86) return "󰼶"
    if (c >= 95) return "󰖓"
    return "󰖐"
  }

  function weatherLabelFor(code) {
    var c = Number(code)
    if (c === 0) return "Clear"
    if (c === 1) return "Mostly clear"
    if (c === 2) return "Partly cloudy"
    if (c === 3) return "Overcast"
    if (c === 45 || c === 48) return "Fog"
    if (c >= 51 && c <= 57) return "Drizzle"
    if (c >= 61 && c <= 67) return "Rain"
    if (c >= 71 && c <= 77) return "Snow"
    if (c >= 80 && c <= 82) return "Showers"
    if (c >= 85 && c <= 86) return "Snow showers"
    if (c >= 95) return "Thunderstorm"
    return "—"
  }

  // Location is owned by `omarchy-weather-location`; an empty or missing file
  // means auto-detect, which Open-Meteo cannot do, so fall back to the IP
  // lookup the file's own tooling uses.
  FileView {
    id: weatherLocation
    path: sys.stateDir + "/settings/weather.json"
    watchChanges: true
    printErrors: false
    onLoaded: sys.applyLocation(text())
    onFileChanged: reload()
  }

  property real lat: NaN
  property real lon: NaN
  property string place: ""

  function applyLocation(raw) {
    try {
      var d = JSON.parse(String(raw || "{}")) || {}
      var la = parseFloat(d.latitude), lo = parseFloat(d.longitude)
      place = typeof d.name === "string" ? d.name.trim() : ""
      if (!isNaN(la) && !isNaN(lo)) { lat = la; lon = lo; fetchWeather(); return }
    } catch (e) { /* unreadable file means auto-detect */ }
    geoLookup.running = true
  }

  Process {
    id: geoLookup
    command: ["curl", "-fsS", "--max-time", "8", "https://ipapi.co/json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(String(text || "{}"))
          if (d.latitude !== undefined && d.longitude !== undefined) {
            sys.lat = parseFloat(d.latitude)
            sys.lon = parseFloat(d.longitude)
            if (sys.place === "") sys.place = String(d.city || "")
            sys.fetchWeather()
          }
        } catch (e) { /* leave weather unavailable rather than guess */ }
      }
    }
  }

  function fetchWeather() {
    if (isNaN(lat) || isNaN(lon) || weatherFetch.running) return
    weatherFetch.command = ["curl", "-fsS", "--max-time", "10",
      "https://api.open-meteo.com/v1/forecast?latitude=" + lat + "&longitude=" + lon +
      "&current=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min" +
      "&timezone=auto&forecast_days=1"]
    weatherFetch.running = true
  }

  Process {
    id: weatherFetch
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: sys.applyWeather(text)
    }
  }

  function applyWeather(raw) {
    try {
      var d = JSON.parse(String(raw || "{}"))
      if (!d.current || !d.daily) return
      var next = {
        temp: d.current.temperature_2m,
        code: d.current.weather_code,
        day: d.current.is_day === 1,
        high: d.daily.temperature_2m_max[0],
        low: d.daily.temperature_2m_min[0],
        place: place,
        condition: weatherLabelFor(d.current.weather_code),
        at: Date.now()
      }
      weather = next
      weatherCache.setText(JSON.stringify(next))
    } catch (e) { /* keep the previous reading rather than blanking it */ }
  }

  FileView {
    id: weatherCache
    path: sys.weatherCachePath
    printErrors: false
    onLoaded: {
      if (sys.weather) return   // a live fetch already won
      try {
        var d = JSON.parse(text())
        if (d && d.temp !== undefined) sys.weather = d
      } catch (e) { /* stale cache, ignore */ }
    }
  }

  Timer {
    interval: 20 * 60 * 1000
    running: true
    repeat: true
    onTriggered: sys.fetchWeather()
  }

  // ----------------------------------------------------------- claude code
  // Strictly a reader of the record `omarchy-agent-usage-update` maintains.
  // No limits in the record means the CLI is not signed in; the tile says so
  // instead of showing a number it cannot substantiate.
  property var claude: null
  readonly property bool claudeReady: !!(claude && claude.ready)
  readonly property var claudeLimits: claudeReady && claude.limits ? claude.limits : []
  readonly property var claudeSession: claudeLimits.length > 0 ? claudeLimits[0] : null
  readonly property var claudeWeekly:  claudeLimits.length > 1 ? claudeLimits[1] : null
  readonly property bool claudeHasLimits: !!claudeSession && claudeSession.percent !== undefined
  readonly property int claudePercent: claudeHasLimits ? Math.round(claudeSession.percent * 100) : -1
  readonly property bool claudeHasWeekly: !!claudeWeekly && claudeWeekly.percent !== undefined
  readonly property int claudeWeeklyPercent: claudeHasWeekly ? Math.round(claudeWeekly.percent * 100) : -1
  readonly property string claudeWeeklyLabel: claudeHasWeekly ? String(claudeWeekly.label || "Weekly") : "Weekly"
  readonly property string claudeWeeklyReset: claudeHasWeekly && claudeWeekly.resetsAt ? resetSpan(claudeWeekly.resetsAt) : ""
  readonly property string claudeSessionLabel: claudeSession ? String(claudeSession.label || "Session") : "Session"
  readonly property string claudeSessionReset: claudeSession && claudeSession.resetsAt ? resetSpan(claudeSession.resetsAt) : ""
  readonly property string claudeTier: claudeReady ? String(claude.tierLabel || "") : ""
  readonly property string claudeValue: claudeHasLimits ? claudePercent + "%"
    : (claudeReady ? "—" : "Off")
  readonly property string claudeDetail: {
    if (!claudeReady) return "No usage recorded"
    if (!claudeHasLimits) return String(claude.authHelpText || "Sign in for limits")
    var label = String(claudeSession.label || "Session")
    var resets = claudeSession.resetsAt ? resetSpan(claudeSession.resetsAt) : ""
    return resets !== "" ? label + " · " + resets : label
  }
  readonly property string claudeGlyph: "󰧑"

  function resetSpan(iso) {
    var t = Date.parse(iso)
    if (isNaN(t)) return ""
    // Keyed off `nowMs` rather than Date.now() so the bindings that call this
    // re-evaluate on the clock tick; otherwise "resets in 2h" stayed on screen
    // until the record itself happened to change.
    var mins = Math.round((t - sys.nowMs) / 60000)
    if (mins <= 0) return "resetting"
    if (mins < 60) return "resets in " + mins + "m"
    var hours = Math.floor(mins / 60)
    if (hours < 24) return "resets in " + hours + "h " + (mins % 60) + "m"
    return "resets in " + Math.floor(hours / 24) + "d " + (hours % 24) + "h"
  }

  FileView {
    path: sys.stateDir + "/agents/usage/claude.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { sys.claude = JSON.parse(text()) } catch (e) { sys.claude = null }
    }
    onLoadFailed: sys.claude = null
  }

  // ---- keeping the record current ------------------------------------------
  // Reading the file was never the problem: nothing on this system was
  // *writing* it, so the meters sat on whichever numbers the last manual run
  // left behind — three days stale, which is what made them look like a
  // mock-up. `omarchy agent usage update claude` regenerates the record in
  // under a second and the FileView above picks the new one up, so refreshing
  // it on a timer is all "live" actually requires.
  //
  // Two cadences: a slow background one so the collapsed island and the card
  // row are never far off, and a fast one only while the Claude detail is open,
  // where the user is looking straight at the number. `--force` is reserved for
  // the moment the detail is opened, so an explicit look always re-reads the
  // authoritative limits instead of a cached copy.
  property bool claudeDetailWanted: false

  readonly property string claudeUpdatedAt: claudeReady ? String(claude.updatedAt || "") : ""
  // How old the record is, so the panel can admit staleness rather than
  // presenting an old number as current.
  property real nowMs: Date.now()
  readonly property int claudeAgeMinutes: {
    if (claudeUpdatedAt === "") return -1
    var t = Date.parse(claudeUpdatedAt)
    if (isNaN(t)) return -1
    return Math.max(0, Math.round((nowMs - t) / 60000))
  }
  readonly property string claudeAge: {
    var m = claudeAgeMinutes
    if (m < 0) return ""
    if (m < 1) return "just now"
    if (m < 60) return m + "m ago"
    var h = Math.floor(m / 60)
    if (h < 24) return h + "h ago"
    return Math.floor(h / 24) + "d ago"
  }

  Process { id: claudeRefresh; command: ["omarchy", "agent", "usage", "update", "claude"] }
  Process { id: claudeRefreshForced; command: ["omarchy", "agent", "usage", "update", "claude", "--force"] }

  function refreshClaude(force) {
    if (force) {
      if (!claudeRefreshForced.running) claudeRefreshForced.running = true
    } else if (!claudeRefresh.running) {
      claudeRefresh.running = true
    }
  }

  onClaudeDetailWantedChanged: if (claudeDetailWanted) refreshClaude(true)

  // Ticks the age readout and the reset countdowns without touching the CLI.
  Timer {
    interval: 30000
    running: true
    repeat: true
    onTriggered: sys.nowMs = Date.now()
  }

  Timer {
    id: claudeSlowTimer
    interval: 5 * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: sys.refreshClaude(false)
  }

  Timer {
    id: claudeFastTimer
    interval: 45000
    running: sys.claudeDetailWanted
    repeat: true
    onTriggered: sys.refreshClaude(false)
  }

  Component.onCompleted: refreshNetwork()
}
