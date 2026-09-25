.pragma library

var BarModel = {
    getDefaultConfig: function() {
        return {
            position: "bottom",
            floatGap: 12,
            cornerRadius: 16,
            transparent: false,
            layout: {
                left: ["avatar", "dock"],
                center: ["workspace-pills"],
                right: ["system-controls", "clock"]
            }
        }
    },

    getWidgetRegistry: function() {
        return {
            "avatar": "AvatarWidget",
            "dock": "DockSection",
            "workspace-pills": "WorkspacePills",
            "system-controls": "SystemControls",
            "clock": "Clock"
        }
    },

    applyTheme: function(bar) {
        if (!bar) return
        bar.floatGap = bar.barConfig?.floatGap ?? 12
        bar.cornerRadius = bar.barConfig?.cornerRadius ?? 16
        bar.position = bar.barConfig?.position ?? "bottom"
    }
}

BarModel