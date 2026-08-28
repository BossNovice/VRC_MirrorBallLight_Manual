/* MirrorBallLight マニュアル。ローカルのファイルを直接開いても動くように、
   外部からは何も読み込みません。検索の索引は search-index.js に直接書いてあります。 */
(function () {
  "use strict";

  /* --- 左の一覧の開閉（画面が狭いとき） --- */
  var sidebar = document.querySelector(".sidebar");
  var toggle = sidebar && sidebar.querySelector(".toggle");
  if (toggle) {
    toggle.addEventListener("click", function () {
      var open = sidebar.classList.toggle("open");
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
    });
  }

  /* --- 見出しへの位置リンク --- */
  var headings = document.querySelectorAll("main h2[id], main h3[id], main section[id] > h2");
  Array.prototype.forEach.call(headings, function (h) {
    var id = h.id || (h.parentNode && h.parentNode.id);
    if (!id || h.querySelector(".anchor")) return;
    var a = document.createElement("a");
    a.className = "anchor";
    a.href = "#" + id;
    a.textContent = "#";
    a.setAttribute("aria-label", "この見出しへのリンク");
    h.appendChild(a);
  });

  /* --- 上へ戻る --- */
  var top = document.querySelector(".totop");
  if (top) {
    var onScroll = function () {
      if (window.pageYOffset > 700) top.classList.add("show");
      else top.classList.remove("show");
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    onScroll();
  }

  /* --- 検索 --- */
  var input = document.getElementById("q");
  var box = document.getElementById("results");
  var index = window.MANUAL_INDEX;
  if (!input || !box || !index) return;

  function normalize(s) {
    return s.toLowerCase().replace(/[　\s]+/g, "");
  }

  function search(query) {
    var q = normalize(query);
    if (q.length < 1) return [];
    var hits = [];
    for (var i = 0; i < index.length && hits.length < 400; i++) {
      var page = index[i];
      var perPage = 0;
      for (var j = 0; j < page.s.length; j++) {
        if (perPage >= 3) break; /* 1ページから多くても3件までにします */
        var sec = page.s[j];
        var hay = normalize(sec.ti + sec.tx);
        var at = hay.indexOf(q);
        if (at < 0) continue;
        /* 見出しに当たったものを上に出します */
        var score = normalize(sec.ti).indexOf(q) >= 0 ? 0 : 1;
        var from = Math.max(0, at - 18);
        hits.push({
          href: page.p + (sec.id ? "#" + sec.id : ""),
          page: page.t,
          title: sec.ti,
          text: sec.tx.substr(from, 90),
          score: score
        });
        perPage++;
      }
    }
    hits.sort(function (a, b) { return a.score - b.score; });
    return hits.slice(0, 30);
  }

  function render(hits, query) {
    box.innerHTML = "";
    if (!query) { box.classList.remove("open"); return; }
    if (!hits.length) {
      var e = document.createElement("div");
      e.className = "empty";
      e.textContent = "見つかりませんでした";
      box.appendChild(e);
      box.classList.add("open");
      return;
    }
    hits.forEach(function (h) {
      var a = document.createElement("a");
      a.href = h.href;
      var b = document.createElement("b");
      b.textContent = h.page + " / " + h.title;
      var s = document.createElement("span");
      s.textContent = h.text;
      a.appendChild(b);
      a.appendChild(s);
      box.appendChild(a);
    });
    box.classList.add("open");
  }

  var timer = null;
  input.addEventListener("input", function () {
    var v = input.value;
    clearTimeout(timer);
    timer = setTimeout(function () { render(search(v), v.trim()); }, 90);
  });

  input.addEventListener("keydown", function (e) {
    if (e.key === "Escape") { input.value = ""; render([], ""); input.blur(); }
    if (e.key === "ArrowDown") {
      var first = box.querySelector("a");
      if (first) { e.preventDefault(); first.focus(); }
    }
  });

  box.addEventListener("keydown", function (e) {
    var links = Array.prototype.slice.call(box.querySelectorAll("a"));
    var at = links.indexOf(document.activeElement);
    if (e.key === "ArrowDown" && at > -1 && links[at + 1]) { e.preventDefault(); links[at + 1].focus(); }
    if (e.key === "ArrowUp") {
      e.preventDefault();
      if (at > 0) links[at - 1].focus(); else input.focus();
    }
    if (e.key === "Escape") { input.focus(); render([], ""); }
  });

  document.addEventListener("click", function (e) {
    if (!box.contains(e.target) && e.target !== input) box.classList.remove("open");
  });

  /* 「/」で検索欄へ移動します */
  document.addEventListener("keydown", function (e) {
    if (e.key === "/" && document.activeElement !== input &&
        !/^(INPUT|TEXTAREA)$/.test(document.activeElement.tagName)) {
      e.preventDefault();
      input.focus();
    }
  });
})();
