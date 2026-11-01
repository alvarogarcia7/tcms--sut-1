#!/usr/bin/env bash
# Renders the traceability documents to PDF and packs the sources and the PDFs back into
# traceability-document.zip. Runs in the pdf job of .gitlab-ci.yml (asciidoctor image, with a
# kroki service for diagrams); it does not need the tpdg or tcms-cli binaries.
#
#   AsciiDoc  (30_documentation_source/asciidoc, consolidated)  -> asciidoctor-pdf, with
#             asciidoctor-diagram and asciidoctor-kroki (diagrams are rendered by KROKI_SERVER_URL)
#   Markdown  (30_documentation_source/markdown, consolidated)  -> pandoc (HTML) -> Chromium (PDF)
#
# The PDFs go to 30_documentation_source/pdf/<asciidoc|markdown|consolidated>/ and mirror the
# source file names. Every PDF is checked (PDF header, page count, text of the test case ids).
#
# Usage: scripts/render-pdfs.sh [INPUT_ZIP]     (default: traceability-document.zip)
# Environment:
#   KROKI_SERVER_URL   kroki endpoint (default http://kroki:8000)
#   PDF_WORK_DIR       scratch directory (default build/pdf)
# Exit code: 0 when every PDF was rendered and checked, 1 otherwise.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

INPUT_ZIP="${1:-traceability-document.zip}"
KROKI_SERVER_URL="${KROKI_SERVER_URL:-http://kroki:8000}"
WORK_DIR="${PDF_WORK_DIR:-$REPO_ROOT/build/pdf}"
SOURCES_ROOT="$WORK_DIR/unpacked"
DOC_DIR="$SOURCES_ROOT/30_documentation_source"
PDF_DIR="$DOC_DIR/pdf"
ZIP="$REPO_ROOT/traceability-document.zip"

[ -f "$INPUT_ZIP" ] || { echo "error: $INPUT_ZIP not found" >&2; exit 1; }
for tool in asciidoctor-pdf pandoc pdfinfo pdftotext unzip zip; do
  command -v "$tool" > /dev/null || { echo "error: $tool not found (see the pdf job in .gitlab-ci.yml)" >&2; exit 1; }
done
CHROMIUM="$(command -v chromium-browser || command -v chromium || true)"
[ -n "$CHROMIUM" ] || { echo "error: chromium not found (see the pdf job in .gitlab-ci.yml)" >&2; exit 1; }

# Kroki must answer before diagrams are rendered; the kroki service can start a little late.
echo "Waiting for kroki at $KROKI_SERVER_URL"
kroki_ready=0
for _ in $(seq 1 60); do
  if curl -fsS "$KROKI_SERVER_URL/health" > /dev/null 2>&1; then
    kroki_ready=1
    break
  fi
  sleep 2
done
if [ "$kroki_ready" -ne 1 ]; then
  echo "error: kroki is not reachable at $KROKI_SERVER_URL" >&2
  exit 1
fi
echo "  kroki ready"

rm -rf "$WORK_DIR"
mkdir -p "$SOURCES_ROOT"
unzip -q "$INPUT_ZIP" -d "$SOURCES_ROOT"
[ -d "$DOC_DIR" ] || { echo "error: $INPUT_ZIP has no 30_documentation_source folder" >&2; exit 1; }

failures=0
fail() {
  echo "  FAIL  $1"
  failures=$((failures + 1))
}

