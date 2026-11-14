# A18Break RW Probe (iPhone 16 · iOS 27.0.1)

This is an **unsigned IPA app** to measure real POSIX read/write results on the installed iPhone. It is not a jailbreak, and does not include a sandbox escape or a kernel exploit.

1. Download the `A18BreakRW-unsigned-ipa` artifact from the GitHub Actions build on this branch.
2. Sign/install the IPA with SideStore.
3. Open **A18Break RW Probe**, tap **Run real R/W checks**, then **Prepare JSON for researcher** and **Share JSON report**.
4. Review the report and redact identifying data before sending to the Dopamine developer.

The app opens fixed directories for reading and, where possible, attempts an **exclusive-create** temporary marker file. It reads back exact bytes and deletes the marker. No existing system file is opened for writing. Each denied operation reports POSIX errno. App Documents is a positive control.

**Don't confuse a directory listing with a sandbox escape.** Expanded write results, if any, require independent validation. The app never claims kernel read/write.