# ReadMeABook Advanced Import

## Goal

Keep the optional ReadMeABook integration out of the normal browsing experience while making it easy to choose audiobook requests from inside Absorb Plus.

## User flow

1. Open Settings → Advanced.
2. Configure ReadMeABook once with its server URL and API token.
3. Select Import books.
4. Search for a title or author.
5. Choose a result and send the request.
6. Track the request in My Requests until ReadMeABook reports it available.

## Important boundary

ReadMeABook is the downloader/importer and already writes completed media into the Audiobookshelf library. Absorb Plus will not copy files from ReadMeABook storage or expose filesystem paths. The integration uses ReadMeABook's supported API for search, request creation, and request status.

## UI placement

- Keep the existing ReadMeABook connection tile in Settings → Advanced.
- Add a separate Import books action there, shown only after a valid connection exists.
- Remove ReadMeABook entries from the optional navigation hold menu so the feature is not surfaced elsewhere.
- Leave the regular Home, Library, and player UI unchanged.

## Security and failure behavior

- Keep the API token in the existing scoped preference storage.
- Do not log the token or send it to any endpoint other than the configured ReadMeABook server.
- Reuse existing error handling for connection, authorization, and request failures.
- If the connection is removed, the Import books action disappears and the user can reconnect from the connection tile.
