# Intro de Nidrath — prompts para vídeo con IA

Herramientas: Kling 2.x, Runway Gen-4, Veo 3 o Sora. Los prompts van en inglés porque
estos modelos lo entienden mejor.

## Cómo trabajar

1. **Primero, una imagen de referencia del protagonista** (Midjourney, Flux, Ideogram o la
   propia herramienta de vídeo). Usa *siempre esa misma imagen* como referencia
   (image-to-video / "character reference") en todos los planos, para que no cambie de cara.
2. Genera cada plano por separado (5–8 s), en **16:9, 24 fps, sin audio**.
3. Monta los planos en orden (CapCut, DaVinci Resolve) hasta ~35 s. El audio, la narración
   y los subtítulos los pone el juego.
4. Exporta en **1280×720, H.264** (o H.265), sin audio, y guárdalo como
   `assets/video/intro.mp4`. Avísame y lo integro con `video_player`.

**Consejo:** los textos de carteles (ej. "CENTRO COMERCIAL") suelen salir deformados. Si pasa,
pide el cartel sin texto ("blank sign") y lo ponemos encima desde el juego.

## Imagen de referencia del protagonista

```
Photorealistic full-body portrait of a man in his early 30s, exhausted and frightened,
short dark brown hair soaked by rain, three-day stubble, dark circles under his eyes,
worn olive-green rain jacket, dark jeans, grey sneakers, black backpack with a faint cyan
light leaking from the zipper. Standing on a wet city street at night, heavy rain,
cold sodium streetlight, cinematic, 35mm, shallow depth of field, film grain.
```

## Estilo común (añádelo al final de cada plano)

```
Photorealistic, cinematic thriller, night, heavy rain, wet asphalt reflections,
cold desaturated teal-blue color grade with warm sodium streetlights, handheld camera,
subtle camera shake, 35mm anamorphic lens, shallow depth of field, film grain,
dark and claustrophobic atmosphere, no text, no logos.
```

**Negativo** (si la herramienta lo admite):
```
cartoon, 3d render, video game, anime, smiling, daylight, extra limbs, distorted face,
morphing, blurry face, text, watermark
```

## Planos (siguiendo el guion de la intro)

| # | Tiempo | Narración que va encima |
|---|--------|-------------------------|
| 1 | 0–6 s | «Llevo tres noches sin dormir…» |
| 2 | 6–9.5 s | «No diré qué es…» |
| 3 | 9.5–11 s | ¡NO DEJÉIS QUE ESCAPE! |
| 4 | 11–13.3 s | «La mafia lo quiere…» |
| 5 | 13.3–14.7 s | (disparo) |
| 6 | 14.7–17.5 s | ¡POR ALLÍ! ¡HACIA LAS AFUERAS! |
| 7 | 17.5–22 s | «Las afueras. Aquí la ciudad se rinde.» |
| 8 | 22–28 s | «El viejo centro comercial…» |
| 9 | 28–35 s | «Si la encuentro…» → portazo |

### 1 · Huida por la ciudad (por detrás)
```
Over-the-shoulder tracking shot from behind: the man with the black backpack runs
desperately down an empty narrow city street at night, rain pouring, his breath visible,
puddles splashing under his sneakers, flickering streetlights, closed shops with metal
shutters. The camera runs right behind him, shaky and close. He glances back over his
shoulder once, terrified.
```

### 2 · Detalle: pies y respiración
```
Extreme close-up, low angle: worn grey sneakers splashing through deep puddles on wet
asphalt at night, water spraying in slow motion, streetlight reflections broken by the
impact. Then quick tilt up to his face in profile, panting, rain running down his face,
eyes wide with fear.
```

### 3 · Subjetivo: los perseguidores
```
Point-of-view shot looking back while running, unstable handheld camera: far down the
rainy street a black car with blinding headlights, and three dark silhouettes in long
coats running towards the camera, their flashlight beams cutting through the rain and
sweeping across the wet asphalt. Lens flare, rain drops on the lens. Faces never visible.
```

### 4 · Travelling lateral junto a persianas
```
Side tracking shot at running speed: the man sprints past a row of graffiti-covered metal
shutters and broken shop windows, a streetlight above him flickers and dies. Flashlight
beams from behind sweep across the wall next to him, catching his shadow.
```

### 5 · Subjetivo: disparo
```
Point-of-view looking back, violent camera shake: one of the silhouettes in a long coat
stops, raises a pistol and fires; bright muzzle flash in the rain. Cut to a bullet hitting
the brick wall right next to the camera, sparks and dust exploding.
```

### 6 · Se agacha y sigue
```
Low angle tracking shot from the front: the man flinches and ducks after the gunshot,
almost slips on the wet ground, recovers and keeps running towards the camera,
the city buildings behind him getting lower and sparser, chain-link fences appear.
```

### 7 · Las afueras
```
Wide static shot, very dark: an empty two-lane road leaving the city at night, heavy rain,
broken streetlights, a rusty fence and wasteland on both sides, a green road sign
"CENTRO COMERCIAL 500 m". A tiny lone figure with a backpack runs along the road;
far behind him, the headlights of the pursuers slowly fade and turn away.
```

### 8 · El centro comercial abandonado
```
Slow push-in towards a huge abandoned shopping mall at night in the rain: half the
pink neon letters of the sign "CENTRO COMERCIAL" flicker or are dead, broken windows,
an empty flooded parking lot with abandoned shopping carts. Behind the dirty glass
entrance doors, a faint, unnatural violet glow pulses. The man, seen from behind,
slows down and stops, catching his breath, staring at the building.
```

### 9 · La puerta
```
Medium shot from behind: the man walks slowly towards the glass doors of the abandoned
mall, the violet glow inside illuminates his face and wet jacket. He pushes the door
and steps into the darkness. The door swings shut violently behind him; the camera stays
outside in the rain. Hold on the closed door, then cut to black.
```
