---
created: "2026-02-07T09:05:35-05:00"
author: "Claude Opus 4.6 as Agent in VS Code GitHub Copilot"
---

# Apple Universal Control — Reverse Engineering & Research

## Goal

Programmatically control the display arrangement of macOS Universal Control (the feature that lets you use one keyboard and mouse across multiple Macs/iPads) without using the clunky "System Settings → Displays → Arrange" UI, which doesn't allow fine positioning.

## Background

When two Macs are linked via Universal Control, Hammerspoon's `hs.screen.allScreens()` only returns the local Mac's displays. The linked Mac's displays are **not** exposed through CoreGraphics or any standard display API — they are managed entirely by the Universal Control subsystem.

The arrangement of linked devices (which edge of which display is adjacent to which display on the other device, and at what vertical/horizontal offset) is what we need to read and write programmatically.

---

## Research & Reverse Engineering

### 1. Hammerspoon Can Only See Local Displays

```lua
-- Only returns the built-in display on this Mac
hs -c 'for _,s in ipairs(hs.screen.allScreens()) do
    print(s:name(), s:id(), s:fullFrame(), s:getUUID())
end'
-- Output:
-- Built-in Retina Display    1    hs.geometry.rect(0.0,0.0,1470.0,956.0)    37D8832A-2D66-02CA-B9F7-8F30A301B230
```

### 2. CoreGraphics APIs Only See Local Displays

Using Python ctypes to call `CGGetOnlineDisplayList` and `CGGetActiveDisplayList`:

```python
import ctypes, ctypes.util
cg = ctypes.CDLL(ctypes.util.find_library("CoreGraphics"))
max_displays = 32
display_array = (ctypes.c_uint32 * max_displays)()
display_count = ctypes.c_uint32(0)
cg.CGGetOnlineDisplayList(max_displays, display_array, ctypes.byref(display_count))
# Result: Count: 1, only the local display
```

### 3. `system_profiler SPDisplaysDataType` — Local Only

Only shows locally connected displays. No awareness of Universal Control linked devices.

### 4. `displayplacer` (Homebrew Tool)

