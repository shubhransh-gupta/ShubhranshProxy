# Release ShubhranshProxy (DMG + website)

This guide covers building a `.dmg`, hosting it, and putting a download page online.

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

## 4. Upload the DMG to a server

Pick one option:

### Option A — GitHub Releases (easiest, free)

```bash
git tag v1.0.0
git push origin v1.0.0

gh release create v1.0.0 \
  build/release/ShubhranshProxy-1.0.dmg \
  --title "ShubhranshProxy 1.0" \
  --notes "First public release"
```

Download URL looks like:

`https://github.com/YOUR_USER/ShubhranshProxy/releases/download/v1.0.0/ShubhranshProxy-1.0.dmg`

### Option B — Firebase Hosting

```bash
npm install -g firebase-tools
firebase login
firebase init hosting   # public folder: website
mkdir -p website/downloads
cp build/release/ShubhranshProxy-1.0.dmg website/downloads/
firebase deploy
```

### Option C — Any VPS / S3 / Cloudflare R2

Upload the DMG to a `downloads/` folder and serve it over HTTPS:

```bash
scp build/release/ShubhranshProxy-1.0.dmg user@your-server:/var/www/html/downloads/
```

---

## 5. Publish the landing page

A starter page is in `website/index.html`.

1. Edit the download link:

   ```html
   <a href="https://YOUR-SERVER/downloads/ShubhranshProxy-1.0.dmg" download>
   ```

2. Deploy the `website/` folder:

| Host | Command |
|------|---------|
| GitHub Pages | Push `website/` to `gh-pages` branch or use `/docs` |
| Netlify | Drag-drop `website/` at netlify.com |
| Firebase | `firebase deploy` |
| Nginx VPS | Copy to `/var/www/html/index.html` |

---

## 6. Quick checklist before going live

- [ ] Bump **Marketing Version** in Xcode (currently `1.0`)
- [ ] Build Release DMG with `Scripts/build-dmg.sh`
- [ ] Test install on a clean Mac
- [ ] (Public) Sign + notarize
- [ ] Upload DMG
- [ ] Update `website/index.html` download URL
- [ ] Deploy website over **HTTPS**
- [ ] Verify download + first launch

---

## 7. Optional: automate with GitHub Actions

On each tag, CI can build the DMG and attach it to a GitHub Release. Ask to add `.github/workflows/release.yml` if you want this automated.
