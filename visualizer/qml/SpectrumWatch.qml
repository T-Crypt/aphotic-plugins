// SPDX-License-Identifier: GPL-3.0-only
// SPDX-FileCopyrightText: Aphotic-Hypr contributors

import QtQuick
import qs.modules.plugins.visualizer

// Mount this for as long as a surface is actually drawing the spectrum.
// Object lifetime is the registration, so a surface behind a Loader
// cannot leak a watch by missing an unpaired call -- the same shape
// core's SystemUsageWatch and ProcessUsageWatch use.
QtObject {
    Component.onCompleted: CavaSpectrum.subscribe()
    Component.onDestruction: CavaSpectrum.unsubscribe()
}
