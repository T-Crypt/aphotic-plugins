// SPDX-License-Identifier: GPL-3.0-or-later
// SPDX-FileCopyrightText: 2023-2026 Trevin Tindall (T-Crypt) and Aphotic-Hypr contributors

pragma ComponentBehavior: Bound

import QtQuick
import qs.components
import qs.services

// The three rising z's a pet shows while it naps.
//
// Placed outside whatever container carries the facing flip, in every pet
// that uses it: the flip is a horizontal mirror, and a mirrored glyph
// reads as a rendering fault rather than a pet facing the other way.
Item {
    id: root

    required property bool asleep

    implicitWidth: 32
    implicitHeight: 30

    Repeater {
        model: 3

        StyledText {
            id: snooze

            required property int index

            x: snooze.index * 9
            y: 20 - snooze.index * 9
            text: "z"
            color: Colours.palette.m3onSurfaceVariant
            opacity: root.asleep ? 0.8 - snooze.index * 0.22 : 0
            font.pixelSize: 11 + snooze.index * 2

            Behavior on opacity {
                Anim {
                    type: Anim.SlowEffects
                }
            }
        }
    }
}
