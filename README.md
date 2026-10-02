# GameLoop Keymapping Copy (PUBG Mobile ⇄ PUBG Mobile Flash)

**Set your buttons up once — copy the whole layout onto your other game build.**

One click. No install. No re-dragging 130 buttons.

```
You, yesterday:   com.tencent.ig        [ ============ 130 buttons ============ ]
                  com.tencent.igfit     [ ]

You, today:       com.tencent.ig        [ ============ 130 buttons ============ ]
                  com.tencent.igfit     [ ============ same 130 buttons ====== ]
```

---

## The problem

If you play two builds of the same game — PUBG Mobile and PUBG Mobile Flash being the
common pair — GameLoop treats them as **two completely separate apps**.

That means your keymapping does not carry over. You set up every button: fire, scope,
lean, peek, crouch, jump, vehicle slots, the lot. Then you open the other build and
there is nothing there. So you either play badly on one of them, or you spend an hour
dragging buttons around a second time.

GameLoop has no "export layout" / "import layout" button. Your layout lives in one config
file, and both games are in it — so copying is perfectly possible, there is just no UI
for it.

**This is that UI.**

---

## What it does

It copies one game's **entire keymapping** onto another, inside GameLoop's own config
file.

| | |
| --- | --- |
| **Copies** | Every `<KeyMapMode>` block — Normal 720P, Smart 720P, Smart 1080P, Smart 2K, and anything else you have — with all of their `<KeyMapping>` / `<KeyMappingEx>` entries. |
| **Leaves alone** | The target's name and version header, its `<StartInfo>` and `<LastMode>`, its `<VersionInfo>`, and its feature list. |

So the layout arrives complete, but the target game stays the target game.

---

## Why it does *not* copy the feature list

Each `<Item>` in the config has a list of features that build supports:

```xml
<Switch Name="Parachute" TextureId="12"/>
<Switch Name="Climb"     TextureId="44"/>
<Switch Name="Hand"      TextureId="103"/>
```

Two builds of the same game can genuinely support different things — one has ski and
cable car and snowboard modes, the other does not. That list describes **what the game
itself supports**, not what your buttons look like. Copying one build's list over the
other's is a good way to break things.

So it is left alone.

**These lists are matched by `Name`, never by `TextureId`.** The `TextureId` is only a
sprite index *inside one build*, and the same number means different things in different
builds. In a real pair: id `103` is `Hand` in one build and `Sw1to3` in the other. Any
tool that matches those by number will silently copy the wrong thing.

If the source uses a feature the target does not have, the script **tells you before it
copies**, so there are no surprises:

```
[warn] 16 feature(s) used by com.tencent.ig are not in com.tencent.igfit's list:
          Bicycle, Climb, Hand, Medicine6, shield, Shop, weapen, Whistle1 ...
       Those toggles will simply do nothing on the target. The button layout
       itself is copied either way.
```

Your buttons all land in the right place. Only the handful of toggles that build does not
support do nothing — which is exactly what would happen if you placed them by hand.

---

## Requirements

* Windows 10 or 11
* GameLoop installed
* **Both games opened at least once** so GameLoop has written them into the config
  (a game that has never been launched is not in the list yet)
* Windows PowerShell 5.1 (built into Windows — nothing to install)

No Python. No Node. No dependencies.

---

## Quick start

1. **Close GameLoop completely** — including the tray icon. The file is rewritten when
   the emulator shuts down, so an edit made while it is running is lost.
2. Double-click **`run.bat`**.
3. Press **`1`** first if you want to see the exact package names you have.
4. Press **`2`**, type the game to copy *from*, then the game to copy *onto*.
5. Done. Open GameLoop, launch the target game, check your controls.

If you play PUBG Mobile and PUBG Mobile Flash, **menu option `3`** does the whole thing
with no typing.

### Menu

| Key | What it does |
| --- | --- |
| `1` | Show every game in the config, and how many keymap modes each one has. |
| `2` | Copy a keymapping — asks for the source and target package names. |
| `3` | Quick copy: `com.tencent.ig` → `com.tencent.igfit`. |
| `4` | See what would change, side by side. Changes nothing. |
| `5` | Preview the plan, write nothing. |
| `6` | Undo — restore the newest backup. |

