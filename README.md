# Excalidraw QuickLook

QuickLook previews and Finder thumbnails for `.excalidraw` files on macOS.
Select a drawing, press space, see the drawing — not its JSON.

    make install

Requires macOS 13 or later and the Xcode command line tools. Installs to
`/Applications/ExcalidrawQuickLook.app` (override with `INSTALL_DIR=`); the
extensions live inside that app, so previews stop working if you move or
delete it.

## Why an app

Legacy `.qlgenerator` plugins stopped working in macOS 15 Sequoia. Previews now
have to be app extensions (`.appex`) bundled inside a real app, so this repo
builds a container app whose only job is to hold two extensions — one for the
spacebar preview, one for Finder thumbnails.

Nothing on a stock system claims the `.excalidraw` extension, so it resolves to
a dynamic UTI that no extension can bind to. The app therefore declares
`com.excalidraw.excalidraw` as an *imported* type. That declaration deliberately
does **not** conform to `public.json`: with it, macOS routes previews to its own
text previewer and you get a wall of element JSON instead of the drawing.

## In the preview

The preview opens zoomed to fit and is a live canvas, not a flat image:

| | |
| --- | --- |
| Pinch, or ⌘/⌥ + scroll | Zoom |
| Scroll, or two-finger drag | Pan |
| Double-click | Toggle between fit and zoomed in |

Zooming redraws the vectors rather than magnifying pixels, so strokes and text
stay sharp all the way in, and only the elements actually on screen are drawn.

## Rendering

The drawing is rendered natively with CoreGraphics — there is no embedded
browser and no vendored JavaScript. `Sources/ExcalidrawKit` parses the document
model and draws rectangles, diamonds, ellipses, lines, arrows, freedraw, text,
embedded images and frames, including a port of the parts of roughjs that
Excalidraw uses, seeded per element so the hand-drawn wobble matches the editor.

Known differences from the real thing:

- `hachure` and `cross-hatch` fills are drawn as clipped parallel lines rather
  than roughjs' sketched ones; `zigzag` is drawn as `hachure`.
- `freedraw` is a round-capped stroke, not a perfect-freehand outline, so it
  does not taper with pressure.
- Frames do not clip the elements inside them.
- Arrows are drawn from their stored points; bindings are not recomputed.

### Fonts

Excalidraw's own typefaces ship as woff2, which CoreText cannot register, so by
default each maps to the closest installed face (Excalifont and Virgil to Comic
Sans MS, Nunito to Helvetica Neue, Cascadia to Menlo, and so on).

For text that matches the editor exactly:

    make fonts && make install

That converts the fonts from the excalidraw repo to ttf into `Resources/Fonts`,
which the build copies into the app. It needs network access and `uv`.

#### Licensing

This repository distributes no font files at all — `make fonts` fetches and
converts them on your machine, and the output is gitignored. Six of the seven
are SIL OFL 1.1 (Excalifont, Nunito, Cascadia Code, Lilita One, Assistant,
Virgil) and Comic Shanns is MIT. Both licences grant modification outright and
attach their conditions to *redistribution*, so converting them for your own
previews carries no obligation. `make fonts` writes the per-font details to
`Resources/Fonts/LICENCES.md`.

Redistributing a **built app** with the fonts inside is a different question,
and two things would need fixing first:

- Cascadia Code and Lilita One have Reserved Font Names, and this script
  deliberately renames each modified font back to its canonical family so
  CoreText can find it — precisely what OFL clause 3 forbids for a modified
  version. Excalifont is also a trademark of Excalidraw, which its licence does
  not cover.
- Excalidraw's own subsetting already stripped the embedded licence records from
  several of these files, so the notices no longer travel inside the fonts and
  would have to be shipped alongside them.

None of that applies to the default build, which ships no fonts.

## Working on it

    make cli                                     # build the renderer alone
    ./build/excalidraw-render in.excalidraw out.png --size 1400
    make test                                    # render Tests/Fixtures
    make test FILES="$(ls ~/drawings/*.excalidraw)"
    make status                                  # what the system has registered
    make uninstall

`build/excalidraw-render` is the fast way to iterate: it runs the same renderer
the extensions do, without Finder or QuickLook caching in the way.
`Tests/Fixtures/kitchen-sink.excalidraw` exercises every element type, fill,
stroke style, arrowhead and font family in one canvas.

If a preview looks stale after a reinstall, `make install` already resets the
QuickLook caches and restarts Finder; `qlmanage -p file.excalidraw` renders one
through the real extension for debugging.

`make install` re-checks registration afterwards and fails if it did not take.
That is not paranoia: `pluginkit -a` accepts a registration made just after the
bundle was replaced and then quietly drops it, which leaves previews dead with
nothing in the log and an install that claimed to succeed.

The build is one `swiftc` invocation per target driven by the `Makefile` — no
Xcode project. It compiles for the host architecture; set
`TARGET=x86_64-apple-macos13.0` to cross-build.
