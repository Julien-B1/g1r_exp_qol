EXP QoL adds a selectable 1x, 2x, 5x, 10x, or 100x battle EXP rate, and a 5-mode Exp Share, to Pokemon Emerald. Persona: QoL tinkerer.

Enable the mod in the mod manager, then open START > OPTIONS > BATTLE OPTIONS. Use left/right on EXP. MULT. to choose a rate (default 1x) and on EXP SHARE to choose a sharing mode (default OFF). Both selectors save with the rest of the in-game options.

## Exp Share modes

Each mode replaces how exp from a defeated Pokemon is split across your party. `calculated = floor(expYield(foe) * foeLevel / 7)` is the same "solo kill" base the game already computes; `n` is the number of living, sub-level-100 party members.

- **OFF** -- vanilla Emerald. Only the Pokemon that fought (or a personal Exp Share item holder) gains exp.
- **OLD SCHOOL** -- Gen 1's party-wide Exp. All. Battlers keep `floor(calculated / participants)` and everyone (battlers included) also gets a bonus `floor(calculated / (2n))`.
- **MODERN** -- the modern Exp Share toggle. Battlers keep the full, undivided `calculated`; every bench Pokemon gets a flat `floor(calculated * 0.5)`.
- **FULL** -- every eligible Pokemon gets the full `calculated`, undivided and unreduced.
- **BALANCE** -- a fixed pool (`calculated`) split by distance from the level cap: `share_i = floor(calculated * (100 - level_i) / sum(100 - level_j))`, so the lowest-level member of the team catches up fastest.

Lucky Egg, trainer-battle, and traded-mon bonuses (each x1.5, floored) still apply on top, same as vanilla.

The mod requests `engine_internals` access to add its rows to Emerald's options menu and to widen the Exp Share recipient set, since neither is exposed as a public hook today.

Pull requests targeting `main` or `master` run the mod test, strict validation, lint, and packaging checks. A successful merge publishes a `vX.Y.Z` GitHub Release with an installable ZIP; the manifest's GitHub source enables the game's Update and Versions controls.

Run these commands from the workspace root:

```sh
python3 gen1recomp/tools/modkit.py --repo gen1recomp validate mods/exp_qol --base imported
python3 gen1recomp/tools/modkit.py --repo gen1recomp lint mods/exp_qol
python3 gen1recomp/tools/modkit.py --repo gen1recomp pack mods/exp_qol -o exp_qol-0.0.1.modpkg
```