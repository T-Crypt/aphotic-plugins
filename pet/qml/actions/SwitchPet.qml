// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

import QtQuick
import qs.modules.plugins.pet

// Headless: switches to the next pet once in `Component.onCompleted` and
// draws nothing. The shell builds it, lets it run and tears it down in
// the same call -- see the core Actions singleton.
//
// Cycles the pets that travel with the plugin (built-in and bundled), not
// the ones a user imported under ~/.config/aphotic/pets: those are found
// by a FolderListModel the settings pane owns, and an action that fires
// and dies has nothing to wait on a directory scan with. The picker in
// Settings is where an imported pet is chosen.
QtObject {
    Component.onCompleted: {
        const choices = PetLibrary.builtins.map(b => b.id).concat(PetLibrary.bundled.map(b => b.id));
        if (choices.length < 2)
            return;
        // "default" is what a pre-1.3 settings file says and it means the
        // fallback built-in, so cycling from it starts where that pet is
        // rather than at the top of the list.
        const current = PetLibrary.selected === "default" ? PetLibrary.fallbackBuiltin : PetLibrary.selected;
        const i = choices.indexOf(current);
        PetLibrary.setPet(choices[(i + 1) % choices.length]);
    }
}
