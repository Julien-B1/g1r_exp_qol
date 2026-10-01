EXP QoL adds a selectable 1x, 2x, 5x, 10x, or 100x battle EXP rate to Pokemon Emerald. Persona: QoL tinkerer.

Enable the mod in the mod manager, then open START > OPTIONS > BATTLE OPTIONS > EXP. MULT. and use left/right to choose a rate. The default is 1x.

The mod requests `engine_internals` access to add its row to Emerald's options menu, which does not currently expose the general options-row hook.

Pull requests targeting `main` or `master` run the mod test, strict validation, lint, and packaging checks. A successful merge publishes a `vX.Y.Z` GitHub Release with an installable ZIP; the manifest's GitHub source enables the game's Update and Versions controls. Releases begin at `0.0.1` and increment the patch component after each merged pull request.

Run these commands from the workspace root:

```sh
python3 gen1recomp/tools/modkit.py --repo gen1recomp validate mods/exp_qol --base imported
python3 gen1recomp/tools/modkit.py --repo gen1recomp lint mods/exp_qol
python3 gen1recomp/tools/modkit.py --repo gen1recomp pack mods/exp_qol -o exp_qol-0.0.1.modpkg
```