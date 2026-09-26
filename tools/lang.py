#!/usr/bin/env python3
"""Generates shaders/lang/en_US.lang and shaders/lang/de_DE.lang"""
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "shaders", "lang")

# key: (english name, english comment, german name, german comment)
OPTIONS = {
    "SHADOWS": ("Shadows", "Real time sun and moon shadows.", "Schatten", "Echtzeit-Schatten von Sonne und Mond."),
    "COLORED_SHADOWS": ("Colored Shadows", "Stained glass tints light, water casts caustics.", "Farbige Schatten", "Buntglas färbt das Licht, Wasser wirft Kaustiken."),
    "shadowMapResolution": ("Shadow Resolution", "Sharper shadows cost GPU memory and time.", "Schattenauflösung", "Schärfere Schatten kosten GPU-Leistung."),
    "shadowDistance": ("Shadow Distance", "Lower values render fewer chunks in the shadow pass (saves CPU).", "Schattendistanz", "Niedrigere Werte rendern weniger Chunks im Schattenpass (spart CPU)."),
    "shadowDistanceRenderMul": ("Shadow Render Limit", "Limit shadow chunk rendering to the shadow distance (saves CPU).", "Schatten-Renderlimit", "Begrenzt Schatten-Chunks auf die Schattendistanz (spart CPU)."),
    "SHADOW_FILTER": ("Shadow Filter", "Softness quality of shadow edges.", "Schattenfilter", "Qualität der weichen Schattenkanten."),
    "SHADOW_SOFTNESS": ("Shadow Softness", "Size of the shadow penumbra.", "Schattenweichheit", "Größe des Halbschattens."),
    "ENTITY_SHADOWS": ("Entity Shadows", "Mobs, players and block entities cast shadows. Costs CPU.", "Entity-Schatten", "Mobs, Spieler und Block-Entities werfen Schatten. Kostet CPU."),
    "sunPathRotation": ("Sun Angle", "Tilt of the sun path.", "Sonnenwinkel", "Neigung der Sonnenbahn."),
    "SUN_INTENSITY": ("Sunlight", "Strength of direct sun/moon light.", "Sonnenlicht", "Stärke des direkten Sonnen-/Mondlichts."),
    "AMBIENT_INTENSITY": ("Sky Light", "Strength of ambient sky light.", "Himmelslicht", "Stärke des indirekten Himmelslichts."),
    "BLOCKLIGHT_INTENSITY": ("Block Light", "Brightness of torches, lamps, lava...", "Blocklicht", "Helligkeit von Fackeln, Lampen, Lava..."),
    "BLOCKLIGHT_TEMP": ("Block Light Color", "Color temperature of block light.", "Blocklicht-Farbe", "Farbtemperatur des Blocklichts."),
    "NIGHT_BRIGHTNESS": ("Night Brightness", "", "Nachthelligkeit", ""),
    "MIN_LIGHT": ("Cave Brightness", "Minimum light in completely dark places.", "Höhlenhelligkeit", "Mindestlicht an komplett dunklen Orten."),
    "SSAO": ("Ambient Occlusion (SSAO)", "Soft contact shadows in corners.", "Umgebungsverdeckung (SSAO)", "Weiche Kontaktschatten in Ecken."),
    "SSAO_STRENGTH": ("SSAO Strength", "", "SSAO-Stärke", ""),
    "VANILLA_AO": ("Vanilla AO", "Strength of Minecraft's own smooth lighting AO.", "Vanilla-AO", "Stärke von Minecrafts eigener AO."),
    "HANDHELD_LIGHT": ("Handheld Light", "Light sources in your hand light up the world.", "Handlicht", "Lichtquellen in der Hand beleuchten die Welt."),
    "SUBSURFACE_SCATTERING": ("Subsurface Scattering", "Light shines through leaves and plants.", "Subsurface Scattering", "Licht scheint durch Blätter und Pflanzen."),
    "CLOUD_SHADOWS": ("Cloud Shadows", "", "Wolkenschatten", ""),
    "SPECULAR_HIGHLIGHTS": ("Specular Highlights", "Sun reflections on smooth surfaces.", "Glanzlichter", "Sonnenreflexe auf glatten Oberflächen."),
    "PBR_MODE": ("PBR Mode", "Integrated: materials detected by the shader. labPBR: use resource pack normal/specular maps.", "PBR-Modus", "Integriert: Materialien erkennt der Shader. labPBR: Normal-/Specular-Maps des Resourcepacks."),
    "EMISSIVE_ORES": ("Glowing Ores", "", "Leuchtende Erze", ""),
    "EMISSION_STRENGTH": ("Emission Strength", "Glow of light emitting blocks.", "Leuchtstärke", "Leuchten von lichtgebenden Blöcken."),
    "RAIN_PUDDLES": ("Rain Puddles", "Wet surfaces and reflective puddles when it rains.", "Regenpfützen", "Nasse Oberflächen und spiegelnde Pfützen bei Regen."),
    "PUDDLE_AMOUNT": ("Puddle Amount", "", "Pfützenmenge", ""),
    "GENERATED_NORMALS": ("Generated Normals", "Fake surface bumps from textures.", "Generierte Normalen", "Simulierte Oberflächenstruktur aus Texturen."),
    "NORMAL_STRENGTH": ("Normal Strength", "", "Normalen-Stärke", ""),
    "WATER_STYLE": ("Water Style", "", "Wasserstil", ""),
    "WATER_WAVES": ("Water Waves", "", "Wasserwellen", ""),
    "WAVE_HEIGHT": ("Wave Height", "", "Wellenhöhe", ""),
    "WAVE_SPEED": ("Wave Speed", "", "Wellengeschwindigkeit", ""),
    "WATER_REFRACTION": ("Refraction", "Distorted view through water.", "Lichtbrechung", "Verzerrte Sicht durch Wasser."),
    "REFRACTION_STRENGTH": ("Refraction Strength", "", "Brechungsstärke", ""),
    "WATER_FOG_DENSITY": ("Water Fog", "How murky water is.", "Wassertrübung", "Wie trüb das Wasser ist."),
    "WATER_CAUSTICS": ("Caustics", "Moving light patterns under water.", "Kaustiken", "Bewegte Lichtmuster unter Wasser."),
    "REFLECTIONS": ("Reflections", "Screen space reflections.", "Reflexionen", "Screen-Space-Reflexionen."),
    "SSR_QUALITY": ("Reflection Quality", "", "Reflexionsqualität", ""),
    "VOLUMETRIC_CLOUDS": ("Volumetric Clouds", "", "Volumetrische Wolken", ""),
    "CLOUD_QUALITY": ("Cloud Quality", "", "Wolkenqualität", ""),
    "CLOUD_HEIGHT": ("Cloud Height", "", "Wolkenhöhe", ""),
    "CLOUD_THICKNESS": ("Cloud Thickness", "", "Wolkendicke", ""),
    "CLOUD_COVERAGE": ("Cloud Amount", "", "Wolkenmenge", ""),
    "CLOUD_SPEED": ("Cloud Speed", "", "Wolkengeschwindigkeit", ""),
    "STARS": ("Stars", "", "Sterne", ""),
    "STAR_AMOUNT": ("Star Amount", "", "Sternenmenge", ""),
    "AURORA": ("Aurora Borealis", "Northern lights at night.", "Polarlichter", "Nordlichter bei Nacht."),
    "RAINBOWS": ("Rainbows", "Appear after rain.", "Regenbögen", "Erscheinen nach Regen."),
    "SUN_SIZE": ("Sun Size", "", "Sonnengröße", ""),
    "MOON_SIZE": ("Moon Size", "", "Mondgröße", ""),
    "VOLUMETRIC_LIGHT": ("Volumetric Light", "God rays through the air and water.", "Volumetrisches Licht", "Lichtstrahlen durch Luft und Wasser."),
    "VL_QUALITY": ("Volumetric Light Quality", "", "Qualität vol. Licht", ""),
    "VL_STRENGTH": ("Volumetric Light Strength", "", "Stärke vol. Licht", ""),
    "FOG_DENSITY": ("Fog Density", "", "Nebeldichte", ""),
    "MORNING_FOG": ("Morning Fog", "", "Morgennebel", ""),
    "BORDER_FOG": ("Border Fog", "Hides the edge of the render distance.", "Randnebel", "Versteckt den Rand der Sichtweite."),
    "NETHER_FOG": ("Nether Fog", "", "Nether-Nebel", ""),
    "END_FOG": ("End Fog", "", "End-Nebel", ""),
    "WAVING_PLANTS": ("Waving Plants", "", "Wehende Pflanzen", ""),
    "WAVING_LEAVES": ("Waving Leaves", "", "Wehende Blätter", ""),
    "WAVING_STRENGTH": ("Wind Strength", "", "Windstärke", ""),
    "WAVING_SPEED": ("Wind Speed", "", "Windgeschwindigkeit", ""),
    "TAA": ("Temporal Anti-Aliasing", "Smooth edges and stable image.", "Temporales Anti-Aliasing", "Glatte Kanten und ruhiges Bild."),
    "SHARPENING": ("Sharpening", "", "Schärfen", ""),
    "BLOOM": ("Bloom", "", "Bloom", ""),
    "BLOOM_STRENGTH": ("Bloom Strength", "", "Bloom-Stärke", ""),
    "AUTO_EXPOSURE": ("Auto Exposure", "Eye adaptation between bright and dark places.", "Auto-Belichtung", "Augenanpassung zwischen hellen und dunklen Orten."),
    "EXPOSURE": ("Exposure", "", "Belichtung", ""),
    "TONEMAP": ("Tonemapper", "", "Tonemapper", ""),
    "SATURATION": ("Saturation", "", "Sättigung", ""),
    "VIBRANCE": ("Vibrance", "", "Lebendigkeit", ""),
    "CONTRAST": ("Contrast", "", "Kontrast", ""),
    "VIGNETTE": ("Vignette", "", "Vignette", ""),
    "DEPTH_OF_FIELD": ("Depth of Field", "Blurs things out of focus.", "Tiefenunschärfe", "Macht unscharf, was nicht im Fokus ist."),
    "DOF_STRENGTH": ("DoF Strength", "", "DoF-Stärke", ""),
    "MOTION_BLUR": ("Motion Blur", "", "Bewegungsunschärfe", ""),
    "MOTION_BLUR_STRENGTH": ("Motion Blur Strength", "", "Stärke Bewegungsunschärfe", ""),
    "UNDERWATER_DISTORTION": ("Underwater Distortion", "", "Unterwasser-Verzerrung", ""),
}

