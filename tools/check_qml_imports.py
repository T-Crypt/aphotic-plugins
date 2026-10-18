#!/usr/bin/env python3
"""Fail a plugin QML file that uses a core singleton without importing its module.

A missing `import qs.services` does not stop a file from loading: every
binding that names `Colours` throws a ReferenceError and the property falls
back to its default, so the surface renders black with no other sign.

Core singletons are found by `pragma Singleton` under the shell root, and
each one's module is `qs.` plus its directory. Usage:

    check_qml_imports.py [--shell-root DIR] [PLUGIN_DIR ...]

With no plugin directories, every plugin in this repo is checked.
"""
import argparse
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMPORT = re.compile(r"^\s*import\s+(qs(?:\.[A-Za-z0-9_]+)+)\s*$", re.M)
COMMENT_LINE = re.compile(r"//[^\n]*")
COMMENT_BLOCK = re.compile(r"/\*.*?\*/", re.S)
STRING = re.compile(r"\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`")


def default_shell_root():
    env = os.environ.get("APHOTIC_SHELL_ROOT")
    if env:
        return env
    linked = os.path.expanduser("~/.config/quickshell/aphotic")
    return os.path.realpath(linked) if os.path.exists(linked) else ""


def core_singletons(shell_root):
    found = {}
    for base, dirs, files in os.walk(shell_root):
        rel = os.path.relpath(base, shell_root)
        parts = [] if rel == "." else rel.split(os.sep)
        if parts[:2] == ["modules", "plugins"] or any(p.startswith(".") for p in parts):
            dirs[:] = []
            continue
        for name in files:
            if not name.endswith(".qml") or not name[0].isupper():
                continue
            with open(os.path.join(base, name), encoding="utf-8", errors="replace") as fh:
                head = fh.read(2048)
            if not re.search(r"^\s*pragma\s+Singleton\b", head, re.M):
                continue
            module = "qs" if rel == "." else "qs." + rel.replace(os.sep, ".")
            found.setdefault(name[:-4], set()).add(module)
    return found


def strip(text):
    text = COMMENT_BLOCK.sub("", text)
    text = STRING.sub('""', text)
    return COMMENT_LINE.sub("", text)


def local_names(plugin_dir):
    names = set()
    for base, _, files in os.walk(plugin_dir):
        names.update(f[:-4] for f in files if f.endswith(".qml"))
    return names


def check_file(path, singletons, own):
    with open(path, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    imported = set(IMPORT.findall(text))
    body = strip(text)
    problems = []
    for name, modules in sorted(singletons.items()):
        if name in own or not re.search(r"(?<![\w.])%s\s*\." % re.escape(name), body):
            continue
        if imported & modules:
            continue
        problems.append("%s uses %s without importing %s" % (os.path.relpath(path, REPO), name, " or ".join(sorted(modules))))
    return problems


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--shell-root", default=default_shell_root())
    parser.add_argument("plugins", nargs="*")
    args = parser.parse_args()
    if not args.shell_root or not os.path.isdir(os.path.join(args.shell_root, "services")):
        print("SKIP: no core shell found; set APHOTIC_SHELL_ROOT")
        return 0
    singletons = core_singletons(args.shell_root)
    plugins = args.plugins or sorted(
        os.path.join(REPO, d) for d in os.listdir(REPO)
        if os.path.isfile(os.path.join(REPO, d, "plugin.toml")))
    problems = []
    for plugin in plugins:
        own = local_names(plugin)
        for base, _, files in os.walk(plugin):
            for name in files:
                if name.endswith(".qml"):
                    problems += check_file(os.path.join(base, name), singletons, own)
    for line in problems:
        print("FAIL: " + line)
    if problems:
        return 1
    print("PASS: %d plugins import every core singleton they use" % len(plugins))
    return 0


if __name__ == "__main__":
    sys.exit(main())
