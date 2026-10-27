# KyleVNC manual clipboard patch

Based on RoyalVNCKit upstream revision `090b96eddeee183e9fec293c5cd881d302a4349d`.
The upstream MIT license in LICENSE remains applicable.

This fork exposes `VNCConnection.sendClipboardText(_:)` and a weak
`VNCClipboardDelegate` callback so an application can implement explicit Send,
Get, and opt-in shared text clipboard without the engine accessing the operating
system pasteboard. Keep `isClipboardRedirectionEnabled` false when using manual
integration. Callbacks arrive on the receive task; dispatch UI work appropriately.
The app remains responsible for observe mode, lifecycle, consent, and echo suppression.

Standard RFB text is ISO-8859-1; unsupported characters and text over 1 MiB throw
instead of silently sending an empty clipboard. A disconnected send also throws.
Incoming clipboard data is bounded to 1 MiB. Extended clipboard is not advertised;
unsolicited extended payloads are consumed fully and produce no text callback.
Rich text, image transfers, ARD proprietary clipboard, and UTF-8 extended clipboard
are not implemented by this patch.

Validation: `swift test --build-system native` passes five focused wire/parser
tests on macOS. Full KyleVNC app wire tests and Duo acceptance belong to the caller.
