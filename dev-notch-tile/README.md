# Dev Notch Tile

Docks a tile into Aphotic's notch for the Dev profile:

- The open project's name and path, as detected when a project is opened
  from the launcher.
- The profile's current lifecycle phase, straight off the Profile Engine.
- Any resource claims the Dev profile holds.

The Dev profile itself — detection, lifecycle, claims — is part of the
`dev` layer and works with this plugin absent. This is only its notch
surface.

## Requirements

- The `dev` layer installed (`requires_layer = "dev"`).

## Install

```sh
aphotic plugin install dev-notch-tile
```