---

## Command line

```powershell
.\Copy-KeyMapping.ps1 -List        # what games do I have?
.\Copy-KeyMapping.ps1 -Diagnose    # source vs target, in detail. changes nothing
.\Copy-KeyMapping.ps1              # copy com.tencent.ig -> com.tencent.igfit
.\Copy-KeyMapping.ps1 -DryRun      # preview, write nothing
.\Copy-KeyMapping.ps1 -Restore     # undo
```

Options:

| Option | Default | Meaning |
| --- | --- | --- |
| `-From <package>` | `com.tencent.ig` if present | The game to copy **from** (the one you set up) |
| `-To <package>` | `com.tencent.igfit` if present | The game to copy **onto** |
| `-VmId <ids>` | all VMs | Only touch these GameLoop VM ids, e.g. `-VmId 100` |
| `-ConfigDir <path>` | auto | Look in this folder, and only this folder |
| `-List` | | List the games, then exit |
| `-Diagnose` | | Show the detail, change nothing |
| `-DryRun` | | Show the plan, write nothing |
| `-Restore` | | Undo — restore the newest backup |
| `-Yes` | off | Skip the confirmation prompt |
| `-Force` | off | Skip the "GameLoop is running" guard. Not recommended. |

Examples:

```powershell
# any two games, by package name
.\Copy-KeyMapping.ps1 -From com.dts.freefireth -To com.garena.game.kgth

# only my main profile
.\Copy-KeyMapping.ps1 -VmId 100

# see exactly which modes and how many buttons would move
.\Copy-KeyMapping.ps1 -Diagnose
```

---

## What it covers

Nothing is hard-coded to one setup:

| | |
| --- | --- |
| **Every resolution** | Copies every `KeyMapMode` block — Normal 720P, Smart 720P, Smart 1080P, Smart 2K, and anything else. Not just the one you are using. |
| **Any two games** | Not limited to PUBG. Anything GameLoop has in the config, matched by package name. |
| **Every profile** | Works on every `TVM_<id>.xml` it finds, so any VM / profile you play on is covered. |
| **Both engine builds** | The 32-bit and the 64-bit GameLoop engines share the same keymapping file, so one run covers both. |
| **Any layout** | It copies the mapping *entries*, not a fixed set of keys — so a fully rebound, custom layout comes across intact. |

---

## Safety

Your config file is the only thing it touches, and it is treated carefully.

**Before writing**

* GameLoop's emulator must be closed (it refuses otherwise — `-Force` overrides).
* A timestamped backup is written next to your config:
  `TVM_100_backup_keymap-clone_2026-10-03_011156.xml`
* The new file is built **in memory first**, then verified by splicing everything except
  the copied region back into it and comparing that **character-for-character** with the
  original. If anything outside the copied region moved by even one character, nothing is
  written.

**After writing**

* The file is read back from disk and compared **byte-for-byte** with what was built.
* If it does not match, the backup is restored automatically and the script stops.

**What it deliberately does not do**

* No BOM. GameLoop writes UTF-8 without one, and the script keeps it that way.
* No re-serialising through an XML parser. The file is not valid XML as written (it has
  no single root element), and re-encoding it would reformat ~280 KB and mangle the
  Chinese text in the button names. Everything is a surgical text-level edit.
* No touching of line endings, the target's other settings, or the feature list.
* Copying the same pair twice gives the same file — the second run is a no-op.

---

## Undo

```powershell
.\Copy-KeyMapping.ps1 -Restore
```

or press **`6`** in `run.bat`. This restores the newest backup, byte-for-byte.

Your backups are ordinary files sat next to the config:

```
%APPDATA%\AndroidTbox\TVM_100_backup_keymap-clone_<date>_<time>.xml
```

---

## FAQ

**Is this a cheat / will I get banned?**
No. It edits your own button layout on your own machine — the same thing you are already
allowed to do by hand in GameLoop's key-mapping UI. It gives you no advantage the UI does
not already give you, and it touches nothing but GameLoop's local config file.

