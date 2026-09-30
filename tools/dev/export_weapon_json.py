#!/usr/bin/env python3
# =============================================================================
#  ESL-MOD -- export the FINAL weapon stats to a single JSON file
#
#  Reproduces what tools/build.ps1 does to the weapons, then reads the result
#  back into docs/weapons.json for the website:
#
#      1. third_party/weapon_rebalance/weapons.iwd   (1192 files)
#      2. src/weapons/extra/*                        (ak74u_mp, m40a3_mp)
#      3. src/weapons/weapon-tweaks.txt              (the ESL-owned dvars)
#
#  One entry per weapon: the files collapse to the part of the name before the
#  first "_", and "<base>_mp" is preferred, exactly like tools/weapon-sheet.ps1
#  and the in-game footer.
#
#  The schema is built around what the mod actually changes:
#    * "esl_changed" holds {dvar: final value} for EVERY parameter ESL set on
#      that weapon, so the site can show precisely what the ruleset did;
#    * "esl_change_log" is the same as "old -> new" text;
#    * everything a TTK needs (damage pair, the curve, the multipliers, RPM,
#      magazine, reload, ADS and recoil) is present for every weapon, changed
#      or not, so the numbers can be compared across the board.
#
#  Usage:  python3 tools/dev/export_weapon_json.py [--out docs/weapons.json]
# =============================================================================

import argparse
import fnmatch
import json
import os
import re
import sys
import zipfile
from datetime import date

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, os.pardir, os.pardir))

IWD_PATH = os.path.join(ROOT, "third_party", "weapon_rebalance", "weapons.iwd")
EXTRA_DIR = os.path.join(ROOT, "src", "weapons", "extra")
TWEAKS_PATH = os.path.join(ROOT, "src", "weapons", "weapon-tweaks.txt")
VERSION_PATH = os.path.join(ROOT, "version.txt")
CHANGELOG_PATH = os.path.join(ROOT, "third_party", "weapon_rebalance", "changelog.txt")

PREFIX = "weapons/mp/"

# 1 game unit is 1 inch
INCH_TO_METRES = 0.0254

CLASS_NAMES = {
    "rifle": "Assault Rifle",
    "smg": "Submachine Gun",
    "mg": "Light Machine Gun",
    "sniper": "Sniper Rifle",
    "spread": "Shotgun",
    "pistol": "Handgun",
    "rocketlauncher": "Launcher",
    "grenade": "Grenade",
    "throwingknife": "Equipment",
    "riotshield": "Equipment",
    "item": "Equipment",
    "non-player": "Killstreak Vehicle",
    "turret": "Killstreak Turret",
    "other": "Special",
}

NAMES = {
    "ak47": "AK-47", "m16": "M16A4", "m4": "M4A1", "famas": "FAMAS",
    "scar": "SCAR-H", "tavor": "TAR-21", "fal": "FAL", "masada": "ACR",
    "fn2000": "F2000",
    "ump45": "UMP45", "mp5k": "MP5K", "p90": "P90", "uzi": "UZI",
    "kriss": "Vector", "ak74u": "AK-74u", "mp5": "MP5", "pp2000": "PP2000",
    "rpd": "RPD", "m240": "M240", "aug": "AUG HBAR", "mg4": "MG4",
    "sa80": "L86 LSW",
    "m9": "M9", "usp": "USP .45", "beretta": "M9 (Beretta)",
    "beretta393": "M93R (single)", "deserteagle": "Desert Eagle",
    "deserteaglegold": "Golden Desert Eagle", "coltanaconda": "Magnum .44",
    "tmp": "TMP", "g18": "G18", "m93r": "M93R", "glock": "Glock 18",
    "spas12": "SPAS-12", "ranger": "Ranger", "m1014": "M1014",
    "winchester1200": "Model 1887", "aa12": "AA-12", "striker": "Striker",
    "model1887": "Model 1887 (akimbo)",
    "cheytac": "Intervention", "barrett": "Barrett .50cal", "wa2000": "WA2000",
    "m21": "M21 EBR", "m40a3": "M40A3",
    "at4": "AT4", "rpg": "RPG-7", "thumper": "Thumper",
    "stinger": "Stinger", "javelin": "Javelin",
    "frag": "Frag Grenade", "semtex": "Semtex", "flash": "Flash Grenade",
    "concussion": "Stun Grenade", "smoke": "Smoke Grenade",
    "throwingknife": "Throwing Knife", "gl": "M203 (underbarrel)", "m79": "M79",
}

