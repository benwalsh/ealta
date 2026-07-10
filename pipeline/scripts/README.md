# Generating illustrations

The collage art is generated, not hand-drawn — kachō-e–style birds, a perched
and a flight pose each. To restyle them or build a set for your own region, the
pipeline is three scripts in this directory, wired into the repo `Makefile`.

## Pipeline

1. `pregen.py` renders each bird with Gemini 2.5 Flash Image, on a flat cream ground.
2. `cutout_flood.py` lifts the ground to transparency with a Pillow flood-fill,
   sweeps stray flecks, and crops to the bird.
3. `build_masks.py --json` writes the 1-bit collage silhouettes to
   the station profile's `illustrations/masks.json`, which the Rails `MaskPacker` reads.

Driven through the `Makefile` (which sources `.env` for `GEMINI_API_KEY`):

```bash
make regen SPECIES="Pyrrhocorax pyrrhocorax|Red-billed Chough"  # one bird: pregen + cut
make cutout      # flood-cut any new cream-ground illustrations to transparent
make declutter   # sweep stray flecks from existing cutouts, then rebuild masks
make masks       # rebuild masks.json after changing the illustration set
```

Or call the scripts directly under `uv run python`. `pregen.py --labels` takes
any `Sci|Com` per-line file (BirdNET-Pi's `labels.txt` works); `--ebird-region`
filters to species seen in your region (needs `EBIRD_API_KEY`); re-render one
bird with `--species "..." --force`.

We cut with a Pillow flood-fill rather than BiRefNet matting — onnxruntime
conflicts with the BirdNET stack in the shared `uv` environment, and at
dashboard/atlas size the flood-fill reads clean.

## Why a cream ground (and its limits)

The image model can't cut a clean transparent background itself — it leaves holes
and fringes. Rendering on a flat, consistent cream ground gives a known colour
the flood-fill removes cleanly, and the steady ground holds the painting style
together across the set.

The flood seeds from the borders, so two things need care, both handled in
`cutout_flood.py`:

- **Stray flecks.** The model speckles the "aged paper" with faint beige stipple
  the flood can't reach. `despeckle()` drops blobs that are *both* ground-coloured
  *and* clear of the body — but keeps dark/coloured details (a pale bird's eye
  floats free in its transparent white head, and must survive). `make declutter`
  applies this to existing cutouts non-destructively.
- **White birds.** A pure-white bird's plumage *is* the ground colour, so the
  flood can't tell body from background. The prompt now asks for white plumage to
  be painted as clean bright white, distinct from the warm cream, so it reads as
  white and the cut separates it. Regenerate affected white birds after a prompt
  change.

## The prompt

`prompt.template.md` is the kachō-e prompt, sent verbatim per request with
`{sci_name}`, `{com_name}`, and `{pose}` substituted. Edit it to change the
style. `pregen.py` attaches up to three reference images per request:

- **Anatomy** (IMAGE 1): a Wikipedia photo of the target species, auto-fetched
  and cached in `assets/references/`. Anchors identity and markings. Drop your
  own `references/<slug>.jpg` to override.
- **Anti-reference** (IMAGE 2, optional): a photo of a look-alike the model
  drifts toward, captioned with what NOT to copy. Wired for blue corvids (vs
  Blue Jay) and swallows (vs Barn Swallow); add more in the `ANTI_REFS` table
  and place photos at `references/_anti_<key>.jpg`.
- **Style** (IMAGE 3, optional): a real Edo-period kachō-e print whose painting
  technique is borrowed. The genus-to-print mapping is in `pregen.py`'s
  `STYLE_REFS`. The prints are not bundled (they are someone else's art); put
  your own in `assets/references/styles/`. The Koson and Yoshida prints used
  originally are easy to find on the public web by the filenames in `STYLE_REFS`.

All three degrade gracefully: a missing reference is simply not attached.

## Hard species

`species-notes.json` holds one-line diagnostic addenda for species the model
gets wrong. Each note names the field marks that matter and the look-alikes to
avoid, and is appended to the prompt for that species. Add entries as you find
drift; they carry forward to every future regeneration of that bird.

## Verifying

`verify.py` sends each illustration back through Gemini Vision without telling
it the target species, then checks the guess, the wing/leg/tail counts, and
whether a stray perch crept in. It catches drift a quick eyeball misses.

```bash
python3 verify.py --labels labels.txt              # whole library -> verify-results.csv
python3 verify.py --labels labels.txt calypte-anna
```

## What actually goes wrong

- **Sticks.** Perched raptors often come back gripping a twig the prompt
  forbade. Generate 2-3 and keep the clean one.
- **Species drift.** The model collapses an uncommon species toward a common
  look-alike (a swift becomes a swallow). Fixes, in order: a sharper
  `species-notes.json` note with anti-feature language; an anti-reference; a
  different style print; a one-off `--species` regen.
- **Matched pair.** The perched and flight poses must read as the same
  individual. Review them side by side before locking.
