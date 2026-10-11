# Licensed fonts (not committed)

The game ships with free stand-ins (Cinzel, Michroma, Saira). If you own licences for the
intended fonts, drop them in this folder with these names and the game uses them instead:

| File | Used for | Intended font |
| --- | --- | --- |
| `title.ttf` or `title.otf` | Title screen, logos, screen titles | Copperplate Gothic Bold |
| `heading.ttf` or `heading.otf` | Section headings in menus and the HUD | Microgramma |
| `body.ttf` or `body.otf` | Buttons, labels and all other text | Eurostile |

Everything here except this file is ignored by git, so the fonts stay on your machine. Check the
licence before shipping a build with them: a desktop licence usually doesn't cover embedding a
font in a distributed game.