**Will it overwrite the target's buttons without asking?**
No. It shows you a plan first and asks for confirmation, and it writes a timestamped
backup before it touches anything.

**Can I copy the other way round too?**
Yes. `-From` and `-To` are just package names, in either direction.

**The game I want is not in the list.**
Launch it once in GameLoop and close GameLoop. Until it has been opened, GameLoop has not
written it into the config, so there is nothing to copy onto yet.

**Some toggles do nothing after copying.**
Those are the features the target build does not support — the script warned you about
them before copying. Everything else works.

**Does it copy my mouse / aim sensitivity?**
No. Only the keymapping layout. Sensitivity lives in the game, not in this file.

**What about different resolutions?**
All of them come across, because every `KeyMapMode` block is copied, not just the active
one.

**What is the risk?**
If something went wrong you would lose the target's button layout — which is why the
script backs up first, verifies the edit character-for-character before writing, verifies
the bytes on disk afterwards, and can restore itself automatically.

---

## Roman Urdu

**Masla:** GameLoop do builds (jaise PUBG Mobile aur PUBG Mobile Flash) ko **do alag alag
apps** samajhta hai. Is liye tumhara keymapping ek se doosre par nahi jata. Ek build mein
poora layout set karne ke baad, doosri build kholne par **kuch bhi nahi** hota — aur
GameLoop mein "export / import layout" ka koi button bhi nahi hai. To ya to tum ek build
par bure khelte ho, ya doosri baar ghanton buttons drag karte ho.

**Hal:** Yeh script ek game ka **poora keymapping** doosre game par copy kar deti hai —
seedha GameLoop ki config file ke andar. Har `KeyMapMode` block (Normal 720P, Smart 720P,
Smart 1080P, Smart 2K) apne saare buttons ke saath.

**Feature list copy nahi hoti — aur yeh jaan boojh kar hai.** Har build ke paas apni
features ki list hoti hai (ski, cable car, snowboard waghera). Do builds mein woh list
alag ho sakti hai, aur woh **game** ke baare mein batati hai ke woh kya support karta hai
— tumhare buttons ke baare mein nahi. Is liye usay chhoda jata hai. Agar source koi aisi
feature use karta hai jo target build mein nahi, to script **copy se pehle bata deti hai**
— layout phir bhi poora copy hota hai, bas woh khaas toggles target par kuch nahi karenge.

**Ahem baat:** woh list **naam** se match hoti hai, **number se kabhi nahi**. `TextureId`
sirf usi build ke andar ka sprite number hai, aur wahi number doosri build mein kuch aur
matlab rakhta hai (ek asli jodi mein: `103` ek build mein `Hand` hai, doosri mein
`Sw1to3`). Jo tools number se match karte hain, woh chupke se ghalat cheez copy kar dete
hain.

**Chalane ka tareeqa:** GameLoop **poora band** karo (tray icon bhi), **`run.bat`** par
double-click karo, aur **`2`** dabao — phir copy *from* aur copy *to* wale package names
likho. Agar tum PUBG Mobile aur PUBG Mobile Flash khelte ho, to **option `3`** se poora
kaam bina kuch type kiye ho jata hai.

**Zaroori:** jis game par copy karna hai woh GameLoop mein **kam az kam ek baar khula** hona
chahiye, warna woh config mein mojood hi nahi hoga.

**Wapas purana karna ho:** option **`6`** (ya `-Restore`). Sab se naya backup byte-by-byte
wapas laga deta hai.

---

## License

MIT — see [LICENSE](LICENSE).

Not affiliated with Tencent, GameLoop, or TxGameAssistant. Use at your own risk.

---

## Related

* The other half of the same problem — GameLoop's sluggish WASD direction changes, and the
  `FlashArrive` trap — lives in
  [gameloop-pubgm-wasd-speed-fix](https://github.com/Ahsuu27488/gameloop-pubgm-wasd-speed-fix).

* Prior art worth a look: [code-fanatic/Gameloop-iPad-view-Keymapping](https://github.com/code-fanatic/Gameloop-iPad-view-Keymapping).
