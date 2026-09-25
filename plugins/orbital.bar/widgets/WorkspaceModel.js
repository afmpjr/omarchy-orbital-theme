.pragma library

var WorkspaceModel = {
    pills: [],
    _workspaces: [],
    _activeWorkspaceId: -1,
    _urgentWorkspaces: [],
    _audioWorkspaces: [],

    init: function(pillsWidget) {
        this._updateWorkspaces()
        this._setupConnections()
    },

    _setupConnections: function() {
        if (Hyprland && Hyprland.workspaces) {
            Hyprland.workspaces.connect(this, this._updateWorkspaces)
        }
        if (Hyprland && Hyprland.activeWorkspace) {
            Hyprland.activeWorkspace.connect(this, function() {
                this._activeWorkspaceId = Hyprland.activeWorkspace?.id || -1
                this._rebuildPills()
            })
        }
        if (Hyprland && Hyprland.toplevels) {
            Hyprland.toplevels.connect(this, this._updateWorkspaces)
        }
    },

    _updateWorkspaces: function() {
        if (!Hyprland || !Hyprland.workspaces) return

        var workspaces = []
        var wsList = Hyprland.workspaces
        for (var i = 0; i < wsList.length; i++) {
            var ws = wsList[i]
            if (ws.id > 0 && ws.id <= 10) {
                workspaces.push({
                    id: ws.id,
                    name: ws.name || String(ws.id),
                    monitor: ws.monitor || "",
                    hasWindows: this._workspaceHasWindows(ws.id)
                })
            }
        }

        workspaces.sort(function(a, b) { return a.id - b.id })
        this._workspaces = workspaces
        this._activeWorkspaceId = Hyprland.activeWorkspace?.id || -1
        this._rebuildPills()
    },

    _workspaceHasWindows: function(workspaceId) {
        if (!Hyprland || !Hyprland.toplevels) return false
        var toplevels = Hyprland.toplevels
        for (var i = 0; i < toplevels.length; i++) {
            var t = toplevels[i]
            if (t.workspace?.id === workspaceId) return true
        }
        return false
    },

    _rebuildPills: function() {
        var newPills = []
        var occupied = this._workspaces.filter(function(w) { return w.hasWindows })
        var maxWorkspaceId = 0

        for (var i = 0; i < this._workspaces.length; i++) {
            if (this._workspaces[i].id > maxWorkspaceId) {
                maxWorkspaceId = this._workspaces[i].id
            }
        }

        for (var i = 0; i < occupied.length; i++) {
            var ws = occupied[i]
            newPills.push({
                id: ws.id,
                name: ws.name,
                active: ws.id === this._activeWorkspaceId,
                occupied: true,
                urgent: this._urgentWorkspaces.includes(ws.id),
                audio: this._audioWorkspaces.includes(ws.id)
            })
        }

        var lastOccupied = occupied.length > 0 ? occupied[occupied.length - 1].id : 0
        var nextEmpty = lastOccupied + 1
        if (nextEmpty <= 10) {
            newPills.push({
                id: nextEmpty,
                name: String(nextEmpty),
                active: nextEmpty === this._activeWorkspaceId,
                occupied: false,
                urgent: false,
                audio: false,
                isEmpty: true
            })
        }

        this.pills = newPills
    },

    focusWorkspace: function(workspaceId) {
        if (Hyprland) {
            Hyprland.message("dispatch workspace " + workspaceId)
        }
    },

    scrollWorkspace: function(delta) {
        var current = this._activeWorkspaceId
        var next = current + delta
        if (next >= 1 && next <= 10) {
            this.focusWorkspace(next)
        }
    }
}

WorkspaceModel