#!/bin/bash
set -euo pipefail

OUTPUT_PATH="${DOCC_OUTPUT_PATH:-$HOME/Downloads/couchdbclient}"
OUTPUT_PARENT="$(dirname "$OUTPUT_PATH")"
HOSTING_BASE_PATH="${DOCC_HOSTING_BASE_PATH:-docs/couchdbclient}"

swift package --allow-writing-to-directory "$OUTPUT_PARENT" \
    generate-documentation \
    --target CouchDBClient \
    --disable-indexing \
    --output-path "$OUTPUT_PATH" \
    --transform-for-static-hosting \
    --experimental-transform-for-static-hosting-with-content \
    --hosting-base-path "$HOSTING_BASE_PATH" \
    --enable-experimental-markdown-output \
    --enable-experimental-markdown-output-manifest

python3 - "$OUTPUT_PATH" <<'PY'
import html
import os
import sys
from pathlib import Path

output_path = Path(sys.argv[1])
link_html = (
    '<a id="docc-markdown-link" href="#" aria-label="Open Markdown version" '
    'style="position:fixed;right:16px;bottom:16px;z-index:2147483647;'
    'padding:8px 12px;border-radius:9999px;background:rgba(255,255,255,0.94);'
    'border:1px solid rgba(0,0,0,0.08);box-shadow:0 2px 8px rgba(0,0,0,0.18);'
    'color:#06c;font:500 13px -apple-system,BlinkMacSystemFont,'
    '&#39;SF Pro Text&#39;,&#39;Helvetica Neue&#39;,sans-serif;text-decoration:none;'
    'backdrop-filter:saturate(180%) blur(20px)" hidden>Markdown</a>'
)
script_html = """
<script>
(function() {
  const link = document.getElementById("docc-markdown-link");
  if (!link) return;

  function trimSlashes(value) {
    return value.replace(/^\\/+|\\/+$/g, "");
  }

  function splitPath(value) {
    const trimmed = trimSlashes(value);
    return trimmed ? trimmed.split("/") : [];
  }

  function relativeHref(fromDirectory, toPath) {
    const fromParts = splitPath(fromDirectory);
    const toParts = splitPath(toPath);
    let sharedIndex = 0;

    while (
      sharedIndex < fromParts.length &&
      sharedIndex < toParts.length &&
      fromParts[sharedIndex] === toParts[sharedIndex]
    ) {
      sharedIndex += 1;
    }

    return [
      ...Array(fromParts.length - sharedIndex).fill(".."),
      ...toParts.slice(sharedIndex)
    ].join("/") || ".";
  }

  function currentRoute() {
    const configuredBaseUrl =
      typeof baseUrl === "string" && baseUrl.length > 0 ? baseUrl : "/";
    const normalizedBaseUrl = trimSlashes(configuredBaseUrl);
    const basePrefix = normalizedBaseUrl ? "/" + normalizedBaseUrl + "/" : "/";
    let pathname = window.location.pathname;

    if (normalizedBaseUrl && pathname.startsWith(basePrefix)) {
      pathname = pathname.slice(basePrefix.length);
    } else {
      pathname = pathname.replace(/^\\/+/, "");
    }

    pathname = pathname.replace(/index\\.html$/, "");
    return trimSlashes(pathname);
  }

  function updateMarkdownLink() {
    const route = currentRoute();

    if (!route) {
      link.hidden = true;
      link.removeAttribute("href");
      return;
    }

    link.href = relativeHref(route, "data/" + route.toLowerCase() + ".md");
    link.hidden = false;
  }

  const originalPushState = history.pushState;
  history.pushState = function() {
    const result = originalPushState.apply(this, arguments);
    queueMicrotask(updateMarkdownLink);
    return result;
  };

  const originalReplaceState = history.replaceState;
  history.replaceState = function() {
    const result = originalReplaceState.apply(this, arguments);
    queueMicrotask(updateMarkdownLink);
    return result;
  };

  window.addEventListener("popstate", updateMarkdownLink);
  updateMarkdownLink();
})();
</script>
"""

for html_path in output_path.rglob("index.html"):
    contents = html_path.read_text()
    if 'id="docc-markdown-link"' in contents:
        continue

    route = html_path.relative_to(output_path).as_posix()
    route = route[:-len("/index.html")] if route.endswith("/index.html") else ""
    markdown_path = output_path / "data" / f"{route.lower()}.md" if route else None
    relative_markdown_path = (
        os.path.relpath(markdown_path, html_path.parent).replace(os.sep, "/")
        if markdown_path and markdown_path.exists()
        else "#"
    )
    page_link_html = link_html.replace('href="#"', f'href="{html.escape(relative_markdown_path, quote=True)}"')
    updated_contents = contents.replace("</body>", f"{page_link_html}{script_html}</body>")
    html_path.write_text(updated_contents)
PY
