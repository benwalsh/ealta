# Bird illustration prompt

The prompt sent to the image model for every illustration. This example ships a plain,
naturalistic field-guide style: a bold clean outline, flat true-to-life colours, on a pure
white ground (cut to transparency in step 2). Swap this file for your own to give your
station its own visual voice — any style works, as long as it keeps the two things the
cutout pipeline needs: a **bold enclosing outline** and a **flat pure-white background**.

Three text placeholders get replaced per request:

- `{sci_name}` — the binomial Latin name, e.g. `Erithacus rubecula`
- `{com_name}` — the English common name, e.g. `European Robin`
- `{pose}` — `perched` (pose 1) or `in flight with wings spread` (pose 2)

`pregen.py` attaches up to two reference images:

- A POSITIVE anatomy reference (Wikipedia photo of the species) as IMAGE 1 — anchors
  identity, markings, and the bird's true colours.
- An OPTIONAL anti-reference as IMAGE 2 (a look-alike the model drifts toward). The
  `{anti_ref_line}` placeholder is rewritten per-species; it's empty when there's none.

---

## Prompt

Generate a {pose} {com_name} ({sci_name}) as a clean, naturalistic field-guide illustration. The bird has a BOLD, CONFIDENT DARK OUTLINE enclosing FLAT AREAS OF COLOUR — crisp printed inks with clear boundaries, not blended or airbrushed. Keep internal detail restrained: a few clean lines to show wing, tail and eye, never dense photographic feather texture.

COLOUR: render the bird in its TRUE, ACCURATE, NATURALISTIC colours and markings — the real plumage of the species — as FLAT, MATTE zones of colour. Use as many flat colours as the species needs to be correct and recognisable. Where the plumage is white or pale, print it as a CLEAN BRIGHT WHITE — the bold outline separates it from the white background, so render it confidently white, never greyed-down.

The bird is isolated on a PLAIN, PURE, FLAT WHITE background — a single clean white field edge to edge. NO colour, NO cream, NO grey, NO tint, NO gradient, NO paper texture, NO speckling, NO shadow, NO scenery — nothing but clean white behind the bird. The bird is the ONLY element; the perch is implied by toe posture, NEVER drawn. NO border or frame, NO text or signature.

Composition: the bird occupies one-third to one-half of the frame, in clear SIDE PROFILE, body held HORIZONTALLY (wider than tall), with generous negative space around it.

The ENTIRE bird must fit within the frame: head, both wings, full tail, both legs, both feet, beak — nothing cropped at the edge. Leave generous padding on all sides.

### Reference handling

- IMAGE 1 (positive, anatomy) IS {com_name}. Match its proportions, head colour, throat, wing pattern, back colour, tail pattern, leg colour, and overall plumage colours FAITHFULLY. If the reference shows non-breeding or worn plumage, render the brightest BREEDING (adult-summer) plumage. Treat IMAGE 1 for ANATOMY and COLOUR only — do NOT copy its photographic texture, lighting, or background.
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