# The weapons ESL's ruleset and the bundled rebalance actually target.
META = {
    "ak47", "m16", "m4", "famas", "scar", "tavor", "fal", "masada", "fn2000",
    "ump45", "mp5k", "p90", "uzi", "kriss", "ak74u",
    "rpd", "m240",
    "cheytac", "barrett", "wa2000", "m21", "m40a3",
    "spas12",
    "deserteagle", "deserteaglegold", "coltanaconda",
    "tmp", "g18", "m93r",
    "at4", "rpg", "thumper",
}

# In weapons/mp but never equipped by a player: killstreak vehicles and
# turrets, the fallback weapon, and the perk assets that live here.
NON_PLAYABLE = {
    "defaultweapon", "airdrop", "onemanarmy", "scavenger",
    "ac130", "heli", "remotemissile", "littlebird",
    "cobra", "harrier", "pavelow", "sentry", "m79",
}

# changelog.txt says the retail name; map it onto the file id.
CHANGELOG_IDS = {
    "famas": "famas", "scarh": "scar", "tar21": "tavor", "m16a4": "m16",
    "acr": "masada", "f2000": "fn2000", "ak47": "ak47",
    "ump45": "ump45", "mp5": "mp5k", "p90": "p90", "uzi": "uzi",
    "rpd": "rpd", "m240": "m240",
    "intervention": "cheytac", "wa2000": "wa2000", "mk14ebr": "m21",
    "deserteagle": "deserteagle", "magnum": "coltanaconda", "spas12": "spas12",
    "tmp": "tmp", "g18": "g18", "m93r": "m93r",
    "at4": "at4", "thumper": "thumper", "rpg7": "rpg",
    "grenadelauncher": "gl", "stun": "concussion", "semtex": "semtex",
    "claymore": None,
}

# Hit-location multipliers: the five that decide damage, plus the rest only when
# the weapon actually sets them away from the stock 1.0.
CORE_LOCS = [
    ("head", "locHead"),
    ("helmet", "locHelmet"),
    ("neck", "locNeck"),
    ("upper_torso", "locTorsoUpper"),
    ("lower_torso", "locTorsoLower"),
]
EXTRA_LOCS = [
    ("left_arm_upper", "locLeftArmUpper"),
    ("right_arm_upper", "locRightArmUpper"),
    ("left_arm_lower", "locLeftArmLower"),
    ("right_arm_lower", "locRightArmLower"),
    ("left_leg_upper", "locLeftLegUpper"),
    ("right_leg_upper", "locRightLegUpper"),
    ("left_leg_lower", "locLeftLegLower"),
    ("right_leg_lower", "locRightLegLower"),
]

# The scalar fields each weapon carries, under the name the site should use.
SCALARS = [
    ("magazine_capacity", "clipSize"),
    ("reload_sec", "reloadTime"),
    ("reload_empty_sec", "reloadEmptyTime"),
    ("ads_in_sec", "adsTransInTime"),
    ("ads_out_sec", "adsTransOutTime"),
    ("ads_idle_amount", "adsIdleAmount"),
    ("ads_idle_speed", "adsIdleSpeed"),
    ("ads_move_speed_scale", "adsMoveSpeedScale"),
]

# The recoil group: the engine divides the view kick by these, so higher is less.
RECOIL = [
    ("center_speed_ads", "adsViewKickCenterSpeed"),
    ("center_speed_hip", "hipViewKickCenterSpeed"),
    ("pitch_max_ads", "adsViewKickPitchMax"),
    ("pitch_max_hip", "hipViewKickPitchMax"),
]


def read_text(path):
    with open(path, "r", encoding="utf-8", errors="surrogateescape") as handle:
        return handle.read()


def dvar_raw(text, name):
    match = re.search(r"\\" + re.escape(name) + r"\\([^\\]*)", text)
    return match.group(1).strip() if match else ""


def dvar_num(text, name, default=0.0):
    raw = dvar_raw(text, name)
    if raw == "":
        return default
    try:
        return float(raw)
    except ValueError:
        return default


def number(value):
    return int(value) if float(value).is_integer() else value


def load_weapons():
    files = {}

    with zipfile.ZipFile(IWD_PATH) as archive:
        for info in archive.infolist():
            if info.is_dir() or not info.filename.startswith(PREFIX):
                continue
            name = os.path.basename(info.filename)
            if name:
                files[name] = archive.read(info).decode("utf-8", "surrogateescape")

    if os.path.isdir(EXTRA_DIR):
        for name in sorted(os.listdir(EXTRA_DIR)):
            path = os.path.join(EXTRA_DIR, name)
            if os.path.isfile(path):
                files[name] = read_text(path)

    return files


