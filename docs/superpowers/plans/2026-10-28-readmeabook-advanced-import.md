# ReadMeABook Advanced Import Plan

## Steps

1. Add the English localization strings for the Advanced Import books action and regenerate Flutter localization output.
2. Add an Advanced-only Import books tile in `SettingsScreen` that opens the existing ReadMeABook search/request sheet when configured, or the existing connection sheet when it is not configured.
3. Hide ReadMeABook shortcuts from the navigation hold picker and default launcher menu while leaving the existing API and request sheets intact.
4. Add focused tests for the navigation filtering and run the existing RMAB/service tests.
5. Run formatting, focused tests, the full test suite, `flutter analyze`, and a Windows release build.

## Verification

- Existing ReadMeABook configuration and request behavior remains unchanged.
- Import books is only visible in Settings → Advanced.
- No RMAB navigation shortcut is offered or retained in the default launcher menu.
- A disconnected RMAB account never exposes the import action.
