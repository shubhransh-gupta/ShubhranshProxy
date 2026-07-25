(function () {
  "use strict";

  var menuToggle = document.getElementById("menu-toggle");
  var mobileNav = document.getElementById("mobile-nav");

  if (menuToggle && mobileNav) {
    menuToggle.addEventListener("click", function () {
      var open = mobileNav.classList.toggle("open");
      mobileNav.setAttribute("aria-hidden", open ? "false" : "true");
    });

    mobileNav.querySelectorAll("a").forEach(function (link) {
      link.addEventListener("click", function () {
        mobileNav.classList.remove("open");
        mobileNav.setAttribute("aria-hidden", "true");
      });
    });
  }

  document.querySelectorAll(".nav-links").forEach(function (nav) {
    var liquid = nav.querySelector(".nav-liquid");
    if (!liquid) return;

    var links = nav.querySelectorAll("a");

    function moveLiquid(target) {
      var navRect = nav.getBoundingClientRect();
      var rect = target.getBoundingClientRect();
      liquid.style.width = rect.width + "px";
      liquid.style.height = rect.height + "px";
      liquid.style.transform =
        "translate3d(" + (rect.left - navRect.left) + "px," + (rect.top - navRect.top) + "px,0) scale(1)";
      nav.classList.add("liquid-active");
    }

    links.forEach(function (link) {
      link.addEventListener("mouseenter", function () {
        links.forEach(function (item) {
          item.classList.remove("liquid-hover");
        });
        link.classList.add("liquid-hover");
        moveLiquid(link);
      });
    });

    nav.addEventListener("mouseleave", function () {
      nav.classList.remove("liquid-active");
      links.forEach(function (item) {
        item.classList.remove("liquid-hover");
      });
    });
  });

  document.querySelectorAll(".btn, .tab, .cv-cta").forEach(function (el) {
    el.addEventListener("mousemove", function (event) {
      var rect = el.getBoundingClientRect();
      var x = ((event.clientX - rect.left) / rect.width) * 100;
      var y = ((event.clientY - rect.top) / rect.height) * 100;
      el.style.setProperty("--liquid-x", x + "%");
      el.style.setProperty("--liquid-y", y + "%");
    });
  });

  document.querySelectorAll(".tab").forEach(function (tab) {
    tab.addEventListener("click", function () {
      var id = tab.dataset.tab;
      document.querySelectorAll(".tab").forEach(function (t) {
        t.classList.toggle("active", t === tab);
        t.setAttribute("aria-selected", t === tab ? "true" : "false");
      });
      document.querySelectorAll(".feature-panel").forEach(function (panel) {
        panel.classList.toggle("active", panel.id === "panel-" + id);
      });
    });
  });

  document.querySelectorAll(".faq-item button").forEach(function (button) {
    button.addEventListener("click", function () {
      var item = button.closest(".faq-item");
      var open = item.classList.toggle("open");
      button.setAttribute("aria-expanded", open ? "true" : "false");
    });
  });

  var revealObs = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (entry.isIntersecting) {
        entry.target.classList.add("visible");
        revealObs.unobserve(entry.target);
      }
    });
  }, { threshold: 0.05, rootMargin: "0px 0px 12% 0px" });

  document.querySelectorAll(".reveal").forEach(function (el) {
    var parent = el.parentElement;
    if (parent) {
      var siblings = Array.prototype.filter.call(
        parent.children,
        function (child) { return child.classList.contains("reveal"); }
      );
      var index = siblings.indexOf(el);
      if (index > 0) {
        el.style.transitionDelay = Math.min(index * 0.035, 0.12) + "s";
      }
    }
    revealObs.observe(el);
  });

  var mockup = document.querySelector(".mockup-window");
  if (mockup) {
    window.addEventListener("scroll", function () {
      var y = window.scrollY;
      mockup.style.transform = "translateY(" + Math.min(y * 0.04, 24) + "px)";
    }, { passive: true });
  }

  if (!window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    document.querySelectorAll(".release-item, .feature-card, .quote-card, .pricing-card, .card.card-3d.install-card, #features .card.card-3d").forEach(function (card) {
      card.addEventListener("mousemove", function (event) {
        var rect = card.getBoundingClientRect();
        var x = (event.clientX - rect.left) / rect.width - 0.5;
        var y = (event.clientY - rect.top) / rect.height - 0.5;
        var tiltX = (-y * 5).toFixed(2);
        var tiltY = (x * 5).toFixed(2);
        card.style.transform =
          "perspective(900px) rotateX(" + tiltX + "deg) rotateY(" + tiltY + "deg) translateY(-6px) translateZ(12px)";
      });

      card.addEventListener("mouseleave", function () {
        card.style.transform = "";
      });
    });
  }
})();
