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
which the build copies into the app. It needs network access and `uv`, and the
output is gitignored rather than redistributed.

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

The build is one `swiftc` invocation per target driven by the `Makefile` — no
Xcode project. It compiles for the host architecture; set
`TARGET=x86_64-apple-macos13.0` to cross-build.
