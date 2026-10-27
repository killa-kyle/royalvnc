# KyleVNC manual clipboard patch

Based on RoyalVNCKit upstream revision `090b96eddeee183e9fec293c5cd881d302a4349d`.
The upstream MIT license in LICENSE remains applicable.

This fork exposes `VNCConnection.sendClipboardText(_:)` and a weak
`VNCClipboardDelegate` callback so an application can implement explicit Send,
Get, and opt-in shared text clipboard without the engine accessing the operating
system pasteboard. Keep `isClipboardRedirectionEnabled` false when using manual
integration. Callbacks arrive on the receive task; dispatch UI work appropriately.
The app remains responsible for observe mode, lifecycle, consent, and echo suppression.

Standard-only servers retain ISO-8859-1 behavior: Unicode is rejected before
negotiation. The client advertises Extended Clipboard and activates UTF-8 only
after receiving server CAPS. CAPS sizes, NOTIFY, REQUEST, PEEK and zlib-compressed
PROVIDE text follow the public RFB specification. Text terminates with NUL and
uses CRLF on the wire; callbacks normalize to LF. Only plain text is advertised.

Incoming compressed payload, aggregate format bytes, and outgoing text are bounded
to 1 MiB. Inflation uses a fixed destination with room for at most 16 format length
fields, rejects oversized output, malformed UTF-8, missing terminators, truncated
payloads, trailing data, and concatenated zlib streams. No unbounded inflation occurs.
Unsupported formats are parsed under the same bound but never published as text.

`clearLocalClipboardText()` revokes cached explicitly supplied clipboard content:
call it on observe mode, background, or sharing revocation so later server REQUEST
messages cannot retrieve old local data. Disconnect resets all extension state.
The fork does not implement rich text, image transfers, or ARD proprietary clipboard.

Validation: `swift test --build-system native` passes 11 tests, including a real
loopback Unicode RFB CAPS/NOTIFY/REQUEST/PROVIDE exchange, codec/action tests, standard
Latin1 framing, malformed/truncated data, and bounded inflation-bomb rejection.
Full KyleVNC app/Duo acceptance belongs to the caller.

Protocol sources (consulted as behavioral documentation; no TigerVNC implementation
code copied):
- https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst (Extended Clipboard)
- https://github.com/TigerVNC/tigervnc/blob/master/common/rfb/CConnection.cxx
- https://github.com/TigerVNC/tigervnc/blob/master/common/rfb/CMsgWriter.cxx
