# direnv Notice

Notifies you when a project opened from
[Aphotic-Hypr](https://github.com/T-Crypt/aphotic-hypr)'s launcher `@`
project-switcher has an `.envrc`, so you know to review/allow it.

## Requires

- `notify-send` (`libnotify`, already part of the shell's own
  notification pipeline).

## What it does

On every project switch (`@` mode in the launcher), checks whether the
project's directory has an `.envrc`. If it does, sends a desktop
notification reminding you to run `direnv allow` there.

This deliberately does **not** run `direnv allow` on your behalf --
that would defeat the point of direnv's per-directory trust step (an
`.envrc` can contain arbitrary shell code). It just makes an unreviewed
`.envrc`'s presence visible right when you jump into a project, instead
of only finding out from direnv's own shell-hook error the first time a
command runs there.

## Install

```sh
git clone https://github.com/T-Crypt/aphotic-plugins ~/aphotic-plugins
aphotic plugin install direnv
```

Or for plugin development (edits take effect without reinstalling):

```sh
aphotic plugin install direnv --link
```
