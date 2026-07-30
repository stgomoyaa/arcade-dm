# Arcade DM

Deathmatch arcade **todo-en-uno** para Counter-Strike 1.6 y Condition Zero. Un solo plugin de AMX Mod X que convierte una partida local contra bots en un entrenamiento de puntería con progresión, recompensas y dopamina constante.

Pensado para jugar **solo contra bots** (YaPB o los ZBot nativos de CZ) y usarlo como calentamiento serio antes de un juego táctico moderno.

![license](https://img.shields.io/badge/license-MIT-green) ![amxx](https://img.shields.io/badge/AMX%20Mod%20X-1.9%2B-blue)

---

## Qué hace

**FFA de verdad.** El motor de GoldSrc recorta el daño entre compañeros al ~35 %; el plugin lo compensa para que todos peguen igual, elimina los avisos de *teamkill*, quita castigos, corrige el marcador y limpia el radar de aliados. En la práctica: todo el mundo contra todo el mundo, sin fricción.

**Killfeed propio.** Reemplaza el monocromo del juego por uno de cinco líneas a color: tus bajas en dorado, headshots en naranja, tus muertes en rojo, el ruido de fondo en gris. Cada línea muestra el rango de ambos jugadores.

**Dos progresiones separadas.**

| | Qué mide | Escalera |
|---|---|---|
| **Puntos** | Qué tan dominante eres | Hierro → Grandmaster (divisiones I/II/III) → **CAMPEÓN** #15000→#1 nacional → **REY** regional → **DEIDAD** mundial → prestigio |
| **Puntería** | Qué tan bien disparas | La misma escalera, pero calculada sobre la *calidad* de cada baja |

El rango de puntería es una media móvil de: headshot, tiempo hasta la baja (TTK), **disciplina de parada** (tu velocidad en el disparo que mata — el counter-strafe) y **economía de disparo** (impactos hasta la baja, con listón distinto por arma). No baja al morir: mide cómo disparas, no cómo sobrevives. Está calibrado con los porcentajes de headshot reales del CS competitivo, y los tres rangos superiores **no se alcanzan solo con HS%**: exigen las cuatro cosas.

**Combos sincronizados.** Doble → Triple → Ultra → Monster → Ludicrous → Holy Shit → Wicked Sick → Cadena. El sonido, el banner, la medalla y el buff salen de **una sola tabla**, así que caen en el mismo instante y con el mismo nombre.

**Recompensas por racha.**

- **4 rápidas** → Vampiro: cada baja te cura, hasta que mueras
- **5 rápidas** (Monster kill) → Vampiro++: además recarga el arma al máximo en cada baja
- **9 rápidas** (Cadena) → **Tiempo bala**: los bots caen al 40 % de velocidad 5 s
- **Racha 15** → **UAV**: ESP a través de paredes, un barrido cada 5 s durante un minuto
- **Racha 30** → **NUKE**: cae el mapa entero y todas las bajas cuentan para ti

**22 medallas** estilo Black Ops II con bonus de puntos, **leaderboard** con 32 rivales que progresan contigo, **némesis** (el bot que más te mata), **killcam** al morir, equipamiento automático, bunnyhop y números de daño flotantes.

---

## Instalación

1. Requisitos: **AMX Mod X 1.9 o superior** con los módulos `fun`, `engine`, `fakemeta`, `hamsandwich`, `cstrike`, `nvault` activados en `configs/modules.ini`.
2. Copia `addons/amxmodx/plugins/arcade_dm.amxx` a `cstrike/addons/amxmodx/plugins/`.
3. Añade `arcade_dm.amxx` al final de `cstrike/addons/amxmodx/configs/plugins.ini`.
4. Copia el contenido de `configs/listenserver.cfg` a tu `cstrike/listenserver.cfg`.
5. (Opcional) Sonidos: coloca los `.wav` en `cstrike/sound/AQS/`. Sin ellos el mod funciona igual, solo en silencio. Ver [Sonidos](#sonidos).

Para compilar desde el fuente:

```bash
amxxpc addons/amxmodx/scripting/arcade_dm.sma -o addons/amxmodx/plugins/arcade_dm.amxx
```

---

## Bots

El plugin no incluye bots: usa los que ya tengas.

- **CS 1.6**: [YaPB](https://github.com/yapb/yapb) es la opción recomendada (compatible con el build actual del juego). El plugin ajusta `yb_difficulty` automáticamente según tu rango de puntería, con tope suave para no romper el ritmo arcade.
- **Condition Zero**: los ZBot nativos funcionan sin nada extra.

> **Aviso**: en CS 1.6 actual (build post-aniversario), los packs antiguos que reemplazan `mp.dll` con binarios de 2006 **crashean el juego**. Usa YaPB o ReGameDLL, no esos packs.

---

## Cvars

| Cvar | Def. | Qué hace |
|---|---|---|
| `adm_ffa` | 1 | FFA: daño completo entre equipos, sin avisos de teamkill, radar limpio |
| `adm_killfeed` | 1 | Killfeed propio (0 = deja el original del juego) |
| `adm_equip` | 1 | Armas automáticas al reaparecer |
| `adm_bhop` | 1 | Bunnyhop automático |
| `adm_sounds` | 1 | Anuncios de voz estilo Quake |
| `adm_damage_numbers` | 1 | Números de daño flotantes |
| `adm_streaks` | 1 | Vampiro, tiempo bala, UAV y nuke |
| `adm_adaptive_bots` | 1 | La dificultad de los bots sigue a tu puntería (tope 2 de 4) |

Escribe **`guns`** en el chat para cambiar tu equipamiento (10 primarias, 5 secundarias). Se recuerda toda la sesión.

---

## Sonidos

El mod busca los `.wav` en `sound/AQS/`. Son los clásicos anuncios de Quake/UT, disponibles en el repositorio [AdvancedQuakeSounds](https://github.com/ClaudiuHKS/AdvancedQuakeSounds) de ClaudiuHKS.

Archivos que usa: `doublekill`, `triplekill`, `ultrakill`, `monsterkill`, `ludicrouskill`, `holyshit`, `whickedsick`, `comboking`, `impressive`, `payback`, `shutdown`, `flawlessvictory`.

---

## Canales de HUD

GoldSrc solo tiene 16 canales de mensaje y cualquier plugin que use canal automático (`-1`) puede pisar a otro. Aquí están repartidos de forma fija:

```
 1  estado permanente        6-10  killfeed
 2  popups de puntos          11   banner de combo
 3  paneles (tablas)          12   buffs activos
 4  anuncios grandes         13-15 números de daño
 5  animaciones
```

Si añades otro plugin con HUD, dale un canal libre o verás parpadeos.

---

## Créditos

- **Vampiro**: basado en el plugin *Vampire* de **Shalfey** (2007), convertido aquí en buff persistente.
- **ESP a través de paredes**: técnica del ESP de *AmxX Cheats* de **DarkGL** — el marcador se proyecta sobre la pared donde impacta el trazo, porque los beams se ocluyen con la geometría.
- **Números de daño**: adaptado del *Rotating DMG 6-dir HUD* de **LyesMC**.
- **Sonidos**: pack *AdvancedQuakeSounds* de **ClaudiuHKS**.
- Rangos, ladder, medallas, combos, killfeed, tiempo bala y sistema de puntería: originales de este proyecto.

## Licencia

MIT — ver [LICENSE](LICENSE).
