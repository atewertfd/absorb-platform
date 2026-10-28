# Windows beta distribution and update plan

## Goal

Publish the current Windows build as a GitHub pre-release and make both the
installer and the installed app update safely without replacing user data.

## Scope

1. Extend the existing GitHub release asset selection to understand Windows
   installer `.exe` assets as well as Android APK assets.
2. Add a Windows update path that downloads the selected installer to a
   temporary location, starts it, and exits Absorb so Inno Setup can update the
   installed files.
3. Keep the existing Android updater behavior unchanged.
4. Expose update checking and the pre-release channel setting on the Windows
   GitHub build.
5. Make the Inno Setup upgrade behavior explicit: stable `AppId`, reuse the
   previous install directory, close/restart the app when updating, and leave
   user data outside the install directory untouched.
6. Add a manually-triggered Windows GitHub Actions release workflow that builds
   the installer and portable ZIP, then publishes a pre-release by default.
7. Bump the beta build number and publish the resulting pre-release after the
   repository changes are pushed.

## Safety and compatibility

- Only the official repository's GitHub release API and release assets are used.
- Stable releases remain the default channel; pre-releases are opt-in.
- The updater never modifies Audiobookshelf server data.
- Inno Setup's fixed application ID prevents a second parallel install and
  routes an update through the normal Windows uninstall/repair registration.
- Verification will include static checks, YAML inspection, repository status,
  and the GitHub Actions result. A local Flutter build is attempted only if the
  toolchain is available.
