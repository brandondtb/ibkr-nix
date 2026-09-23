# FHS environment wrappers for Interactive Brokers' proprietary Linux clients.
#
# Both apps are installed by IBKR's install4j installers into $HOME
# (~/.jts for TWS, ~/ntws for IBKR Desktop) and manage their own updates,
# so these wrappers deliberately only provide the runtime environment --
# they never need rebuilding when IBKR ships a new version.
#
# gpuWorkarounds covers two EGL/GLX fixes needed on NVIDIA and hybrid
# NVIDIA+AMD systems; they are harmless elsewhere but can be disabled if
# they ever interfere with a working single-vendor setup.
{
  pkgs,
  gpuWorkarounds ? true,
}:

let
  inherit (pkgs.lib) optionalString;

  targetPkgs =
    p: with p; [
      # X11
      libx11
      libxext
      libxi
      libxrender
      libxtst
      libxxf86vm
      libxcomposite
      libxdamage
      libxfixes
      libxrandr
      libxcb
      xcb-util-cursor
      xcbutilimage
      xcbutilkeysyms
      xcbutilrenderutil
      xcbutilwm
      libxkbfile

      # Graphics
      mesa
      libgbm
      cairo
      pango
      gdk-pixbuf
      gtk3

      # Browser (JxBrowser / Chromium)
      nss
      nspr
      cups
      dbus
      libdrm
      expat
      libxkbcommon
      libxshmfence

      # Text / fonts
      freetype
      fontconfig
      glib
      dejavu_fonts
      liberation_ttf

      # Audio
      alsa-lib
      pulseaudio

      # Accessibility
      at-spi2-core
      at-spi2-atk
      atk

      # Runtime
      gcc-unwrapped.lib
      glibc
      zlib
      zstd
      libglvnd
      krb5
      systemd
    ];

  # The sandbox binds the host's /etc/fonts (buildFHSEnv explicitly skips the
  # FHS env's own /etc/fonts), and NixOS's generated fonts.conf has no
  # /usr/share/fonts dir entry -- so fonts placed in the env via targetPkgs
  # are invisible. Worse, ~/.cache/fontconfig (shared with the host) holds
  # stale caches for /usr/share/fonts from *other* FHS envs, and store paths'
  # epoch mtimes make them look forever-valid. Referencing the font package's
  # unique store path avoids both problems: it is visible in the sandbox (/nix
  # is bound) and no foreign cache entry can exist for it.
  #
  # IBKR Desktop's UI font is Source Sans 3, but the installer only bundles
  # Regular + Semibold into ~/ntws/fonts. Qt asks fontconfig for every other
  # style (bold/italic/light), and without the family installed it falls back
  # to whatever the host default is -- visibly different metrics.
  fontConf = pkgs.writeText "ibkr-fonts.conf" ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
      <include>/etc/fonts/fonts.conf</include>
      <dir>${pkgs.source-sans}/share/fonts</dir>
    </fontconfig>
  '';

  installerCleanup = app: ''
    # Clean up desktop files created by the installer (these packages provide
    # their own)
    rm -f "$HOME/Desktop/${app}"*.desktop 2>/dev/null
    rm -f "$HOME/.local/share/applications/${app}"*.desktop 2>/dev/null
  '';

  ibkrDesktopItem = pkgs.makeDesktopItem {
    name = "ibkr-desktop";
    desktopName = "IBKR Desktop";
    comment = "Interactive Brokers desktop trading platform";
    exec = "ibkr-desktop";
    icon = "ibkr-desktop";
    terminal = false;
    type = "Application";
    categories = [
      "Office"
      "Finance"
    ];
  };

  twsDesktopItem = pkgs.makeDesktopItem {
    name = "tws";
    desktopName = "IB Trader Workstation";
    comment = "Interactive Brokers trading platform";
    exec = "tws";
    icon = "tws";
    terminal = false;
    type = "Application";
    categories = [
      "Office"
      "Finance"
    ];
  };
