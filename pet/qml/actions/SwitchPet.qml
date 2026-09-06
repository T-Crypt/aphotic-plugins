// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

import QtQuick
import qs.modules.plugins.pet

// Headless: switches to the next pet once in `Component.onCompleted` and
// draws nothing. The shell builds it, lets it run and tears it down in
// the same call -- see the core Actions singleton.
//
// Cycles the pets that travel with the plugin, not the ones a user
// imported under ~/.config/aphotic/pets: those are found
// by a FolderListModel the settings pane owns, and an action that fires
// and dies has nothing to wait on a directory scan with. The picker in
// Settings is where an imported pet is chosen.
QtObject {
    Component.onCompleted: {
        const choices = PetLibrary.bundled.map(b => b.id);
        if (choices.length < 2)
            return;
        // `selected` has already resolved "default" and every retired id
        // to a real one, so cycling starts from the pet actually on the
        // desktop rather than at the top of the list.
        const i = choices.indexOf(PetLibrary.selected);
        PetLibrary.setPet(choices[(i + 1) % choices.length]);
    }
}
