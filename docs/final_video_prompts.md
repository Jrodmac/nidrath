# Final de Nidrath (huida en helicóptero): prompts para vídeo con IA

Este vídeo sale cuando el jugador sube al helicóptero en la azotea. Después del vídeo, el juego
muestra «HAS ESCAPADO», las estadísticas y los botones. Si el archivo no existe, el juego
muestra solo esa pantalla, así que puedes generarlo cuando quieras.

**Importante:** los filtros de estas IAs rechazan cuerpos, armas, sangre, «mafia», «gunmen»,
balas, etc. Estos prompts no tienen nada de eso: la tensión sale de la lluvia, la luz y la
prisa. Si alguno se sigue rechazando, quita la frase más «dura» y reintenta.

## Cómo trabajar

1. Usa **la misma imagen de referencia del protagonista** que en la intro.
2. Genera cada plano por separado (5–8 s), en **16:9 y 24 fps**.
3. Monta los planos en orden, unos **18–22 s** en total.
4. Exporta en **1280×720, H.264** y guárdalo como `assets/video/final.mp4`.

## Estilo común (añádelo al final de cada plano)

```
Cinematic, photorealistic, night, heavy rain, wet reflections, teal and orange color grade,
35mm anamorphic lens, shallow depth of field, film grain, no text, no logos.
```

## Planos

### 1 · El helicóptero llega
```
Low angle shot from a wet rooftop at night: a dark helicopter slowly descends through heavy
rain toward a yellow painted helipad, its searchlight sweeping across the puddles, rain
blowing sideways under the rotors, a small red light blinking.
```

### 2 · Carrera hacia el helipuerto
```
Tracking shot from behind: a tired man in an olive-green rain jacket with a backpack runs
across a flooded rooftop toward a landed helicopter, its bright searchlight shining into
the camera, splashing through puddles.
```

### 3 · Dentro
```
Close-up inside a helicopter cabin with soft red interior light: the man in the olive-green
rain jacket takes the pilot's gloved hand and climbs in, soaked and out of breath, rain
blowing through the open side door.
```

### 4 · Despegue
```
Wide shot from the rooftop: the helicopter lifts off and tilts away into the stormy night
sky, rain swirling under the rotors, the rooftop stairwell door swinging open in the wind.
The helicopter rises out of frame.
```

### 5 · Adiós al centro comercial
```
Aerial shot looking down from a helicopter: a huge abandoned shopping mall on the edge of
a city at night in the rain, a broken neon sign, an empty flooded parking lot with old cars.
Through a skylight, a soft violet glow pulses once and fades into darkness. The camera
slowly rises and pulls away.
```

### 6 · Amanecer
```
Inside a helicopter, side profile of the man in the olive-green jacket by the window, dawn
breaking over a distant city skyline, the rain stopping, warm golden sunlight on his tired
face. He smiles slightly and closes his eyes. Slow push-in, calm, hopeful ending.
```

**Consejo:** si el helicóptero cambia de forma entre planos, genera primero una imagen fija
del helicóptero y úsala como referencia en los planos 1, 3 y 4.