in
{
  tws = pkgs.buildFHSEnv {
    name = "tws";
    inherit targetPkgs;
    runScript = pkgs.writeShellScript "tws-launcher" ''
      export FONTCONFIG_FILE=${fontConf}
      export _JAVA_OPTIONS="''${_JAVA_OPTIONS:-} -Dawt.useSystemAAFontSettings=on -Dswing.aatext=true"
      JTS_DIR="$HOME/Jts"
      LATEST=$(ls -1d "$JTS_DIR"/[0-9]* 2>/dev/null | sort -V | tail -1)
      if [ -z "$LATEST" ]; then
        echo "No TWS installation found under $JTS_DIR" >&2
        echo "Run tws-install to install it." >&2
        exit 1
      fi
      exec "$LATEST/tws" "$@"
    '';
    extraInstallCommands = ''
      cp -r ${twsDesktopItem}/share $out/
    '';
    meta = {
      description = "Interactive Brokers Trader Workstation";
      mainProgram = "tws";
    };
  };

  ibkr-desktop = pkgs.buildFHSEnv {
    name = "ibkr-desktop";
    inherit targetPkgs;
    runScript = pkgs.writeShellScript "ibkr-desktop-launcher" ''
      export FONTCONFIG_FILE=${fontConf}

      # IBKR Desktop is Qt (QtJambi + QtWebEngine), not Swing, and it ships
      # its own Qt. KDE sessions export plugin/QML paths for the system Qt,
      # which the bundled Qt rejects at load time -- drop them so it only
      # ever looks at its own.
      unset QT_PLUGIN_PATH QML2_IMPORT_PATH QML_IMPORT_PATH
      unset QT_QPA_PLATFORMTHEME QT_STYLE_OVERRIDE

      # No wayland platform plugin is bundled, so go straight to xcb rather
      # than probing wayland first and failing.
      unset WAYLAND_DISPLAY
      export QT_QPA_PLATFORM=xcb

      ${optionalString gpuWorkarounds ''
      # libglvnd inside the FHS env only sees mesa's EGL ICD (the host
      # driver's lives under /run/opengl-driver/share, which glvnd does not
      # scan), so EGL silently falls back to software rendering on NVIDIA.
      export __EGL_VENDOR_LIBRARY_DIRS=/run/opengl-driver/share/glvnd/egl_vendor.d:/usr/share/glvnd/egl_vendor.d

      # Qt's default xcb GL integration is GLX, which is fragile on XWayland:
      # glvnd picks the nvidia GLX vendor first on hybrid GPU systems, and
      # when that vendor lib is broken (e.g. userspace rebuilt against a
      # newer driver than the loaded kernel module, pre-reboot) GLX context
      # creation fails outright -- the app shows the login window, then dies
      # with "Failed to create RHI". EGL's vendor-dir override above covers
      # both nvidia and mesa ICDs, so sidestep GLX entirely.
      export QT_XCB_GL_INTEGRATION=xcb_egl
      ''}

      export QTWEBENGINE_DISABLE_SANDBOX=1

      # The install4j launcher hardcodes verbose Qt debug logging routed
      # through java.util.logging. _JAVA_OPTIONS is applied after the command
      # line, so it wins.
      export _JAVA_OPTIONS="''${_JAVA_OPTIONS:-} -Dio.qt.debug=false -Dio.qt.log-messages=CRITICAL,FATAL"

      NTWS_DIR="$HOME/ntws"
      if [ -x "$NTWS_DIR/ntws" ]; then
        exec "$NTWS_DIR/ntws" "$@"
      fi

      # Fallback: search under ~/Jts for ntws
      JTS_DIR="$HOME/Jts"
      NTWS=$(find "$JTS_DIR" -maxdepth 2 -name "ntws" -type f 2>/dev/null | head -1)
      if [ -n "$NTWS" ]; then
        exec "$NTWS" "$@"
      fi

      echo "No IBKR Desktop installation found under $NTWS_DIR." >&2
      echo "If an update recently failed, check $NTWS_DIR/.install4j/updater.log." >&2
      echo "Recovery: run ibkr-desktop-install to install the latest version." >&2
      exit 1
    '';
    extraInstallCommands = ''
      cp -r ${ibkrDesktopItem}/share $out/
    '';
    meta = {
      description = "Interactive Brokers IBKR Desktop";
      mainProgram = "ibkr-desktop";
    };
  };

  ibkr-desktop-install = pkgs.buildFHSEnv {
    name = "ibkr-desktop-install";
    targetPkgs = p: (targetPkgs p) ++ [ p.curl ];
    runScript = pkgs.writeShellScript "ibkr-desktop-install-launcher" ''
      NTWS_INSTALLER_URL="https://download2.interactivebrokers.com/installers/ntws/latest-standalone/ntws-latest-standalone-linux-x64.sh"

      if [ -n "$1" ]; then
        chmod +x "$1"
        exec "$1"
      fi

      TMPDIR="$(mktemp -d)"
      INSTALLER="$TMPDIR/ntws-install.sh"
      echo "Downloading IBKR Desktop installer..."
      curl -fSL -o "$INSTALLER" "$NTWS_INSTALLER_URL"
      chmod +x "$INSTALLER"
      "$INSTALLER"

      ${installerCleanup "IBKR Desktop"}
    '';
    meta = {
      description = "FHS environment for installing Interactive Brokers IBKR Desktop";
      mainProgram = "ibkr-desktop-install";
    };
  };

  tws-install = pkgs.buildFHSEnv {
    name = "tws-install";
    targetPkgs = p: (targetPkgs p) ++ [ p.curl ];
    runScript = pkgs.writeShellScript "tws-install-launcher" ''
      TWS_INSTALLER_URL="https://download2.interactivebrokers.com/installers/tws/latest-standalone/tws-latest-standalone-linux-x64.sh"

      if [ -n "$1" ]; then
        chmod +x "$1"
        exec "$1"
      fi

      TMPDIR="$(mktemp -d)"
      INSTALLER="$TMPDIR/tws-install.sh"
      echo "Downloading TWS installer..."
      curl -fSL -o "$INSTALLER" "$TWS_INSTALLER_URL"
      chmod +x "$INSTALLER"
      "$INSTALLER"

      ${installerCleanup "Trader Workstation"}
    '';
    meta = {
      description = "FHS environment for installing Interactive Brokers TWS";
      mainProgram = "tws-install";
    };
  };
}