def load_tweaks():
    rules = []

    if not os.path.isfile(TWEAKS_PATH):
        return rules

    for line in read_text(TWEAKS_PATH).splitlines():
        text = line.strip()
        if text == "" or text.startswith("#"):
            continue

        parts = text.split("|")
        if len(parts) < 3:
            continue

        rules.append(
            {
                "pattern": parts[0].strip(),
                "dvars": [d.strip() for d in parts[1].split(",") if d.strip()],
                "value": parts[2].strip(),
                "from": [v.strip() for v in parts[3].split(",") if v.strip()]
                if len(parts) >= 4
                else [],
                "keep": [v.strip() for v in parts[4].split(",") if v.strip()]
                if len(parts) >= 5
                else [],
            }
        )

    return rules


def load_changelog():
    notes = {}

    if not os.path.isfile(CHANGELOG_PATH):
        return notes

    for line in read_text(CHANGELOG_PATH).splitlines():
        text = line.strip()
        if text == "" or text.startswith("-") or ":" not in text:
            continue

        key, _, value = text.partition(":")
        weapon_id = CHANGELOG_IDS.get(re.sub(r"[^a-z0-9]", "", key.lower()))

        if weapon_id:
            notes.setdefault(weapon_id, []).append(value.strip())

    return notes


def apply_tweaks(files, rules):
    """Apply the ESL tweaks exactly as tools/build.ps1 does.

    Returns base -> {"changed": {dvar: value}, "log": ["dvar: old -> new"]}.
    """
    result = {}

    def base_of(name):
        return re.sub(r"_.*$", "", name)

    for rule in rules:
        for name in sorted(n for n in files if fnmatch.fnmatch(n, rule["pattern"])):
            base = base_of(name)
            text = files[name]

            for dvar in rule["dvars"]:
                pattern = re.compile(r"\\" + re.escape(dvar) + r"\\([^\\]*)")

                def replace(match, dvar=dvar, rule=rule, base=base):
                    current = match.group(1)

                    if current == rule["value"] or current in rule["keep"]:
                        return match.group(0)
                    if rule["from"] and current not in rule["from"]:
                        return match.group(0)

                    entry = result.setdefault(base, {"changed": {}, "log": []})
                    entry["changed"][dvar] = number(float(rule["value"])) \
                        if re.fullmatch(r"-?\d+(\.\d+)?", rule["value"]) else rule["value"]

                    note = "%s: %s -> %s" % (dvar, current, rule["value"])
                    if note not in entry["log"]:
                        entry["log"].append(note)

                    return "\\" + dvar + "\\" + rule["value"]

                text = pattern.sub(replace, text)

            files[name] = text

    return result


def rpm(text):
    """tools/weapon-sheet.ps1's real cycle: max(fireTime, bolt, rechamber > 0.2)."""
    cycle = dvar_num(text, "fireTime")
    bolt = dvar_num(text, "rechamberBoltTime")
    rechamber = dvar_num(text, "rechamberTime")

    if bolt > cycle:
        cycle = bolt
    if rechamber > 0.2 and rechamber > cycle:
        cycle = rechamber

    return int(round(60.0 / cycle)) if cycle > 0 else None


