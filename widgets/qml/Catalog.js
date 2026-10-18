// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

// Every widget this plugin ships. `file` is under widgets/, sizes are in
// logical pixels, and `config` is the schema the settings sheet draws.
// Field types: bool, enum (values + labels), text, number (min/max/step).

var CATEGORIES = [
    { id: "clock", label: "Clocks", icon: "schedule" },
    { id: "date", label: "Date", icon: "calendar_today" },
    { id: "media", label: "Media", icon: "play_circle" },
    { id: "system", label: "System", icon: "monitor_heart" },
    { id: "weather", label: "Weather", icon: "partly_cloudy_day" },
    { id: "productivity", label: "Productivity", icon: "task_alt" },
    { id: "utility", label: "Utility", icon: "build" },
    { id: "aphotic", label: "Aphotic", icon: "blur_on" }
];

var COMMON = {
    background: { type: "enum", label: "Background", default: "glass", values: ["glass", "line", "none"], labels: ["Glass", "Hairline", "None"] },
    opacity: { type: "number", label: "Glass opacity", default: 0.72, min: 0.1, max: 1, step: 0.05 },
    accent: { type: "enum", label: "Accent", default: "signal", values: ["signal", "secondary", "tertiary", "ink"], labels: ["Signal", "Secondary", "Tertiary", "Ink"] }
};

var HOUR = { type: "enum", label: "Hours", default: "system", values: ["system", "24", "12"], labels: ["System", "24-hour", "12-hour"] };

