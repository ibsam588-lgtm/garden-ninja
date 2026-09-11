# Harvest garden art prompts

Built-in imagegen was used for the project artwork. Final assets:

- `assets/images/backgrounds/harvest_courtyard.png`
- `assets/images/sprites/harvest_atlas.png`

## Courtyard environment

Create a production-ready background asset for the mobile game shown in the supplied approved mockup. Use the LEFT screenshot as the exact visual/layout reference. Output ONLY the garden environment, no frames, no text, no buttons, no HUD, no icons, no decorative presentation canvas. Portrait aspect ratio 9:16, 1080x1920 preferred.
Replicate the beautiful mature sunlit isometric stone courtyard: distant hills at top, cypress trees, warm stone enclosing walls, dark timber garden shed left, trellis right, pale stone winding pathways, traditional stone lantern and small koi pond lower left, rustic potting bench lower right, cultivated decorative lavender/leafy borders. Six wooden raised planting beds in three staggered rows occupy the center and lower center from approximately 40% to 78% image height. Maintain generous clear path separating beds.
CRITICAL for game integration: all six playable raised beds must contain ONLY bare rich brown soil with subtly uneven texture. No strawberry fruit, no crop plants, no foliage inside these six beds. Decorative greenery outside the beds remains lush. These beds receive interactive crop sprites in code. The two front beds are largest and easily readable. Beyond the rear low wall at upper right around x=68%, y=29%, leave a flat empty rectangular sunlit stone terrace for a later greenhouse placement. Do not put a greenhouse there. Lower 14% remains beautiful garden/path background suitable behind controls.
Match the reference's light, realistic stylized 2.5D art, material richness, architecture, top-down viewing angle and color palette closely. Do not make it childish. No faces, mascots, sparkles, arrows, outlines, labels, modern machinery, square tile puzzle grid, or UI. Finished game environment illustration that fills the entire portrait image.

## Atlas source

Create one production game sprite atlas PNG with a genuinely TRANSPARENT alpha background, no checkerboard or opaque background. Exactly 3 columns by 2 rows of equal square cells, 1536x1024 canvas. Every object centered fully inside its own cell with 12% transparent padding. NO text, labels, lines, borders, dividers, numbers or captions. Asset colors match a sophisticated sunny isometric garden game: realistic stylized 2.5D, detailed natural leaves, weathered wood, copper. Light from upper left. Consistent camera looking downward at about 35 degrees. Absolutely no faces or baby style.
Top-left cell: low healthy strawberry plant with several richly red ripe strawberries plainly visible above and among dark green serrated leaves and two tiny white blossoms. Small soil root base, NO pot or box. Readable rich red berry silhouettes.
Top-middle cell: same low strawberry plant but only SMALL GREEN UNRIPE berries, no red anywhere. Rich leaves, small soil root base, no container.
Top-right cell: a compact low blueberry bush, plainly visible deep indigo blue ripe berry clusters, natural leaves, small soil root base, no container.
Bottom-left cell: full detailed freestanding copper-framed glass greenhouse on a small stone base, peaked roof, transparent glass, few green pots inside, modest footprint. Isometric view, complete building uncut.
Bottom-middle cell: two small EMPTY wooden raised growing beds on a small stone terrace base, perspective matching the camera, soil visible and retaining stone edge.
Bottom-right cell: low tomato plant with vivid ripe orange-red tomatoes and pointed leaves, small soil root base, no container.
All six images must be independent isolated cutouts, with generous space between them and no overlap. The greenhouse and terrace are detailed architectural cutouts. Plants are detailed game sprites. Keep all cells exactly equal and centered. Alpha transparency required.

## Final atlas background edit

Edit this sprite sheet for chroma-key compositing in a game renderer. Replace the entire blurry background with perfectly FLAT PURE MAGENTA #FF00FF, with zero gradients, zero shadows on background, no checkerboard. Preserve all six objects, their natural colors and the exact 3-column 2-row atlas layout. Keep each object within its equal square cell. No objects may touch adjacent cells. Shrink the greenhouse so its roof starts below the exact midline. Give at least 5% margin around each sprite. Use pure magenta in the gaps between leaves, and around all object silhouettes. No text, labels, grid lines or color swatches. Foreground objects must stay crisp and detailed: red strawberry plant, green unripe strawberry plant, blueberry bush, copper greenhouse, stone terrace beds, tomato plant. The single flat magenta background is intentional for runtime shader masking. Make every background pixel exactly #ff00ff.

The renderer converts the chroma key into premultiplied transparency once while loading; the source atlas is not modified at runtime.
