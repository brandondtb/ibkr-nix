# ibkr-nix

Nix flake providing FHS-environment launchers for Interactive Brokers'
proprietary Linux clients: **IBKR Desktop** (ntws) and **Trader Workstation**
(TWS).

Nothing for these apps exists in nixpkgs. Because IBKR ships installers that
self-update, these wrappers deliberately provide only the *runtime
environment* (libraries, fonts, graphics workarounds) and never pin or wrap
the application itself -- they keep working across IBKR's ~monthly releases
without any rebuilds.

## Packages

| Package | Purpose |
|---|---|
| `ibkr-desktop` | Launcher for IBKR Desktop (Qt-based, next-gen client) |
| `ibkr-desktop-install` | Downloads and runs the latest IBKR Desktop installer |
| `tws` | Launcher for Trader Workstation (Java/Swing client) |
| `tws-install` | Downloads and runs the latest TWS installer |

## Usage

### Flake input + Home Manager

```nix
# flake.nix
inputs.ibkr-nix.url = "github:YOURUSER/ibkr-nix";
```

```nix
# Home Manager configuration
imports = [ inputs.ibkr-nix.homeManagerModules.default ];

programs.ibkr = {
  enable = true;
  desktop.enable = true;   # ibkr-desktop + ibkr-desktop-install (default)
  tws.enable = false;      # tws + tws-install
};
```

### Ad hoc

```console
$ nix run github:YOURUSER/ibkr-nix#ibkr-desktop-install   # first time: install the app
$ nix run github:YOURUSER/ibkr-nix                         # then: launch it
```

## First run and updates

The wrappers do not contain the applications. On first use, run
`ibkr-desktop-install` (or `tws-install`) from within a graphical session;
the install4j wizard installs to `~/ntws` (or `~/Jts`).

IBKR auto-updates the installation in place on launch. If an update fails
mid-flight it can tear the installation, after which `ibkr-desktop` will
report no installation found -- check `~/ntws/.install4j/updater.log` and
recover by running `ibkr-desktop-install` again.

## Environment notes (why the wrappers look the way they do)

- **X11/XWayland required.** IBKR Desktop bundles its own Qt without a
  wayland plugin, so the launcher forces `QT_QPA_PLATFORM=xcb`. TWS is
  Swing and needs an X display too.
- **EGL instead of GLX.** On NVIDIA and hybrid systems, GLX context
  creation via glvnd is fragile (a driver userspace/kernel mismatch makes it
  fail outright); the launcher points glvnd's EGL vendor dir at the host
  driver and forces Qt's xcb-EGL integration. Both cover nvidia and mesa.
  Disable via `programs.ibkr.desktop.gpuWorkarounds = false` if unwanted.
- **Source Sans 3.** The IBKR Desktop installer bundles only Regular and
  Semibold of its UI font; every other style resolves through fontconfig.
  The launcher injects a `FONTCONFIG_FILE` that layers the full family (by
  store path -- avoids stale shared fontconfig caches for `/usr/share/fonts`
  from other FHS envs) on top of the host configuration.
- **TWS text rendering on Wayland sessions.** Under some Wayland compositors
  (observed with KDE Plasma 6 + XWayland), all Java/Swing apps -- not just
  TWS -- render bilevel (aliased) text. This is a JDK-level issue outside
  the wrapper's control; TWS in an X11 session renders normally.

## Requirements

- x86_64-linux
- A graphical session (X11, or Wayland with XWayland)

## License

The nix expressions in this repository are MIT licensed. The Interactive
Brokers software they wrap is proprietary and subject to IBKR's terms; it is
downloaded at install time, never redistributed here.
