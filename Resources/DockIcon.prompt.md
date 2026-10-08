# Postino app icon

The approved face-and-letter master is `IconMaster.png`, generated with the built-in imagegen tool. `DockIcon.png` and `Logo.png` are 1024 px derivatives. `scripts/build-icon.sh` packages all standard 16–1024 px and Retina sizes into `PostinoFace.icns`. The bundle declares that ICNS directly; the app does not override the Dock image with a smaller icon-services representation. macOS 26 applies its system mask, sizing, and material. Verified using a fresh bundle’s system-rendered icon.

Apple references: [App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons/) and [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass).

## Approved refinement prompt

Use case: precise-object-edit. Edit the provided Postauomo cartoon app icon with exactly these refinements, keeping the character, expression, colors, clean black outlines, green square background and overall style unchanged. 1) Make the blue cap matte and flat like the rest of the cartoon: remove the long shiny pale blue reflection streak and the glossy gray highlight across the black brim; use restrained flat color shading instead. Reduce shiny highlights on its gold buttons too. 2) Remove the tiny stray black pointed shape just below the viewer-left mustache beside the corner of the smile, making that cheek clean skin without a black spike. Preserve the large curled mustache itself. 3) Move the head a little left and the gloved hand with its envelope a little right so there is a clear visible green gap between the entire envelope and the viewer-right mustache. No touching, no overlap, no tangency. Keep the whole face, cap, hand and letter comfortably inside the square, adjusting their size slightly if needed. Preserve the natural hand grip. No red annotation marks, no text, no watermark. Crisp high-resolution square icon master.

## Final cleanup prompt

Use case: precise-object-edit. Make two very small corrections to this icon; preserve everything else exactly. Remove the tiny pointed black tooth/spike underneath the viewer-left mustache at the corner of the smile (around x430 y752 in the 1254px image): replace it with clean peach cheek skin. That small skin area should have no black mark at all; keep the larger outer mustache curve. Also remove the gray reflective stripe on the black hat brim entirely, making the brim solid black. Keep the blue cap matte as shown, and keep the new clear green gap between the letter and mustache. Do not move, add or redesign anything else. No annotations, no text.


## Transparent sidebar logo

`Logo.png` is a transparent cutout generated using the built-in imagegen tool from the approved master. It is displayed at 40 pt in the sidebar. The Dock keeps its green icon background.

Use case: background-extraction. Edit target: approved Postauomo mascot portrait. Remove ONLY the entire emerald green background, including the green gap between the face and letter, replacing it with true alpha transparency. Preserve the exact existing cartoon face, cap, mustache, smile, collar, white glove and cream envelope, their colors, proportions, outlines, composition and spacing. Do not redraw or restyle the character. Keep all original fine antialiased edges without green fringe. No added drop shadow, no frame, no colored backdrop, no checkerboard baked into pixels, no text. Return a high-resolution transparent PNG cutout.
