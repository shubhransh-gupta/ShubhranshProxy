(function () {
  "use strict";

  var REPO = "shubhransh-gupta/ShubhranshProxy";
  var API_URL = "https://api.github.com/repos/" + REPO + "/releases?per_page=20";
  var FALLBACK_DOWNLOAD =
    "https://github.com/shubhransh-gupta/ShubhranshProxy/releases/download/v2.0.1/ShubhranshProxy-2.0.1.dmg";
  var latestDownloadUrl = FALLBACK_DOWNLOAD;
  var releaseRequest = null;

  function pickDmgAsset(release) {
    var assets = release && release.assets;
    if (!assets || !assets.length) return null;
    var dmgs = assets.filter(function (asset) {
      return /\.dmg$/i.test(asset.name);
    });
    if (!dmgs.length) return null;

    var tag = String(release.tag_name || "").replace(/^v/i, "");
    var versioned = dmgs.find(function (asset) {
      return tag && asset.name.indexOf(tag) !== -1;
    });
    if (versioned) return versioned;

    return dmgs.slice().sort(function (a, b) {
      return new Date(b.updated_at) - new Date(a.updated_at);
    })[0];
  }

  function pickLatestRelease(releases) {
    if (!Array.isArray(releases)) return null;
    return releases
      .filter(function (release) {
        return !release.draft && pickDmgAsset(release);
      })
      .sort(function (a, b) {
        return new Date(b.published_at || b.created_at) - new Date(a.published_at || a.created_at);
      })[0] || null;
  }

  function versionFromTag(tag) {
    return String(tag || "").replace(/^v/i, "");
  }

  function versionLabel(tag) {
    var version = versionFromTag(tag);
    return version ? "v" + version : "";
  }

  function formatPublishedDate(iso) {
    if (!iso) return "";
    try {
      return new Date(iso).toLocaleDateString("en-US", {
        month: "long",
        year: "numeric",
      });
    } catch (err) {
      return "";
    }
  }

  function applyTemplate(template, version, label) {
    return template
      .replace(/\{version\}/g, label)
      .replace(/\{versionShort\}/g, version);
  }

  function applyRelease(release) {
    var version = versionFromTag(release.tag_name);
    var label = versionLabel(release.tag_name);
    var dmg = pickDmgAsset(release);
    var downloadUrl = (dmg && dmg.browser_download_url) || FALLBACK_DOWNLOAD;
    var notesUrl = release.html_url || "";
    var published = formatPublishedDate(release.published_at);
    latestDownloadUrl = downloadUrl;

    document.querySelectorAll(".release-download").forEach(function (el) {
      el.href = downloadUrl;
      var downloadLabel = el.getAttribute("data-download-label");
      if (downloadLabel) {
        el.textContent = applyTemplate(downloadLabel, version, label);
      }
    });

    document.querySelectorAll(".release-version").forEach(function (el) {
      var template = el.getAttribute("data-release-template") || "{version}";
      el.textContent = applyTemplate(template, version, label);
    });

    document.querySelectorAll(".release-version-in").forEach(function (el) {
      el.textContent = "What's new in " + label;
    });

    document.querySelectorAll(".release-notes").forEach(function (el) {
      if (notesUrl) el.href = notesUrl;
    });

    document.querySelectorAll(".release-published").forEach(function (el) {
      if (published) el.textContent = "Released " + published;
    });

    document.documentElement.classList.add("release-loaded");
    document.documentElement.setAttribute("data-release-version", label);
    document.documentElement.setAttribute("data-release-download", downloadUrl);
  }

  function loadRelease() {
    if (releaseRequest) return releaseRequest;

    releaseRequest = fetch(API_URL, {
      cache: "no-store",
      headers: { Accept: "application/vnd.github+json" },
    })
      .then(function (res) {
        if (!res.ok) throw new Error("release fetch failed");
        return res.json();
      })
      .then(function (releases) {
        var latestRelease = pickLatestRelease(releases);
        if (!latestRelease) throw new Error("no dmg release found");
        applyRelease(latestRelease);
        return latestDownloadUrl;
      })
      .catch(function () {
        document.documentElement.classList.add("release-fallback");
        return latestDownloadUrl;
      });
    return releaseRequest;
  }

  document.addEventListener("click", function (event) {
    var link = event.target.closest && event.target.closest("a.release-download");
    if (!link) return;

    event.preventDefault();
    loadRelease().then(function (downloadUrl) {
      window.location.href = downloadUrl || link.href || FALLBACK_DOWNLOAD;
    });
  });

  loadRelease();
})();