var TYPES = [
    { type: "clockDigital", label: "Digital clock", category: "clock", icon: "schedule", file: "ClockDigital.qml", w: 320, h: 150, minW: 160, minH: 80,
        description: "Large time with optional seconds and date.",
        config: { seconds: { type: "bool", label: "Seconds", default: false }, date: { type: "bool", label: "Date line", default: true }, hours: HOUR,
            align: { type: "enum", label: "Align", default: "left", values: ["left", "center", "right"], labels: ["Left", "Center", "Right"] } } },
    { type: "clockAnalog", label: "Analog clock", category: "clock", icon: "nest_clock_farsight_analog", file: "ClockAnalog.qml", w: 220, h: 220, minW: 100, minH: 100,
        description: "A hairline dial with hour and minute hands.",
        config: { seconds: { type: "bool", label: "Second hand", default: false }, numerals: { type: "bool", label: "Numerals", default: true },
            marks: { type: "enum", label: "Marks", default: "ticks", values: ["ticks", "dots", "none"], labels: ["Ticks", "Dots", "None"] } } },
    { type: "clockWord", label: "Word clock", category: "clock", icon: "text_fields", file: "ClockWord.qml", w: 320, h: 140, minW: 180, minH: 80,
        description: "The time in plain words, to the nearest five minutes.",
        config: { casing: { type: "enum", label: "Casing", default: "sentence", values: ["sentence", "upper", "lower"], labels: ["Sentence", "Upper", "Lower"] } } },
    { type: "clockWorld", label: "World clock", category: "clock", icon: "public", file: "ClockWorld.qml", w: 300, h: 200, minW: 200, minH: 90,
        description: "Local time in other places.",
        config: { zones: { type: "text", label: "Time zones (comma separated)", default: "Europe/London, America/New_York, Asia/Tokyo" }, hours: HOUR } },
    { type: "clockRings", label: "Ring clock", category: "clock", icon: "donut_large", file: "ClockRings.qml", w: 220, h: 220, minW: 110, minH: 110,
        description: "Hours, minutes and seconds as three concentric arcs.",
        config: { seconds: { type: "bool", label: "Seconds ring", default: true }, label: { type: "bool", label: "Time in the middle", default: true } } },
    { type: "clockStack", label: "Stacked clock", category: "clock", icon: "view_agenda", file: "ClockStack.qml", w: 180, h: 220, minW: 100, minH: 120,
        description: "Hour over minute, set large.",
        config: { hours: HOUR, weekday: { type: "bool", label: "Weekday", default: true } } },
    { type: "clockBinary", label: "Binary clock", category: "clock", icon: "grid_on", file: "ClockBinary.qml", w: 240, h: 160, minW: 140, minH: 90,
        description: "Hours, minutes and seconds as lit dots.",
        config: { labels: { type: "bool", label: "Digits under columns", default: true } } },
    { type: "dayProgress", label: "Progress of the day", category: "clock", icon: "hourglass_bottom", file: "DayProgress.qml", w: 300, h: 160, minW: 180, minH: 90,
        description: "How much of the day, week, month and year has gone.",
        config: { year: { type: "bool", label: "Show year", default: true }, workday: { type: "bool", label: "Day means working hours", default: false },
            start: { type: "number", label: "Workday start (hour)", default: 9, min: 0, max: 23, step: 1 }, end: { type: "number", label: "Workday end (hour)", default: 17, min: 1, max: 24, step: 1 } } },

    { type: "dateStack", label: "Date stack", category: "date", icon: "event", file: "DateStack.qml", w: 170, h: 190, minW: 100, minH: 110,
        description: "Weekday, a big day number and the month.", config: {} },
    { type: "dateBanner", label: "Date banner", category: "date", icon: "short_text", file: "DateBanner.qml", w: 380, h: 90, minW: 200, minH: 50,
        description: "The full date on one line.",
        config: { year: { type: "bool", label: "Year", default: false } } },
    { type: "calendarMonth", label: "Month calendar", category: "date", icon: "calendar_month", file: "CalendarMonth.qml", w: 300, h: 290, minW: 200, minH: 200,
        description: "This month with today marked. Scroll to change month.",
        config: { weekStart: { type: "enum", label: "Week starts", default: "monday", values: ["monday", "sunday"], labels: ["Monday", "Sunday"] },
            weekNumbers: { type: "bool", label: "Week numbers", default: false } } },
    { type: "calendarWeek", label: "Week strip", category: "date", icon: "view_week", file: "CalendarWeek.qml", w: 380, h: 110, minW: 240, minH: 70,
        description: "The seven days of this week.",
        config: { weekStart: { type: "enum", label: "Week starts", default: "monday", values: ["monday", "sunday"], labels: ["Monday", "Sunday"] } } },
    { type: "countdown", label: "Countdown", category: "date", icon: "event_upcoming", file: "Countdown.qml", w: 260, h: 150, minW: 150, minH: 90,
        description: "Days left until a date you care about.",
        config: { title: { type: "text", label: "What", default: "New year" }, date: { type: "text", label: "Date (YYYY-MM-DD)", default: "" } } },

    { type: "mediaNowPlaying", label: "Now playing", category: "media", icon: "music_note", file: "MediaNowPlaying.qml", w: 380, h: 150, minW: 260, minH: 110,
        description: "Cover, title, artist, progress and controls.",
        config: { progress: { type: "bool", label: "Progress bar", default: true } } },
    { type: "mediaCompact", label: "Media pill", category: "media", icon: "graphic_eq", file: "MediaCompact.qml", w: 320, h: 64, minW: 200, minH: 48,
        description: "Title and play/pause in one line.", config: {} },
    { type: "mediaCover", label: "Album cover", category: "media", icon: "album", file: "MediaCover.qml", w: 240, h: 240, minW: 140, minH: 140,
        description: "The cover art, with controls on hover.", config: {} },
    { type: "mediaDisc", label: "Spinning disc", category: "media", icon: "radio_button_checked", file: "MediaDisc.qml", w: 220, h: 220, minW: 120, minH: 120,
        description: "The cover on a disc that turns while music plays.",
        config: { spin: { type: "bool", label: "Spin while playing", default: true } } },

    { type: "sysCpu", label: "CPU", category: "system", icon: "memory", file: "SysCpu.qml", w: 170, h: 170, minW: 110, minH: 110,
        description: "Processor load and temperature.", config: { temp: { type: "bool", label: "Temperature", default: true } } },
    { type: "sysRam", label: "Memory", category: "system", icon: "memory_alt", file: "SysRam.qml", w: 170, h: 170, minW: 110, minH: 110,
        description: "Memory in use.", config: {} },
    { type: "sysGpu", label: "GPU", category: "system", icon: "developer_board", file: "SysGpu.qml", w: 170, h: 170, minW: 110, minH: 110,
        description: "Graphics load and temperature.", config: { temp: { type: "bool", label: "Temperature", default: true } } },
    { type: "sysDisk", label: "Disks", category: "system", icon: "hard_drive", file: "SysDisk.qml", w: 300, h: 170, minW: 200, minH: 80,
        description: "Used space per mounted drive.", config: {} },
    { type: "sysNetwork", label: "Network", category: "system", icon: "network_check", file: "SysNetwork.qml", w: 300, h: 150, minW: 200, minH: 90,
        description: "Download and upload speed with a short history.", config: { graph: { type: "bool", label: "History graph", default: true } } },
    { type: "sysResources", label: "Resources", category: "system", icon: "equalizer", file: "SysResources.qml", w: 300, h: 180, minW: 200, minH: 120,
        description: "CPU, memory, GPU and disk side by side.",
        config: { layout: { type: "enum", label: "Layout", default: "columns", values: ["columns", "rows"], labels: ["Columns", "Rows"] } } },
    { type: "sysBattery", label: "Battery", category: "system", icon: "battery_full", file: "SysBattery.qml", w: 220, h: 110, minW: 140, minH: 70,
        description: "Charge, state and time left.", config: {} },
    { type: "sysUptime", label: "Host", category: "system", icon: "dns", file: "SysUptime.qml", w: 260, h: 120, minW: 180, minH: 80,
        description: "Host name, address and uptime.", config: { address: { type: "bool", label: "IP address", default: true } } },
    { type: "sysProcesses", label: "Top processes", category: "system", icon: "list_alt", file: "SysProcesses.qml", w: 300, h: 200, minW: 220, minH: 120,
        description: "The busiest processes right now.",
        config: { count: { type: "number", label: "Rows", default: 5, min: 3, max: 10, step: 1 } } },

    { type: "weatherNow", label: "Weather", category: "weather", icon: "partly_cloudy_day", file: "WeatherNow.qml", w: 260, h: 150, minW: 160, minH: 90,
        description: "Current temperature and conditions.", config: { place: { type: "bool", label: "Place name", default: true } } },
    { type: "weatherForecast", label: "Forecast", category: "weather", icon: "calendar_view_week", file: "WeatherForecast.qml", w: 380, h: 150, minW: 240, minH: 100,
        description: "Today and the next two days, high and low.",
        config: { days: { type: "number", label: "Days", default: 3, min: 2, max: 3, step: 1 } } },
    { type: "weatherPill", label: "Weather pill", category: "weather", icon: "thermostat", file: "WeatherPill.qml", w: 200, h: 56, minW: 140, minH: 44,
        description: "Icon and temperature, compact.", config: {} },

    { type: "timer", label: "Timer", category: "productivity", icon: "timer", file: "Timer.qml", w: 240, h: 170, minW: 170, minH: 120,
        description: "Count down from a preset, with a notification at the end.",
        config: { minutes: { type: "number", label: "Default minutes", default: 10, min: 1, max: 180, step: 1 } } },
    { type: "stopwatch", label: "Stopwatch", category: "productivity", icon: "avg_pace", file: "Stopwatch.qml", w: 240, h: 170, minW: 170, minH: 110,
        description: "Start, stop and laps.", config: {} },
    { type: "pomodoro", label: "Pomodoro", category: "productivity", icon: "nutrition", file: "PomodoroWidget.qml", w: 220, h: 200, minW: 150, minH: 150,
        description: "Work and break cycles, shared with the shell's own timer.", config: {} },
    { type: "notes", label: "Note", category: "productivity", icon: "sticky_note_2", file: "Notes.qml", w: 260, h: 220, minW: 140, minH: 100,
        description: "A sticky note. Click to type.",
        config: { mono: { type: "bool", label: "Monospace", default: false } } },
    { type: "todo", label: "To-do", category: "productivity", icon: "checklist", file: "Todo.qml", w: 280, h: 260, minW: 180, minH: 140,
        description: "A short checklist.",
        config: { title: { type: "text", label: "Title", default: "Today" }, clearDone: { type: "bool", label: "Hide finished", default: false } } },
    { type: "counter", label: "Daily counter", category: "productivity", icon: "exposure_plus_1", file: "Counter.qml", w: 200, h: 150, minW: 140, minH: 100,
        description: "Tap to count something each day, glasses of water or anything else.",
        config: { title: { type: "text", label: "What", default: "Water" }, goal: { type: "number", label: "Daily goal", default: 8, min: 1, max: 50, step: 1 } } },
    { type: "quote", label: "Quote", category: "productivity", icon: "format_quote", file: "Quote.qml", w: 340, h: 150, minW: 200, minH: 90,
        description: "A line to read, a new one each day.",
        config: { lines: { type: "text", label: "Your own lines (separated by |)", default: "" } } },

    { type: "quickLaunch", label: "Launcher", category: "utility", icon: "apps", file: "QuickLaunch.qml", w: 300, h: 90, minW: 120, minH: 60,
        description: "Buttons for the apps you open most.",
        config: { apps: { type: "text", label: "App ids (comma separated)", default: "" }, labels: { type: "bool", label: "Names", default: false } } },
    { type: "quickToggles", label: "Quick toggles", category: "utility", icon: "toggle_on", file: "QuickToggles.qml", w: 260, h: 80, minW: 160, minH: 56,
        description: "Mute, microphone and do not disturb.", config: {} },
    { type: "bluetooth", label: "Bluetooth devices", category: "utility", icon: "bluetooth", file: "BluetoothDevices.qml", w: 280, h: 150, minW: 180, minH: 80,
        description: "Connected devices and their battery.", config: {} },
    { type: "photo", label: "Photo", category: "utility", icon: "image", file: "Photo.qml", w: 260, h: 260, minW: 100, minH: 100,
        description: "A picture, or a folder of them shown in turn.",
        config: { path: { type: "text", label: "Image or folder path", default: "" }, minutes: { type: "number", label: "Change every (minutes)", default: 10, min: 1, max: 240, step: 1 },
            fit: { type: "enum", label: "Fit", default: "crop", values: ["crop", "fit"], labels: ["Fill", "Whole picture"] } } },
    { type: "greeting", label: "Greeting", category: "utility", icon: "waving_hand", file: "Greeting.qml", w: 380, h: 100, minW: 200, minH: 60,
        description: "Good morning, good evening, by name.",
        config: { name: { type: "text", label: "Name (empty uses your login)", default: "" } } },

    { type: "agents", label: "Agent sessions", category: "aphotic", icon: "smart_toy", file: "Agents.qml", w: 320, h: 180, minW: 220, minH: 100,
        description: "Every live coding agent, what it is doing and whether it waits for you." , config: {} },
    { type: "engines", label: "Local AI", category: "aphotic", icon: "neurology", file: "Engines.qml", w: 320, h: 160, minW: 220, minH: 90,
        description: "Local inference engines, the one in use and its models.", config: {} },
    { type: "signal", label: "Signal line", category: "aphotic", icon: "show_chart", file: "SignalPulse.qml", w: 400, h: 80, minW: 120, minH: 30,
        description: "A quiet line that lights when the machine works.",
        config: { source: { type: "enum", label: "Follows", default: "cpu", values: ["cpu", "gpu", "network", "agents"], labels: ["CPU", "GPU", "Network", "Agents"] } } }
];

