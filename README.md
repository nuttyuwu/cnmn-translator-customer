# MN AutoCAD Translator

Customer installer for AutoCAD 2024–2027 on Windows. This repository contains
compiled software and installation scripts only. No source project, signing key,
developer tools, or full project glossary is distributed here.

1. Download this repository as a ZIP and extract it, or clone it.
2. Close AutoCAD. Double-click **Install.cmd**.
3. The activation window opens. Click **Copy machine ID** and send it to Khongor
   at ebatkhongor@gmail.com.
4. When you receive your licence, open the `.lic` file in that window or paste
   its complete text, then click **Activate**.
5. Start AutoCAD, allow the plug-in to load if prompted, and run **MNTRANSLATE**.

No administrator rights, GitHub credentials, developer SDK or separate .NET
runtime are required. Downloading or cloning alone does not execute an installer.

You can close the activation window and reopen it with **Activate-Licence.cmd**.
Inside AutoCAD, **MNLICENSE** also shows your machine ID and imports licences.
Licences work offline and are tied to the issued machine and expiry date.

For updates, download or pull the latest package, close AutoCAD, and run
**Install.cmd** again. The installer retains existing glossary/settings data
and a rollback bundle. Run **Rollback-CmnCadTranslator.ps1** if needed.

Only a small generic glossary is included. Supply terminology you are authorized
to use. A SHA-256 checksum detects damaged or mismatched downloads; it is not a
digital signature. Obtain this package from the repository supplied by Khongor.
