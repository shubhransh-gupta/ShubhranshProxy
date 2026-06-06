# Release ShubhranshProxy (DMG + download page)

This guide covers building a `.dmg`, publishing it on GitHub Releases, and deploying the public download page on GitHub Pages.

---

## 1. Build the DMG locally

From the project root:

```bash
chmod +x Scripts/build-dmg.sh
./Scripts/build-dmg.sh
```

Output:

```text
build/release/ShubhranshProxy.dmg
build/release/ShubhranshProxy-1.0.dmg
```

The script builds **Release**, copies the app into a DMG, and adds an **Applications** shortcut.

---

## 2. Test the DMG on your Mac

1. Double-click `ShubhranshProxy.dmg`
2. Drag the app to **Applications**
3. Open it

If macOS says the app is from an unidentified developer (expected without notarization):

- **System Settings → Privacy & Security → Open Anyway**, or
- Terminal: `xattr -cr /Applications/ShubhranshProxy.app`

---

## 3. Sign & notarize (recommended for public downloads)

Without notarization, many users will see Gatekeeper warnings.

Requirements:

- [Apple Developer Program](https://developer.apple.com/programs/) ($99/year)
- Developer ID Application certificate in Keychain
- App-specific password for notarytool

Typical flow:

```bash
# 1) Archive in Xcode: Product → Archive
# 2) Export → Developer ID → copy ShubhranshProxy.app

# 3) Sign
codesign --force --options runtime --deep --sign "Developer ID Application: Your Name (TEAMID)" ShubhranshProxy.app

# 4) Create DMG (use Scripts/build-dmg.sh or create-dmg)

# 5) Notarize DMG
xcrun notarytool submit ShubhranshProxy-1.0.dmg \
  --apple-id "you@email.com" \
  --team-id "TEAMID" \
  --password "app-specific-password" \
  --wait

# 6) Staple ticket
xcrun stapler staple ShubhranshProxy-1.0.dmg
```

Set your **Development Team** in Xcode → Target → Signing & Capabilities before archiving.

---

## 4. Publish to GitHub Releases

The download page links to the **latest release** asset `ShubhranshProxy.dmg` (stable filename — no HTML edits needed on each version bump).

### One command (build + release)

```bash
chmod +x Scripts/publish-release.sh
./Scripts/publish-release.sh v1.0.0 "First public release"
```

This runs `build-dmg.sh`, then uploads:

- `ShubhranshProxy.dmg` — used by the download button
- `ShubhranshProxy-1.0.dmg` — versioned copy for reference

### Manual steps

```bash
./Scripts/build-dmg.sh

gh release create v1.0.0 \
  build/release/ShubhranshProxy.dmg \
  build/release/ShubhranshProxy-1.0.dmg \
  --title "ShubhranshProxy 1.0" \
  --notes "First public release"
```

Download URL (always points to latest):

`https://github.com/shubhransh-gupta/ShubhranshProxy-downloads/releases/latest/download/ShubhranshProxy.dmg`

---

## 5. Deploy the download page (GitHub Pages)

The landing page lives in [`web/index.html`](../web/index.html).

### First-time setup

1. Push the repo to GitHub:
   ```bash
   git remote add origin https://github.com/shubhransh-gupta/ShubhranshProxy.git
   git push -u origin main
   ```
2. Enable Pages: **Settings → Pages → Build and deployment → Source: GitHub Actions**
3. Create public repo `ShubhranshProxy-downloads` for the landing page + releases (see `web/` folder)
4. Push to `main` — [`.github/workflows/deploy-pages.yml`](../.github/workflows/deploy-pages.yml) deploys `web/` automatically

Live URL: `https://shubhransh-gupta.github.io/ShubhranshProxy-downloads/`

### Updating the site

Edit files under `web/` and push to `main`. The deploy workflow runs when `web/**` changes.

---

## 6. Quick checklist before going live

- [ ] Bump **Marketing Version** in Xcode (currently `1.0`)
- [ ] Build Release DMG with `Scripts/build-dmg.sh`
- [ ] Test install on a clean Mac
- [ ] (Public) Sign + notarize
- [ ] Publish release with `Scripts/publish-release.sh v1.0.0 "..."` to `ShubhranshProxy-downloads`
- [ ] Enable GitHub Pages (GitHub Actions source)
- [ ] Verify download button on Pages site + first launch

---

## 7. Optional: automate DMG build on tag

On each tag, CI can build the DMG on a macOS runner and attach it to a GitHub Release. This requires code-signing secrets in the repo. Ask to add `.github/workflows/release.yml` if you want this automated.