function byType(type) {
    for (var i = 0; i < TYPES.length; i++)
        if (TYPES[i].type === type)
            return TYPES[i];
    return null;
}

function schemaOf(type) {
    var entry = byType(type);
    var schema = {};
    var keys = Object.keys(COMMON);
    for (var i = 0; i < keys.length; i++)
        schema[keys[i]] = COMMON[keys[i]];
    if (entry) {
        var own = Object.keys(entry.config || {});
        for (var j = 0; j < own.length; j++)
            schema[own[j]] = entry.config[own[j]];
    }
    return schema;
}

function defaultsOf(type) {
    var schema = schemaOf(type);
    var out = {};
    var keys = Object.keys(schema);
    for (var i = 0; i < keys.length; i++)
        out[keys[i]] = schema[keys[i]].default;
    return out;
}

function merged(type, config) {
    var out = defaultsOf(type);
    var keys = Object.keys(config || {});
    for (var i = 0; i < keys.length; i++)
        out[keys[i]] = config[keys[i]];
    return out;
}

function inCategory(category) {
    return TYPES.filter(function (t) { return t.category === category; });
}

function snap(value, grid) {
    return Math.round(value / grid) * grid;
}

function clampRect(rect, entry, screenW, screenH) {
    var w = Math.max(entry ? entry.minW : 60, Math.min(rect.w, screenW));
    var h = Math.max(entry ? entry.minH : 40, Math.min(rect.h, screenH));
    var x = Math.max(0, Math.min(rect.x, screenW - w));
    var y = Math.max(0, Math.min(rect.y, screenH - h));
    return { x: x, y: y, w: w, h: h };
}
