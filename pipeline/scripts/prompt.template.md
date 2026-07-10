# Bird illustration prompt

The prompt sent to Gemini for every illustration. Style: **Irish linocut** — bold
carved black keylines, flat areas of the bird's true colours, on a plain white
ground (cut to transparency in step 2). The bold keylines wall off the bird, so
the flood-cut works even on white birds.

Three text placeholders get replaced per request:

- `{sci_name}` — the binomial Latin name, e.g. `Erithacus rubecula`
- `{com_name}` — the English common name, e.g. `European Robin`
- `{pose}` — `perched` (pose 1) or `in flight with wings spread` (pose 2)

`pregen.py` attaches up to two reference images:

- A POSITIVE anatomy reference (Wikipedia photo of the species) as IMAGE 1 —
  anchors identity, markings, and the bird's true colours.
- An OPTIONAL anti-reference as IMAGE 2 (a look-alike the model drifts toward, for
  genera where the prior collapses). The `{anti_ref_line}` placeholder is rewritten
  per-species; it's empty when there's no anti-reference.

The linocut style lives entirely in the text below — there's no style-reference
image, so closely-related species come out consistent without a shared print.

---

## Prompt

Generate a {pose} {com_name} ({sci_name}) as a hand-pulled IRISH LINOCUT — a multi-block lino-reduction relief print. The bird is built from BOLD, CONFIDENT CARVED BLACK KEYLINES: the outline and the major internal divisions look cut from a lino block — clean, decisive, slightly angular, with the weight and character of a knife-cut line, not a thin pen line — enclosing FLAT AREAS OF COLOUR. Within the larger colour areas there is a SUBTLE hand-carved texture: sparse fine gouge-marks and short parallel cut-strokes that follow the form (the honest texture of carved lino and hand-printing), NEVER smooth airbrushed gradients and NEVER dense photographic feather detail. The whole thing has the slightly imperfect, hand-pressed character of ink pulled from a hand-cut block on paper.

COLOUR: render the bird in its TRUE, ACCURATE, NATURALISTIC colours and markings — the real plumage of the species — but as FLAT, MATTE PRINTED INKS with crisp boundaries, not blended or tonally shaded. Use AS MANY flat colours as the species needs to be correct and recognisable: this is a multi-block print, NOT a reduced two- or three-colour print, so do not throw away the bird's real colours. The inks are rich but a touch earthy and matte, like printmaking ink. Keep each colour a flat zone and let the black keylines plus a few carved accent marks do the describing. Where the plumage is white or pale, print it as a CLEAN BRIGHT WHITE — the bold black keyline separates it from the white background, so render it confidently white, never greyed-down or tinted.

The bird is isolated on a PLAIN, PURE, FLAT WHITE background — a single clean white field edge to edge. NO colour, NO cream, NO buff, NO grey, NO tint, NO gradient, NO paper texture, NO stipple, NO speckling, NO foxing, NO flecks, NO shadow, NO scenery — nothing but clean white behind the bird. The bird is the ONLY element; the perch is implied by toe posture, NEVER drawn. NO border or frame, NO text or signature.

Composition: the bird occupies one-third to one-half of the frame, in clear SIDE PROFILE, body held HORIZONTALLY (wider than tall), with generous negative space around it. Sparse and confident, not packed with detail.

The ENTIRE bird must fit within the frame: head, both wings, full tail, both legs, both feet, beak — nothing cropped at the edge. Leave generous padding on all sides.

### Reference handling

- IMAGE 1 (positive, anatomy) IS {com_name}. Match its proportions, head colour, throat, wing pattern, back colour, tail pattern, leg colour, and overall plumage colours FAITHFULLY. If the reference shows non-breeding or worn plumage, render the brightest BREEDING (adult-summer) plumage. Treat IMAGE 1 for ANATOMY and COLOUR only — do NOT copy its photographic texture, lighting, or background; restyle it completely as a flat linocut.
{anti_ref_line}

### Anatomy

- EXACTLY TWO wings, EXACTLY TWO legs, ONE head, ONE beak, ONE tail.
- Posture, colour, markings and proportions match IMAGE 1 / {com_name}. Render species-specific patterns precisely — do NOT default to generic markings (no invented face mask, wingbars, or crest the species does not have).
- For close-relative species in the library, render the diagnostic differences clearly so they are distinguishable.

### Feet

- BOTH FEET visible at the bottom of the body. Slim tarsi, small delicate toes — songbird tarsi roughly 10-15% of body height, larger birds proportionally per IMAGE 1. Do NOT exaggerate feet or claws.

### Pose

- PERCHED (pose 1): one wing folded against the body, side profile, both feet visible with toes gently curled as if grasping a thin (undrawn) perch.
- IN FLIGHT (pose 2): both wings fully extended; feet tucked to the belly or trailed along the tail, not dangling.

### Output

Render at high resolution. No shadow, no caption.
