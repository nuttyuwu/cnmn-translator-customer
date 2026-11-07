# CMN AutoCAD Translator

Customer package **0.6.2** for Windows and AutoCAD 2024–2027.

Download this repository with **Code → Download ZIP**, extract it, and double-click
**Install.cmd**. In the setup window, choose **Install bundled version** after
closing AutoCAD. Keep CMNSetup.exe and CMN.Payload.zip together; setup reads
the inner ZIP automatically. No Git, compiler, .NET SDK or GitHub sign-in is needed.

This repository contains compiled software, installer/support scripts and release
metadata. Application source, licence issuer tools, private keys, API keys and
private project glossaries are excluded. Compiled .NET software can still be
decompiled; this package does not claim to prevent reverse engineering.

This is the newer v0.6 product line: it has no licence activation or expiry gate.
The six-word starter glossary is intentionally small. Import your approved
company glossary using the setup manager, or run **MNTERMS** in AutoCAD to select
a project glossary and discipline. AI translation still requires your own
provider configuration and API key; the offline glossary mode needs neither.

Approved terms are locked exactly, with longer approved phrases taking priority.
AI fills only uncovered Chinese text. **MNGLOSSARYAUDIT** writes one list of
duplicate, conflicting or overridden terms; ambiguous mappings are blocked.

Review workbooks show source, English, draft, final, approval and occurrence count.
Drawing IDs and technical details are hidden. Repeated text in the same context
can be approved once. Use Excel **Data → Clear** to show all rows. Set approval
to **Y**, then use **MNIMPORT** to apply or **MNMERGE** to learn the wording.
Keep the workbook in its original project folder so its scope can be verified.

**Update.cmd** opens the setup manager. Online update checks use this public
repository's GitHub Releases; a repo update alone is not a published Release.
Until a Release is published, download the current package here and install its
bundled version. Existing company/project glossaries are preserved on update.
**Rollback.cmd** restores a retained version. **Uninstall.cmd** removes this
product and its local data after confirmation; export your glossary first.

SHA-256 files detect download corruption; they are **not digital signatures**.
Run **MNVERSION** when requesting support. Send drawings or glossaries only
through your company's approved support channel.