SCREENS = {
    "SHADOWS_SCREEN": ("Shadows", "Schatten"),
    "LIGHTING_SCREEN": ("Lighting", "Beleuchtung"),
    "MATERIALS_SCREEN": ("Materials", "Materialien"),
    "WATER_SCREEN": ("Water & Reflections", "Wasser & Reflexionen"),
    "SKY_SCREEN": ("Sky & Clouds", "Himmel & Wolken"),
    "ATMOSPHERE_SCREEN": ("Atmosphere", "Atmosphäre"),
    "POST_SCREEN": ("Camera & Post", "Kamera & Nachbearbeitung"),
}

PROFILES = {
    "POTATO": ("Potato", "Kartoffel"), "LOW": ("Low", "Niedrig"), "MEDIUM": ("Medium", "Mittel"),
    "HIGH": ("High", "Hoch"), "ULTRA": ("Ultra", "Ultra"),
}

VALUES = {
    "SHADOW_FILTER": {0: ("Hard", "Hart"), 1: ("Soft", "Weich"), 2: ("Smooth", "Sanft"), 3: ("Ultra", "Ultra")},
    "BLOCKLIGHT_TEMP": {0: ("Neutral", "Neutral"), 1: ("Warm", "Warm"), 2: ("Very Warm", "Sehr warm")},
    "PBR_MODE": {0: ("Integrated", "Integriert"), 1: ("labPBR", "labPBR")},
    "WATER_STYLE": {0: ("Clear", "Klar"), 1: ("Tinted Texture", "Getönte Textur"), 2: ("Vanilla Texture", "Vanilla-Textur")},
    "REFLECTIONS": {0: ("Sky Only", "Nur Himmel"), 1: ("Water", "Wasser"), 2: ("All Surfaces", "Alle Oberflächen")},
    "SSR_QUALITY": {0: ("Low", "Niedrig"), 1: ("Medium", "Mittel"), 2: ("High", "Hoch")},
    "CLOUD_QUALITY": {0: ("Low", "Niedrig"), 1: ("Medium", "Mittel"), 2: ("High", "Hoch")},
    "VL_QUALITY": {0: ("Low", "Niedrig"), 1: ("Medium", "Mittel"), 2: ("High", "Hoch")},
    "AURORA": {0: ("Off", "Aus"), 1: ("Snowy Biomes", "Schneebiome"), 2: ("Always", "Immer")},
    "TONEMAP": {0: ("ACES", "ACES"), 1: ("Lottes", "Lottes"), 2: ("Reinhard-Jodie", "Reinhard-Jodie")},
    "shadowDistanceRenderMul": {-1.0: ("Unlimited", "Unbegrenzt"), 1.0: ("Shadow Distance", "Schattendistanz")},
}


def fmt_value(v):
    return str(v)


def write(lang_idx, fname, header):
    lines = [header, ""]
    for k, (en, enc, de, dec) in OPTIONS.items():
        name, comment = (en, enc) if lang_idx == 0 else (de, dec)
        lines.append(f"option.{k}={name}")
        if comment:
            lines.append(f"option.{k}.comment={comment}")
    lines.append("")
    for k, names in SCREENS.items():
        lines.append(f"screen.{k}={names[lang_idx]}")
    lines.append("")
    for k, names in PROFILES.items():
        lines.append(f"profile.{k}={names[lang_idx]}")
    lines.append("")
    for k, vals in VALUES.items():
        for v, names in vals.items():
            lines.append(f"value.{k}.{fmt_value(v)}={names[lang_idx]}")
    os.makedirs(ROOT, exist_ok=True)
    with open(os.path.join(ROOT, fname), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")


if __name__ == "__main__":
    write(0, "en_US.lang", "# Yukitus Shader - English")
    write(1, "de_DE.lang", "# Yukitus Shader - Deutsch")
    print("lang files written")