[github.com/jakehilborn/displayplacer](https://github.com/jakehilborn/displayplacer) — A macOS CLI tool for configuring multi-display resolutions and arrangements. It uses CoreGraphics private SPI (`CGSBeginDisplayConfiguration`, `CGSConfigureDisplayOrigin`, `CGSCompleteDisplayConfiguration`). However, these APIs only work for **real physical displays** — Universal Control's linked displays are not `CGDirectDisplayID` entries and cannot be managed this way.

---

## Where Universal Control Arrangement Data Is Stored

### 5. The Universal Control Preferences Plist

The arrangement is stored in a per-host plist:

```
~/Library/Preferences/ByHost/com.apple.universalcontrol.<host-uuid>.plist
```

On this Mac:
```
~/Library/Preferences/ByHost/com.apple.universalcontrol.B10FE300-673C-51DE-8F2B-6EE7E132CF1B.plist
```

The plist has three keys:
- `Configuration` — binary data (4959 bytes) containing a nested binary plist
- `ConfigurationID` — 32-byte hash
- `HasShownControlNotification` — boolean

### 6. The Configuration CRDT Structure

The `Configuration` value is itself a binary plist with this structure:

```python
{
    "vers": 3,          # Version
    "head": bytes,      # 32-byte hash pointing to the current head node
    "heap": [...],      # List of CRDT nodes (linked list)
    "refs": {}          # References (empty in observed data)
}
```

Each heap entry is a list with either 5 elements (a simple node) or 5+ elements (a node with arrangement records):

**Simple node (5 elements):**
```
[
    bytes(32),    # Node ID (hash)
    int,          # Timestamp (monotonic, not epoch)
    int,          # Flag (always 1 in observed data)
    bytes(32),    # Reference to another node (linked list pointer)
    int           # Sub-count (0 for simple nodes)
]
```

**Arrangement node (5 + N elements):**
```
[
    bytes(32),    # Node ID (hash)
    int,          # Timestamp
    int,          # Flag
    bytes(32),    # Reference to another node
    int,          # Sub-count (N, number of arrangement records)
    [record],     # Arrangement record 0
    [record],     # Arrangement record 1
    ...           # ...
]
```

**Each arrangement record is a list of 8 elements:**
```
[
    int,      # Timestamp (monotonic)
    int,      # Edge: 0=LEFT, 1=RIGHT, 2=TOP, 3=BOTTOM
    string,   # Device 1 UUID
    string,   # Display 1 UUID (or 00000000-0000-0000-0000-000000000000 for "any")
    string,   # Device 2 UUID
    string,   # Display 2 UUID
    int,      # Offset value 1 (UInt16, range 0–65535, 32767=center)
    int        # Offset value 2 (UInt16, range 0–65535, 32767=center)
]
```

The record means: "Display 1 on Device 1 has Display 2 on Device 2 adjacent on its [edge] side, at position [offset1, offset2]."

### 7. Parsing Script

```python
import plistlib, os, glob
from collections import defaultdict

pattern = os.path.expanduser("~/Library/Preferences/ByHost/com.apple.universalcontrol.*.plist")
files = glob.glob(pattern)
path = files[0]

with open(path, 'rb') as f:
    data = plistlib.load(f)

config_data = data['Configuration']
inner = plistlib.loads(config_data)

# Find entries with arrangement data
for i, entry in enumerate(inner['heap']):
    if len(entry) > 5:
        for j in range(5, len(entry)):
            arr = entry[j]
            if isinstance(arr, list):
                edge_names = {0: "LEFT", 1: "RIGHT", 2: "TOP", 3: "BOTTOM"}
                print(f"Record: edge={edge_names.get(arr[1], arr[1])} "
                      f"dev1={arr[2]} disp1={arr[3]} "
                      f"dev2={arr[4]} disp2={arr[5]} "
                      f"v1={arr[6]} v2={arr[7]}")
```

### 8. Observed Devices and Displays

From parsing the plist on this Mac (`bofoh`):

| Device UUID | # Displays | Notes |
|---|---|---|
| `9B43C016-C734-4027-A0D7-5819912121EC` | 3 | **This Mac** (built-in `37D8832A…` + 2 historical externals) |
| `97755A49-A45B-459D-BD0A-D6295363DDE7` | 10 | Another Mac (many historical display configs) |
| `B731E312-3129-4D4A-B292-A728F9A9A239` | 3 | Another Mac (currently linked — LEFT neighbor) |
| `B3072AE8-1D97-486E-B515-82835EEC82C2` | 1 | Another Mac or iPad |
| `BA5D5F8D-CA6F-4D75-B7CE-6DB4D2CF909F` | 1 | Another Mac or iPad |
| `21A366DF-6A11-480F-AFA1-4372EEBD62B0` | 0 (uses null display) | A Mac with no specific display recorded |

This Mac's local display UUID: `37D8832A-2D66-02CA-B9F7-8F30A301B230`

### 9. Current Active Arrangement (Head Record)

The head hash `e7422e16…` points to heap entry 45, which contains a single record:

```
edge=LEFT
dev1=9B43C016-C734-4027-A0D7-5819912121EC (this Mac)
disp1=37D8832A-2D66-02CA-B9F7-8F30A301B230 (Built-in Retina Display, 1470×956@2x)
dev2=B731E312-3129-4D4A-B292-A728F9A9A239
disp2=69C894C5-0AD6-4735-ACCD-AD1416937F61
v1=65535 v2=0
```

Meaning: Device `B731E312…`'s display `69C894C5…` is on the **LEFT** edge of this Mac's built-in display, aligned to the **top** (`v1=65535, v2=0`).

### 10. Offset Value Semantics

The offset values (`v1`, `v2`) use the `UInt16` range 0–65535:
- `32767` = centered (midpoint)
- `65535` and `0` together = aligned to one extreme (top/left or bottom/right)
- Other values = proportional offset along the edge

---

## The UniversalControl.framework Private API

### 11. Framework and Daemon Discovery

```bash
# Find UC-related files
mdfind "kMDItemFSName == *UniversalControl*"
# Results:
# /System/Library/CoreServices/UniversalControl.app
# /usr/share/man/man8/UniversalControl.8
# /System/Library/PrivateFrameworks/UniversalControl.framework
# /System/Library/HIDPlugins/ServiceFilters/UniversalControlServiceFilter.plugin
```

Man page content (minimal):
```
UniversalControl – Universal Control
The UniversalControl process provides Universal Control for the system.
There are no configuration options for UniversalControl, and users should not run UniversalControl manually.
```

### 12. Launchd Service

```bash
plutil -p /System/Library/LaunchAgents/com.apple.ensemble.plist
```

```
Label: com.apple.ensemble
Program: /System/Library/CoreServices/UniversalControl.app/Contents/MacOS/UniversalControl
MachServices:
    com.apple.ensemble: true
    com.apple.ensemble.dragserver: (HideUntilCheckIn)
LaunchEvents:
    com.apple.rapport.matching:
        com.apple.universalcontrol.discovery: (serviceType: _companion-link._tcp, type: discovery)
        com.apple.universalcontrol.server: (serviceType: com.apple.universalcontrol, type: server)
```

Key facts:
- **Launchd label**: `com.apple.ensemble`
- **Mach service name**: `com.apple.ensemble` (this is the XPC endpoint)
- **Internal codename**: "Ensemble"
- Built on top of Apple's `rapport` framework (peer-to-peer device communication, also used by AirPlay/Handoff)
- Uses AWDL (Apple Wireless Direct Link) for transport

### 13. XPC Interface (from binary string analysis)

```bash
strings /System/Library/CoreServices/UniversalControl.app/Contents/MacOS/UniversalControl | grep "XPC" | sort -u
```

XPC commands found:
```
=== XPC: Connected Devices ===
=== XPC: Devices ===
=== XPC: Diagnose ===
=== XPC: Edges ===
=== XPC: IDS ===
=== XPC: Local Device ==
XPC: Disconnect
XPC: Disconnect All
XPC: Release Client Assertion
XPC: Set Automatically Reconnect
XPC: Set Client Assertion
XPC: Set Configuration          ← KEY: This is how arrangement is set
XPC: Synchronize
```

### 14. Mach Service Identifiers Found in Binary

```bash
strings /System/Library/CoreServices/UniversalControl.app/Contents/MacOS/UniversalControl | grep "^com.apple." | sort -u
```

```
com.apple.ensemble.dragserver
com.apple.universalcontrol
com.apple.universalcontrol.available
com.apple.universalcontrol.connected
com.apple.universalcontrol.hid-activity
com.apple.universalcontrol.inputstate
com.apple.universalcontrol.notifications.displays-preferences
com.apple.universalcontrol.p2p-peer-coordinator
com.apple.universalcontrol.shield
com.apple.universalcontrol.transfer-destination
com.apple.universalcontrol.transfer-source
com.apple.universalcontrol.ui
com.apple.universalcontrol.virtual-service
com.apple.universalcontrol.virtual-service-pool
com.apple.universalcontrol.virtual-service-pool.services
```

### 15. Internal Source File Paths (from binary)

The binary leaks build-root paths revealing the source structure:

```
Ensemble_executables/Agent/main_macOS.swift
Ensemble_executables/EnsembleAgent/Agent.swift
Ensemble_executables/EnsembleAgent/ConnectionController.swift
Ensemble_executables/EnsembleAgent/ConnectionCoordinator.swift
Ensemble_executables/EnsembleAgent/DisplaySleepAssertionController_macOS.swift
Ensemble_executables/EnsembleAgent/DragController.swift
Ensemble_executables/EnsembleAgent/DragPlatformProvider_macOS.swift
Ensemble_executables/EnsembleAgent/DragSinkCoordinator.swift
Ensemble_executables/EnsembleAgent/DragSourceCoordinator.swift
Ensemble_executables/EnsembleAgent/EnsembleHIDController.swift
Ensemble_executables/EnsembleAgent/EventController.swift
Ensemble_executables/EnsembleAgent/EventReport.swift
Ensemble_executables/EnsembleAgent/P2PBrowser.swift
Ensemble_executables/EnsembleAgent/P2PController.swift
Ensemble_executables/EnsembleAgent/P2PDirectLink.swift
Ensemble_executables/EnsembleAgent/P2PLink.swift
Ensemble_executables/EnsembleAgent/P2PMessage.swift
Ensemble_executables/EnsembleAgent/P2PPeerCoordinator.swift
Ensemble_executables/EnsembleAgent/P2PStream.swift
Ensemble_executables/EnsembleAgent/PasteboardController.swift
Ensemble_executables/EnsembleAgent/PasteboardController_macOS.swift
Ensemble_executables/EnsembleAgent/PasteboardDataSession.swift
Ensemble_executables/EnsembleAgent/PowerManagement_macOS.swift
Ensemble_executables/EnsembleAgent/SyncContext.swift
Ensemble_executables/EnsembleAgent/SyncController.swift
Ensemble_executables/EnsembleAgent/SyncCoordinator.swift
Ensemble_executables/EnsembleHID/HIDCapsLock.swift
Ensemble_executables/CompanionLink/RapportStreamServer.swift
Ensemble_executables/Glue/Archive.swift
```

### 16. Display Arrangement Logging Strings

Key strings from the binary that reveal how arrangement works internally:

```
Reconfigured Display: %{public}s [%f %f %f %f]
Display Layout: [%{public}s] version=%ld
Display Layout Links: %{public}s
Display Layout Rects: %{public}s
Remote Display Layout: [%{public}s]
Local Display Layout did change
Invalid screenRect: %{public}s, device: %{public}s, display: %{public}s
Connect via magic edge: remove any links between %{public}s and %{public}s
IDS %{public}s: Target Ready: edge=%{public}s, offset=%f, drag=%{public}s, keyboard=%{public}s
Hot Zone: Timed Out (on edge): %{public}s dwell=%.*fs t=%.*fs
Magic Edge: %{public}s
Enabling Magic Edges: %{public}s
Solver did solve a device offset for the local device
```

### 17. How System Settings Talks to Universal Control

The Displays System Settings extension lives at:
```
/System/Library/ExtensionKit/Extensions/DisplaysExt.appex
```

It links against these key frameworks:
```bash
otool -L /System/Library/ExtensionKit/Extensions/DisplaysExt.appex/Contents/MacOS/DisplaysExt
```
```
/System/Library/PrivateFrameworks/UniversalControl.framework/Versions/A/UniversalControl
/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight
/System/Library/Frameworks/CoreDisplay.framework/Versions/A/CoreDisplay
/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/A/DisplayServices
/System/Library/PrivateFrameworks/SidecarCore.framework/Versions/A/SidecarCore
```

Key strings from DisplaysExt binary:
```
Failed to reflect display origin to Ensemble:
Failed to set display origin for Ensemble device:
Failed to configure display origin. Error =
applyConfigurationChanges(displaysRearranged:)
EnsembleDeviceDisplay
ArrangementProxy
DisplayItemProxy
RemoteDeviceProxy
UniversalControlManager failed to connect to
```

Key Swift classes in DisplaysExt:
```
DisplaysExt.ArrangementProxy          — manages the arrangement UI
DisplaysExt.DisplayItemProxy          — proxy for a single display
DisplaysExt.RemoteDeviceProxy         — proxy for a remote UC device
DisplaysExt.EnsembleDeviceDisplay     — a display on a UC-linked device
DisplaysExt.DeviceProxy               — base proxy for a device
DisplaysExt.DisplaysManager           — overall display management
DisplaysExt.DisplaySettingsManager    — settings management
```

Source path found in binary:
```
DisplaysPref/DisplaysPref/ArrangementProxy.swift
DisplaysPref/DisplaysPref/DisplayItemProxy.swift
```

---

## The UniversalControl.framework API (Demangled Swift Symbols)

### 18. How to Extract the API

The framework binary is in the dyld shared cache (the on-disk framework is a stub with no binary):

```bash
# The framework stub is empty:
ls -la /System/Library/PrivateFrameworks/UniversalControl.framework/Versions/A/
# Only Resources/ and _CodeSignature/ — no binary file

# But dyld_info can read it from the shared cache:
dyld_info -exports /System/Library/PrivateFrameworks/UniversalControl.framework/UniversalControl 2>/dev/null \
    | swift demangle 2>/dev/null
```

### 19. `UniversalControlManager` — Main Entry Point

```swift
class UniversalControlManager {
    // Properties
    var localDevice: UniversalControlDevice?                    // This Mac
    var availableDevices: [UniversalControlDevice]              // Nearby UC-capable devices
    var connectedDevices: [UniversalControlDevice]              // Currently linked devices
    var testableDevices: [UniversalControlDevice]               // (get/set/modify)
    var activeEdges: [UniversalControlEdgeRegion]               // Current hot zone edges
    var configuration: UniversalControlConfiguration            // Current arrangement config
    var isSynchronized: Bool
    var description: String
    var debugDescription: String

    // Methods
    func setConfiguration(_: UniversalControlConfiguration, completion: (Error?) -> ())
    func disconnect()
    func disconnect(from: UniversalControlDevice, completion: (Error?) -> ())
    func disconnect(from: UniversalControlDeviceID, completion: (Error?) -> ())
    func synchronize(with: [UniversalControlDeviceID],
                     completion: ([UniversalControlDeviceID: Error?], Error?) -> ())
    func takeClientAssertion(UVCClientAssertion) -> AnyCancellable
}
```

### 20. `UniversalControlConfiguration` — The Arrangement

```swift
class/struct UniversalControlConfiguration {
    // Methods for manipulating links (adjacency relationships)
    func addingLinks([UniversalControlLink]) -> UniversalControlConfiguration
    func removingLinks(where: (UniversalControlLink) -> Bool) -> UniversalControlConfiguration
    func replacing(links: [UniversalControlLink]) -> UniversalControlConfiguration
    func findConflicts(UniversalControlLink) -> [UniversalControlLink]
    func recentLink(between: UniversalControlDeviceID,
                    and: UniversalControlDeviceID) -> UniversalControlLink?

    // Nested type
    struct GradedLink {
        var edge: UniversalControlEdge
        var link: UniversalControlLink
        var endpoint1: UniversalControlLink.Endpoint
        var endpoint2: UniversalControlLink.Endpoint
        var display1: UniversalControlDisplayID
        var display2: UniversalControlDisplayID
        var fixedOffset1: UInt16
        var fixedOffset2: UInt16
        var isNormalized: Bool
        func normalized() -> GradedLink
        func flipped() -> GradedLink
    }
}
```

### 21. `UniversalControlLink` — A Single Adjacency

```swift
struct UniversalControlLink: Codable, Hashable, Comparable {
    // Initializers
    init(display1: UniversalControlDisplayID,
         display2: UniversalControlDisplayID,
         edge: UniversalControlEdge,
         fixedOffset1: UInt16,
         fixedOffset2: UInt16)

    init(endpoint1: Endpoint, endpoint2: Endpoint)

    init(from: Decoder) throws  // Codable

    // Properties
    var edge: UniversalControlEdge
    var fixedOffset1: UInt16      // Position offset (0–65535, 32767=center)
    var fixedOffset2: UInt16
    var isNormalized: Bool

    // Methods
    func normalized() -> UniversalControlLink
    func normalized(for: UniversalControlDeviceID) -> UniversalControlLink
    func flipped() -> UniversalControlLink
    func encode(to: Encoder) throws
    func hash(into: inout Hasher)

    // Nested type
    struct Endpoint: Codable, Hashable, Comparable {
        var device: UniversalControlDeviceID
        var display: UniversalControlDisplayID
        var anchor: UniversalControlAnchor

        init(display: UniversalControlDisplayID, anchor: UniversalControlAnchor)
        init(from: Decoder) throws
    }
}
```

### 22. `UniversalControlDisplayLayout` — Computed Layout

```swift
struct UniversalControlDisplayLayout {
    var displaysID: UniversalControlUUID
    var configuration: UniversalControlUUID

    init(configuration: UniversalControlUUID,
         devices: [UniversalControlDeviceID],
         displaysID: UniversalControlUUID,
         links: [UniversalControlLink],
         displayFrames: [UniversalControlDisplayID: CGRect])
}
```

### 23. `UniversalControlEdgeRegion` — Hot Zone on a Display Edge

```swift
class UniversalControlEdgeRegion {
    var id: UniversalControlDisplayID      // (get/set/modify)
    var edge: UniversalControlEdge         // (get/set/modify)
    var rect: CGRect                       // (get/set/modify)

    init(id: UniversalControlDisplayID, edge: UniversalControlEdge, rect: CGRect)
}
```

### 24. Supporting Types

```swift
struct UniversalControlDisplayID { ... }
struct UniversalControlDeviceID { ... }
struct UniversalControlUUID { ... }
struct UniversalControlAnchor { ... }

enum UniversalControlEdge {
    // Values: left (0), right (1), top (2), bottom (3)
}

class UniversalControlDevice {
    enum DeviceType {
        case mac
        case iPad
        case realityDevice
        case other
    }
}

class UniversalControlDisplay { ... }

// XPC transport types
class UniversalControlXPCDevice { ... }        // ObjC class
class UniversalControlXPCEdgeRegion { ... }    // ObjC class

// Display solvers (likely for computing layout from links)
class UniversalControlDisplaySolver0 { ... }
class UniversalControlDisplaySolver1 { ... }
class UniversalControlDisplaySolver2 { ... }

// Preferences
class UniversalControlPreferences {
    var configuration: UniversalControlConfiguration?  // (get/set/modify)
}

// Diagnostics
enum UniversalControlDiagnoseCategory {
    case config
    // ...
}
class UniversalControlConfigurationDiagnostics { ... }
class SystemConfigurationGlue { ... }
```

### 25. Other Configuration Strings

```
AlwaysGuardEdges
DisableMagicEdges
MagicEdgeDebounceTime
MagicEdgeRejectTime
```

These are likely `defaults write com.apple.universalcontrol` keys for debugging/tuning, not arrangement.

---

## Online Research Summary

### 26. No Public API Exists

There is **no public Apple API**, framework, or documented interface for programmatically controlling Universal Control display arrangement.

### 27. How Universal Control Works (from eclecticlight.co)

From Howard Oakley's [Inside Universal Control](https://eclecticlight.co/2022/06/06/inside-universal-control/) analysis:

- **Bundle ID**: `com.apple.universalcontrol`
- **Architecture**: Uses a **Controller** (the Mac whose input devices are master) and a **Target** (the Mac/iPad being controlled)
- **Communication layer**: Built on `com.apple.rapport` — Apple's private framework for peer-to-peer device communication (also used by AirPlay, Handoff)
- **Transport**: Uses AWDL (Apple Wireless Direct Link)
- **Event protocol**: Custom event IDs over the Rapport stream:
  - `SYNC` — synchronization between Controller and Target
  - `EVNT` — input device events (mouse moves, clicks, keyboard)
  - `DRAG` — drag-and-drop events
  - `CLIP` — clipboard/pasteboard events
- **Activation**: Pointer enters a "Hot Zone" at display edge → "Sync Barrier" handshake
- **Log subsystems**: `com.apple.universalcontrol` and `com.apple.rapport`

### 28. MDM Control (Enable/Disable Only)

The only known programmatic control via MDM is **disabling UC entirely**:

```xml
<key>com.apple.universalcontrol</key>
<dict>
    <key>Forced</key>
    <array><dict>
        <key>mcx_preference_settings</key>
        <dict>
            <key>Disable</key>
            <true/>
        </dict>
    </dict></array>
</dict>
```

Or via `defaults`:
```bash
defaults write com.apple.universalcontrol Disable -bool true
```

There is **no MDM payload** for controlling arrangement.

### 29. No Third-Party Tools Found

- **displayplacer** — Only handles local CoreGraphics displays, not UC virtual displays
- **LinearMouse** — No UC integration (only mouse/trackpad input processing)
- **MonitorControl** — No UC awareness (only DDC/brightness control)
- **BetterDisplay** — No UC arrangement features found
- **No GitHub repos** found that modify `com.apple.universalcontrol` arrangement
- **No reverse engineering** of the arrangement protocol published online (prior to this research)

---

## Conclusions & Practical Approaches

### There IS a programmatic API — it's Apple's private `UniversalControl.framework`

The Displays System Settings extension (`DisplaysExt.appex`) links directly against `/System/Library/PrivateFrameworks/UniversalControl.framework` and uses it to read and **set** Universal Control display arrangement. This is not filesystem manipulation — it's an XPC-based API.

### The Key API Surface (demangled from the framework)

**`UniversalControlManager`** — the main entry point:
- `.configuration` → get current `UniversalControlConfiguration`
- `.setConfiguration(_:completion:)` → **set a new arrangement** ✅
- `.localDevice` → this Mac's `UniversalControlDevice`
- `.availableDevices` / `.connectedDevices` → lists remote devices
- `.activeEdges` → current hot zone edges
- `.disconnect()` / `.synchronize(with:completion:)`

**`UniversalControlConfiguration`** — describes the arrangement:
- `.addingLinks([UniversalControlLink])` → adds adjacency links
- `.removingLinks(where:)` → removes links
- `.replacing(links:)` → replaces all links

**`UniversalControlLink`** — a single adjacency between two displays:
- `.init(display1:display2:edge:fixedOffset1:fixedOffset2:)` — the key constructor
- `edge` — `UniversalControlEdge` (left/right/top/bottom)
- `fixedOffset1` / `fixedOffset2` — `UInt16` values (0–65535, 32767=center)
- `endpoint1` / `endpoint2` — each containing `device`, `display`, `anchor`

**`UniversalControlDisplayID`** — wraps device UUID + display UUID

The UC agent runs as `com.apple.ensemble` (Mach service name) and accepts XPC commands including `XPC: Set Configuration` and `XPC: Edges`.

### The Bad News

This is a **private Swift framework** with no headers and no Objective-C bridge. Calling it from outside Apple's own code would require:
1. Loading the framework dynamically with `dlopen`
2. Using the Swift runtime ABI to call the mangled symbols
3. Your process would need the right entitlements (the Displays pane runs within System Settings which has the necessary entitlements)

### Practical Approaches (no system file modification)

1. **GUI scripting via AppleScript/Accessibility** — Automate the "System Settings → Displays → Arrange" UI using AppleScript and the Accessibility framework. This is clunky but works without modifying any files.

2. **Write a small Swift helper** that links against `UniversalControl.framework` and calls `UniversalControlManager.setConfiguration()`. This would need to be a proper signed executable but wouldn't modify system files — it would talk to the UC daemon via XPC. However, it may be restricted by entitlements.

3. **XPC direct communication** — Connect to the `com.apple.ensemble` Mach service directly and send the right XPC dictionary. The protocol would need reverse engineering from the binary.

---

## Reverse Engineering Methods Used

1. **Hammerspoon CLI** (`hs -c '...'`) — to query local display state
2. **Python `plistlib`** — to parse binary plists, including the nested Configuration blob
3. **Python `ctypes`** — to call CoreGraphics C API (`CGGetOnlineDisplayList`, `CGGetActiveDisplayList`)
4. **`system_profiler SPDisplaysDataType`** — to check system-level display info
5. **`defaults find`** / **`defaults read`** — to search for relevant preference domains
6. **`find`** / **`mdfind`** — to locate UC-related files on disk
7. **`plutil -p`** — to read plist files in human-readable format
8. **`strings`** — to extract readable strings from Mach-O binaries
9. **`otool -L`** — to check dynamic library dependencies
10. **`dyld_info -exports`** — to extract exported symbols from the dyld shared cache
11. **`swift demangle`** — to demangle Swift symbol names into readable API signatures
12. **`file`** / **`ls -la`** — to check binary types and symlink targets
13. **Web research** — Apple developer docs, GitHub repos, eclecticlight.co articles
14. **`man`** — to check for documentation of the UC binary

---

## Key File Locations

| Path | Description |
|---|---|
| `/System/Library/CoreServices/UniversalControl.app` | The UC agent application |
| `/System/Library/PrivateFrameworks/UniversalControl.framework` | The UC framework (stub; real code in dyld cache) |
| `/System/Library/LaunchAgents/com.apple.ensemble.plist` | Launchd agent configuration |
| `/System/Library/HIDPlugins/ServiceFilters/UniversalControlServiceFilter.plugin` | HID event filter plugin |
| `/System/Library/ExtensionKit/Extensions/DisplaysExt.appex` | Displays System Settings extension |
| `~/Library/Preferences/ByHost/com.apple.universalcontrol.<host-uuid>.plist` | Per-host UC configuration (CRDT) |
| `~/Library/Preferences/ByHost/com.apple.windowserver.displays.<host-uuid>.plist` | Local display arrangement |

## Key Identifiers

| Identifier | Type | Description |
|---|---|---|
| `com.apple.ensemble` | Mach service / launchd label | The UC daemon's XPC endpoint |
| `com.apple.ensemble.dragserver` | Mach service | Drag-and-drop server |
| `com.apple.universalcontrol` | Bundle ID / preference domain | UC app and preferences |
| `com.apple.rapport` | Framework | Device-to-device communication layer |
| `_companion-link._tcp` | Bonjour service | UC device discovery |
