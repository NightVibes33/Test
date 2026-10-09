# SonicLab FLAC Studio

Convert MP3 and other supported audio files to real FLAC locally in the browser. Includes 16/24-bit output, sample-rate controls, optional enhancement, normalization, and iPhone-compatible sharing.

[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https%3A%2F%2Fgithub.com%2FNightVibes33%2FTest%2Ftree%2Fmain%2Fsoniclab-flac-studio&project-name=soniclab-flac-studio&repository-name=soniclab-flac-studio)

**[Open the preconfigured Vercel install page](https://vercel.com/new/clone?repository-url=https%3A%2F%2Fgithub.com%2FNightVibes33%2FTest%2Ftree%2Fmain%2Fsoniclab-flac-studio&project-name=soniclab-flac-studio&repository-name=soniclab-flac-studio)**

The source is in `NightVibes33/Test/soniclab-flac-studio`. The one-click installer uses this subdirectory as the template, preselects `soniclab-flac-studio` as both project and repository name, and requires no environment variables or backend. Sign in to Vercel and authorize the Git provider to complete deployment. The template wizard makes a dedicated repository copy; it does **not** deploy your original `Test` repository in place.

### To deploy and keep the original Test repository connected

Open [Vercel New Project](https://vercel.com/new), import **NightVibes33/Test**, and in Project Settings select **Root Directory: `soniclab-flac-studio`**. Select **Other** as Framework Preset (or leave autodetected) and deploy. No build command or output directory is needed. Future changes under this subdirectory can deploy automatically.

### Files

- `index.html`: actual converter UI and on-device FLAC encoder
- `install.html`: dedicated installer launch page
- `vercel.json`: static-site configuration

**Audio quality:** Conversion to FLAC prevents *further* lossy encoding but cannot reconstruct information already discarded by MP3 compression.

### iPhone 16 / iOS 27 export notes

- The **Download .flac** button exports a complete 24-bit or 16-bit FLAC. Use a player that can open FLAC files; a missing thumbnail or Files preview does **not** establish that the file is silent.
- The **Save playable 16-bit WAV on iPhone** button provides the full processed song as broadly compatible PCM WAV using the iOS share sheet when available.
- SonicLab checks frame CRCs and writes the FLAC PCM MD5 fingerprint before enabling downloads. It uses a short WAV preview to avoid misleading playback errors from embedded audio players.
- A real 93.53-second, 44.1-kHz stereo MP3 was converted in the browser; the exported 20 MB / 24-bit FLAC passed `flac -t`, and the 16-bit WAV export decoded successfully. Browser validation was performed in headless Chromium, **not** on an actual iPhone.
- Processing and conversion run in-browser; user audio is not uploaded to this repository or server.
