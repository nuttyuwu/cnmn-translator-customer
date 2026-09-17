# MN AutoCAD Translator

Customer installer for AutoCAD 2024–2027 on Windows. This repository contains
compiled software and installation scripts only. No source project, signing key,
developer tools, or full project glossary is distributed here.

1. Download this repository as a ZIP and extract it, or clone it.
2. Close AutoCAD. Double-click **Install.cmd**.
3. The activation window opens. Click **Copy machine ID** and send it to Khongor
   at ebatkhongor@gmail.com.
4. When you receive your activation key by message, paste it into the window
   and click **Activate**. No licence file needs to be sent.
5. For AI translation, paste your Alibaba Model Studio **Qwen API key** in the
   same window. Select the region where you created the key, then click
   **Save Qwen setup** and **Check connection**. For a workspace-specific key,
   select Custom workspace endpoint and paste its OpenAI-compatible URL.
6. Start AutoCAD, allow the plug-in to load if prompted, and run **MNTRANSLATE**
   for glossary-only translation or **MNTRANSLATEAI** to use Qwen.

No administrator rights, GitHub credentials, developer SDK or separate .NET
runtime are required. Downloading or cloning alone does not execute an installer.

You can close the activation window and reopen it with **Activate-Licence.cmd**.
Inside AutoCAD, **MNSETUP** opens activation and Qwen setup; **MNLICENSE** also
shows your machine ID, imports licences and has a Qwen setup button.
Keys work offline, are tied to the issued machine, and expire **one month or one
year** from issuance, as selected by Khongor. The expiry date is inclusive.
Existing `.lic` files still work.

The Qwen key is encrypted for your Windows account, outside the installation,
and is never stored in a plaintext environment variable by this setup. Other
software running as you, or an administrator controlling your account, can still
recover it. Do not share your key. The connection check sends no drawing data;
AI translation sends drawing text to your selected Qwen service and requires
its model access and quota. See [Alibaba Model Studio setup](https://www.alibabacloud.com/help/en/model-studio/text-generation).

For updates, download or pull the latest package, close AutoCAD, and run
**Install.cmd** again. The installer retains existing glossary/settings data
and a rollback bundle. Run **Rollback-CmnCadTranslator.ps1** if needed.

To remove the product, close AutoCAD and double-click **Uninstall.cmd**. Confirm
once to delete the installed bundle, rollback copies, activation licence, saved
Qwen key, settings, logs and **all local glossaries**. Export glossaries you need
first. It also removes the current user's legacy DASHSCOPE_API_KEY and CNMN
environment settings; other applications using that same variable will need
their own key configured again. Downloaded installer files, drawing files and
custom files outside the translator's standard data folder are retained.

Only a small generic glossary is included. Supply terminology you are authorized
to use. A SHA-256 checksum detects damaged or mismatched downloads; it is not a
digital signature. Obtain this package from the repository supplied by Khongor.