def shots_to_kill(damage_per_hit, health=100):
    return int(-(-health // damage_per_hit)) if damage_per_hit > 0 else None


def build_weapon(base, name, text, changes, changelog):
    dmg = dvar_num(text, "damage")
    min_dmg = dvar_num(text, "minDamage")

    if dmg <= 0:
        return None

    full_in = dvar_num(text, "maxDamageRange")
    min_in = dvar_num(text, "minDamageRange")
    weapon_class = dvar_raw(text, "weaponClass")

    multipliers = {}
    for label, dvar in CORE_LOCS:
        value = dvar_num(text, dvar, 1.0)
        if value:
            multipliers[label] = number(value)
    for label, dvar in EXTRA_LOCS:
        value = dvar_num(text, dvar, 0.0)
        if value and value != 1.0:
            multipliers[label] = number(value)

    rate = rpm(text)
    penetration = dvar_raw(text, "penetrateType")

    record = changes.get(base, {"changed": {}, "log": []})

    entry = {
        "id": base,
        "name": NAMES.get(base, base),
        "file": name,
        "category": CLASS_NAMES.get(weapon_class, weapon_class or "Unknown"),
        "weapon_class": weapon_class,
        "playable": weapon_class not in ("non-player", "turret") and base not in NON_PLAYABLE,
        "fire_type": dvar_raw(text, "fireType"),
        "damage": {
            "max": number(dmg),
            "min": number(min_dmg),
            "range_full_meters": int(round(full_in * INCH_TO_METRES)),
            "range_min_meters": int(round(min_in * INCH_TO_METRES)),
        },
        "multipliers": multipliers,
        "fire_rate_rpm": rate,
        "penetration": penetration or "none",
        "recoil": {},
        "is_meta": base in META and rate is not None,
        "modified_by_esl": base in changes,
        "esl_changed": record["changed"],
        "esl_change_log": record["log"],
        "rebalance_notes": changelog.get(base, []),
    }

    for key, dvar in SCALARS:
        if dvar_raw(text, dvar) != "":
            entry[key] = number(dvar_num(text, dvar))

    for key, dvar in RECOIL:
        if dvar_raw(text, dvar) != "":
            entry["recoil"][key] = number(dvar_num(text, dvar))

    if not entry["recoil"]:
        del entry["recoil"]

    return entry


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=os.path.join(ROOT, "docs", "weapons.json"))
    args = parser.parse_args()

    version = ""
    if os.path.isfile(VERSION_PATH):
        for line in read_text(VERSION_PATH).splitlines():
            text = line.strip()
            if text and not text.startswith("#"):
                version = text
                break

    files = load_weapons()
    rules = load_tweaks()
    changelog = load_changelog()
    changes = apply_tweaks(files, rules)

    read = {}
    bare = {}
    for name in sorted(files):
        base = re.sub(r"_.*$", "", name)
        read.setdefault(base, name)
        if name == base + "_mp":
            bare[base] = name
    read.update(bare)

    weapons = []
    for base in sorted(read):
        entry = build_weapon(base, read[base], files[read[base]], changes, changelog)
        if entry:
            weapons.append(entry)

    weapons.sort(key=lambda w: (not w["playable"], w["category"], w["name"]))

    payload = {
        "last_updated": date.today().isoformat(),
        "mod": {
            "name": "ESL-MOD",
            "version": version,
            "game": "IW4x (Call of Duty: Modern Warfare 2, 2009)",
            "ruleset": "competitive Search & Destroy - no perks, no killstreaks, no deathstreaks",
        },
        "source": {
            "rebalance": "third_party/weapon_rebalance/weapons.iwd",
            "esl_added_weapons": "src/weapons/extra (ak74u_mp, m40a3_mp)",
            "esl_tweaks": "src/weapons/weapon-tweaks.txt",
            "read_from": "the tweaked payload - the same numbers the match uses",
            "generator": "tools/dev/export_weapon_json.py",
        },
        "units": {
            "damage": "per-shot damage; min is the value at the end of the drop curve",
            "range_meters": "distance in metres; 'full' is where max damage ends, 'min' where it reaches minDamage",
            "fire_rate_rpm": "round(60 / max(fireTime, rechamberBoltTime, rechamberTime if > 0.2))",
            "time_sec": "seconds",
            "multipliers": "per-hit-location damage multiplier (missing limbs default to 1.0)",
            "recoil_center_speed": "higher is less recoil (the engine divides the view kick by it)",
            "ads_move_speed_scale": "multiplier on the movement speed while aiming",
            "esl_changed": "{dvar: final value} for every parameter ESL set on that weapon",
        },
        "stats": {
            "weapons": len(weapons),
            "playable_weapons": sum(1 for w in weapons if w["playable"]),
            "weapon_files_in_archive": len(files),
            "esl_tweak_rules": len(rules),
            "esl_modified_weapons": len(changes),
        },
        "weapons": weapons,
    }

    out_dir = os.path.dirname(args.out)
    if out_dir and not os.path.isdir(out_dir):
        os.makedirs(out_dir)

    with open(args.out, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    compact = json.dumps(payload, separators=(",", ":"), ensure_ascii=False)

    print("weapons        : %d (%d playable)" % (len(weapons), payload["stats"]["playable_weapons"]))
    print("archive files  : %d" % len(files))
    print("esl tweak rules: %d" % len(rules))
    print("esl modified   : %d" % len(changes))
    print("pretty bytes   : %d" % os.path.getsize(args.out))
    print("compact bytes  : %d" % len(compact.encode("utf-8")))
    print("written        : %s" % args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