# Markdown styling for the PDF (the AsciiDoc output has its own theme from asciidoctor-pdf).
cat > "$WORK_DIR/markdown.css" <<'CSS'
body { font-family: "Noto Sans", "DejaVu Sans", sans-serif; font-size: 10pt; line-height: 1.4; color: #111; }
h1 { font-size: 20pt; border-bottom: 1px solid #999; padding-bottom: 4pt; }
h2 { font-size: 15pt; margin-top: 18pt; }
h3 { font-size: 12pt; }
table { border-collapse: collapse; width: 100%; margin: 8pt 0; font-size: 9pt; }
th, td { border: 1px solid #bbb; padding: 3pt 5pt; text-align: left; vertical-align: top; }
th { background: #eee; }
code, pre { font-family: "DejaVu Sans Mono", monospace; font-size: 8.5pt; }
pre { background: #f5f5f5; padding: 6pt; white-space: pre-wrap; }
hr { border: 0; border-top: 1px solid #ccc; margin: 14pt 0; }
CSS

render_adoc() { # render_adoc <source.adoc> <output.pdf>
  local src="$1" out="$2"
  if ! asciidoctor-pdf -r asciidoctor-diagram -r asciidoctor-kroki \
      -a source-highlighter=rouge \
      -a "kroki-server-url=$KROKI_SERVER_URL" \
      -o "$out" "$src" > "$WORK_DIR/asciidoctor-pdf.log" 2>&1; then
    echo "  FAIL  $(basename "$src"): asciidoctor-pdf failed"
    sed 's/^/        /' "$WORK_DIR/asciidoctor-pdf.log" | tail -n 30
    return 1
  fi
}

render_md() { # render_md <source.md> <output.pdf>
  local src="$1" out="$2" html="$WORK_DIR/$(basename "$1" .md).html"
  local title
  title="$(head -n 1 "$src" | sed 's/^# *//')"
  if ! pandoc -f gfm -t html5 -s --metadata "title=$title" \
        -H <(printf '<style>\n'; cat "$WORK_DIR/markdown.css"; printf '</style>\n') \
        -o "$html" "$src" 2> "$WORK_DIR/pandoc.log"; then
    echo "  FAIL  $(basename "$src"): pandoc failed"
    sed 's/^/        /' "$WORK_DIR/pandoc.log" | tail -n 30
    return 1
  fi
  if ! "$CHROMIUM" --headless --no-sandbox --disable-gpu --disable-dev-shm-usage \
        --no-pdf-header-footer --print-to-pdf="$out" "file://$html" \
        > "$WORK_DIR/chromium.log" 2>&1; then
    echo "  FAIL  $(basename "$src"): chromium failed"
    sed 's/^/        /' "$WORK_DIR/chromium.log" | tail -n 30
    return 1
  fi
}

check_pdf() { # check_pdf <pdf> <source> : the PDF is well formed and names the test case ids
  local pdf="$1" src="$2" pages text id
  if [ ! -s "$pdf" ] || [ "$(head -c 5 "$pdf")" != "%PDF-" ]; then
    fail "$(basename "$pdf") is not a PDF"
    return 1
  fi
  pages="$(pdfinfo "$pdf" 2> /dev/null | awk '/^Pages:/ {print $2}')"
  if [ -z "$pages" ] || [ "$pages" -lt 1 ]; then
    fail "$(basename "$pdf") has no pages"
    return 1
  fi
  text="$(pdftotext -layout "$pdf" - 2> /dev/null)"
  if ! grep -q -E 'PASS|FAIL' <<< "$text"; then
    fail "$(basename "$pdf") has no PASS or FAIL verdict in its text"
    return 1
  fi
  # Per-test documents name their test case; the consolidated ones name all of them.
  case "$src" in
    */consolidated/*) ;;
    *) id="$(basename "$src" | sed 's/\.[^.]*$//')"
       grep -q -F -- "$id" <<< "$text" || { fail "$(basename "$pdf") does not name $id"; return 1; } ;;
  esac
  echo "  ok    ${pdf#"$DOC_DIR"/} ($pages pages)"
}

render_all() { # render_all <subfolder> <adoc|md>
  local sub="$1" format="$2" src pdf
  mkdir -p "$PDF_DIR/$sub"
  for src in "$DOC_DIR/$sub"/*."$format"; do
    [ -f "$src" ] || continue
    # The format stays in the name: all_tests.adoc.pdf and all_tests.md.pdf are both kept.
    pdf="$PDF_DIR/$sub/$(basename "$src").pdf"
    if [ "$format" = adoc ]; then render_adoc "$src" "$pdf" || { failures=$((failures + 1)); continue; }
    else render_md "$src" "$pdf" || { failures=$((failures + 1)); continue; }
    fi
    check_pdf "$pdf" "$src" || failures=$((failures + 1))
  done
}

echo "AsciiDoc to PDF (asciidoctor-pdf, kroki diagrams)"
render_all asciidoc adoc
render_all consolidated adoc
echo "Markdown to PDF (pandoc, Chromium)"
render_all markdown md
render_all consolidated md

pdf_count="$(find "$PDF_DIR" -name '*.pdf' | wc -l)"
if [ "$pdf_count" -eq 0 ]; then
  echo "error: no PDF was produced" >&2
  exit 1
fi

# --- Package: the layout of the archive ------------------------------------------------------
#   MANIFEST.md
#   all_tests.adoc, all_tests.adoc.pdf, all_tests.md, all_tests.md.pdf    (consolidated)
#   individual/asciidoc/<TC>.adoc.pdf    individual/markdown/<TC>.md.pdf  (one per test case)
#   data/asciidoc/<TC>.adoc              data/markdown/<TC>.md            (sources)
#   other/                               everything else (e.g. all_tests_container.yaml)
PACKAGE_DIR="$WORK_DIR/package"
rm -rf "$PACKAGE_DIR"
mkdir -p "$PACKAGE_DIR/individual/asciidoc" "$PACKAGE_DIR/individual/markdown" \
  "$PACKAGE_DIR/data/asciidoc" "$PACKAGE_DIR/data/markdown" "$PACKAGE_DIR/other"

cp "$DOC_DIR/consolidated/all_tests.adoc" "$DOC_DIR/consolidated/all_tests.md" \
  "$DOC_DIR/pdf/consolidated/all_tests.adoc.pdf" "$DOC_DIR/pdf/consolidated/all_tests.md.pdf" \
  "$PACKAGE_DIR/"
cp "$DOC_DIR"/pdf/asciidoc/*.pdf "$PACKAGE_DIR/individual/asciidoc/"
cp "$DOC_DIR"/pdf/markdown/*.pdf "$PACKAGE_DIR/individual/markdown/"
cp "$DOC_DIR"/asciidoc/*.adoc "$PACKAGE_DIR/data/asciidoc/"
cp "$DOC_DIR"/markdown/*.md "$PACKAGE_DIR/data/markdown/"

# Everything else of the documentation folder goes to other/ (the manifest is handled below).
while IFS= read -r -d '' other; do
  cp "$other" "$PACKAGE_DIR/other/"
done < <(find "$DOC_DIR" -type f ! -name MANIFEST.md \
  ! -path "$DOC_DIR/pdf/*" ! -path "$DOC_DIR/asciidoc/*" ! -path "$DOC_DIR/markdown/*" \
  ! -name all_tests.adoc ! -name all_tests.md -print0)

# The manifest keeps its content; the file list is rewritten for this layout.
sed '/^## Files$/,$d' "$DOC_DIR/MANIFEST.md" > "$PACKAGE_DIR/MANIFEST.md"
{
  echo "## Files"
  echo
  (cd "$PACKAGE_DIR" && find . -type f ! -name MANIFEST.md | sort | sed 's|^\./|- |')
  echo
  echo "## Layout"
  echo
  echo "- Top level: the consolidated documents (all test cases) with their PDFs."
  echo "- individual/: one PDF per test case, AsciiDoc and Markdown."
  echo "- data/: the AsciiDoc and Markdown sources of the individual documents."
  echo "- other/: the remaining files of the documentation folder."
  echo
  echo "PDFs are rendered from the AsciiDoc and Markdown documents by the pdf job (scripts/render-pdfs.sh)."
} >> "$PACKAGE_DIR/MANIFEST.md"

rm -f "$ZIP"
(cd "$PACKAGE_DIR" && zip -qr "$ZIP" .)
echo "Produced ${ZIP#"$REPO_ROOT"/} with $pdf_count PDF(s):"
unzip -l "$ZIP"

if [ "$failures" -gt 0 ]; then
  echo "error: $failures document(s) could not be rendered to PDF" >&2
  exit 1
fi
