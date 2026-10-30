"""Patch desktop_webview_window's Linux source for the libsoup/GLib on CI.

soup_cookie_get_expires() returns a SoupDate (libsoup 2.4, Ubuntu 22.04),
not a GDateTime. Run after `flutter pub get` and before `flutter build linux`.
Idempotent: a second run sees the patch and does nothing.
"""

import sys
from pathlib import Path

PATH = Path("linux/flutter/ephemeral/.plugin_symlinks/desktop_webview_window/linux/webview_window.cc")
OLD = "    gdouble expires = g_date_time_get_seconds(soup_cookie_get_expires(cookie));"
NEW = ("    SoupDate *expires_date = soup_cookie_get_expires(cookie);\n"
       "    gdouble expires = expires_date == nullptr\n"
       "                           ? -1\n"
       "                           : static_cast<gdouble>(soup_date_to_time_t(expires_date));")


def main() -> int:
    source = PATH.read_text()
    if OLD in source:
        PATH.write_text(source.replace(OLD, NEW, 1))
        print("patched desktop_webview_window cookie expiry")
    elif "SoupDate *expires_date = soup_cookie_get_expires(cookie);" in source:
        print("desktop_webview_window already patched")
    elif "soup_cookie_get_expires" not in source:
        # Versions without the cookie API (e.g. 0.2.3) don't need the patch.
        print("desktop_webview_window has no cookie expiry code; nothing to patch")
    else:
        print("desktop_webview_window cookie expiry source changed; review the patch")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
