.pragma library

var DockModel = {
    items: [],
    dragOver: false,
    _pinnedApps: [],
    _runningApps: [],
    _configPath: Quickshell.env("HOME") + "/.config/omarchy/orbital-dock.json",
    _statePath: Quickshell.env("HOME") + "/.local/state/omarchy/orbital-dock/",

    init: function(dockSection) {
        this._loadPinned()
        this._watchRunningApps()
        this._rebuildItems()
    },

    _loadPinned: function() {
        try {
            var file = File.read(this._configPath)
            if (file) {
                this._pinnedApps = JSON.parse(file)
            }
        } catch (e) {
            this._pinnedApps = []
        }
        this._ensureStateDir()
    },

    _ensureStateDir: function() {
        var dir = this._statePath
        if (!File.exists(dir)) {
            File.mkpath(dir)
        }
    },

    _savePinned: function() {
        this._ensureStateDir()
        File.write(this._configPath, JSON.stringify(this._pinnedApps, null, 2))
    },

    _watchRunningApps: function() {
        if (!Hyprland || !Hyprland.toplevels) return
        Hyprland.toplevels.connect(this, function() {
            this._updateRunningApps()
        })
    },

    _updateRunningApps: function() {
        var running = []
        var seen = {}

        if (Hyprland && Hyprland.toplevels) {
            var toplevels = Hyprland.toplevels
            for (var i = 0; i < toplevels.length; i++) {
                var t = toplevels[i]
                var appId = t.appId || t.class || ""
                if (!appId) continue
                var key = appId.toLowerCase()
                if (!seen[key]) {
                    seen[key] = true
                    var entry = this._findDesktopEntry(appId)
                    running.push({
                        appId: appId,
                        name: entry ? entry.name : appId,
                        icon: entry ? entry.icon : appId,
                        running: true,
                        windowCount: this._countWindows(appId)
                    })
                } else {
                    for (var j = 0; j < running.length; j++) {
                        if (running[j].appId.toLowerCase() === key) {
                            running[j].windowCount++
                            break
                        }
                    }
                }
            }
        }

        this._runningApps = running
        this._rebuildItems()
    },

    _countWindows: function(appId) {
        var count = 0
        if (Hyprland && Hyprland.toplevels) {
            var toplevels = Hyprland.toplevels
            for (var i = 0; i < toplevels.length; i++) {
                var t = toplevels[i]
                var id = (t.appId || t.class || "").toLowerCase()
                if (id === appId.toLowerCase()) count++
            }
        }
        return count
    },

    _findDesktopEntry: function(appId) {
        if (!DesktopEntries || !DesktopEntries.applications) return null
        var apps = DesktopEntries.applications
        for (var i = 0; i < apps.length; i++) {
            var app = apps[i]
            if (app.appId === appId || app.id === appId || app.name === appId) {
                return {
                    name: app.name,
                    icon: app.icon,
                    appId: app.appId,
                    exec: app.exec
                }
            }
        }
        return null
    },

    _rebuildItems: function() {
        var newItems = []
        var seen = {}

        for (var i = 0; i < this._pinnedApps.length; i++) {
            var pinned = this._pinnedApps[i]
            var running = this._findRunning(pinned.appId)
            newItems.push({
                appId: pinned.appId,
                name: pinned.name,
                icon: pinned.icon,
                running: running ? true : false,
                windowCount: running ? running.windowCount : 0,
                pinned: true,
                index: i
            })
            seen[pinned.appId.toLowerCase()] = true
        }

        for (var i = 0; i < this._runningApps.length; i++) {
            var running = this._runningApps[i]
            if (!seen[running.appId.toLowerCase()]) {
                newItems.push({
                    appId: running.appId,
                    name: running.name,
                    icon: running.icon,
                    running: true,
                    windowCount: running.windowCount,
                    pinned: false
                })
            }
        }

        this.items = newItems
    },

    _findRunning: function(appId) {
        for (var i = 0; i < this._runningApps.length; i++) {
            if (this._runningApps[i].appId.toLowerCase() === appId.toLowerCase()) {
                return this._runningApps[i]
            }
        }
        return null
    },

    pinApp: function(desktopId) {
        var entry = this._findDesktopEntry(desktopId)
        if (!entry) return

        for (var i = 0; i < this._pinnedApps.length; i++) {
            if (this._pinnedApps[i].appId === entry.appId) return
        }

        this._pinnedApps.push({
            appId: entry.appId,
            name: entry.name,
            icon: entry.icon
        })
        this._savePinned()
        this._rebuildItems()
    },

    unpinApp: function(index) {
        if (index >= 0 && index < this._pinnedApps.length) {
            this._pinnedApps.splice(index, 1)
            this._savePinned()
            this._rebuildItems()
        }
    },

    launchApp: function(appId) {
        var entry = this._findDesktopEntry(appId)
        if (entry && entry.exec) {
            Quickshell.run(entry.exec)
        } else {
            Quickshell.run("gtk-launch " + appId)
        }
    },

    focusOrMinimize: function(appId, windowCount) {
        if (windowCount === 0) {
            this.launchApp(appId)
        } else if (windowCount === 1) {
            this._focusWindow(appId)
        } else {
            this._showWindowPicker(appId)
        }
    },

    _focusWindow: function(appId) {
        if (Hyprland && Hyprland.toplevels) {
            var toplevels = Hyprland.toplevels
            for (var i = 0; i < toplevels.length; i++) {
                var t = toplevels[i]
                if ((t.appId || t.class || "").toLowerCase() === appId.toLowerCase()) {
                    Hyprland.message("dispatch focuswindow address:" + t.address)
                    break
                }
            }
        }
    },

    _showWindowPicker: function(appId) {
        // For now, just focus the most recent
        this._focusWindow(appId)
    },

    reorderPinned: function(from, to) {
        if (from < 0 || from >= this._pinnedApps.length || to < 0 || to >= this._pinnedApps.length) return
        var item = this._pinnedApps.splice(from, 1)[0]
        this._pinnedApps.splice(to, 0, item)
        this._savePinned()
        this._rebuildItems()
    }
}

DockModel