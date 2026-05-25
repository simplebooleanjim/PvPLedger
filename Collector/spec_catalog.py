"""Class and spec slug mappings for Battle.net Blitz leaderboards."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class BlitzSpecDefinition:
    """Maps one Battle.net Blitz bracket slug to addon aggregate keys."""

    api_slug: str
    class_token: str
    spec_token: str

    @property
    def spec_key(self) -> str:
        """Return the CLASS_SPEC aggregate key used by the addon."""

        return f"{self.class_token}_{self.spec_token}"


# Midnight Blitz specs. Order longest class slug first when matching.
BLITZ_SPECS: tuple[BlitzSpecDefinition, ...] = (
    BlitzSpecDefinition("blitz-deathknight-blood", "DEATHKNIGHT", "BLOOD"),
    BlitzSpecDefinition("blitz-deathknight-frost", "DEATHKNIGHT", "FROST"),
    BlitzSpecDefinition("blitz-deathknight-unholy", "DEATHKNIGHT", "UNHOLY"),
    BlitzSpecDefinition("blitz-demonhunter-devourer", "DEMONHUNTER", "DEVOURER"),
    BlitzSpecDefinition("blitz-demonhunter-havoc", "DEMONHUNTER", "HAVOC"),
    BlitzSpecDefinition("blitz-demonhunter-vengeance", "DEMONHUNTER", "VENGEANCE"),
    BlitzSpecDefinition("blitz-druid-balance", "DRUID", "BALANCE"),
    BlitzSpecDefinition("blitz-druid-feral", "DRUID", "FERAL"),
    BlitzSpecDefinition("blitz-druid-guardian", "DRUID", "GUARDIAN"),
    BlitzSpecDefinition("blitz-druid-restoration", "DRUID", "RESTORATION"),
    BlitzSpecDefinition("blitz-evoker-augmentation", "EVOKER", "AUGMENTATION"),
    BlitzSpecDefinition("blitz-evoker-devastation", "EVOKER", "DEVASTATION"),
    BlitzSpecDefinition("blitz-evoker-preservation", "EVOKER", "PRESERVATION"),
    BlitzSpecDefinition("blitz-hunter-beastmastery", "HUNTER", "BEASTMASTERY"),
    BlitzSpecDefinition("blitz-hunter-marksmanship", "HUNTER", "MARKSMANSHIP"),
    BlitzSpecDefinition("blitz-hunter-survival", "HUNTER", "SURVIVAL"),
    BlitzSpecDefinition("blitz-mage-arcane", "MAGE", "ARCANE"),
    BlitzSpecDefinition("blitz-mage-fire", "MAGE", "FIRE"),
    BlitzSpecDefinition("blitz-mage-frost", "MAGE", "FROST"),
    BlitzSpecDefinition("blitz-monk-brewmaster", "MONK", "BREWMASTER"),
    BlitzSpecDefinition("blitz-monk-mistweaver", "MONK", "MISTWEAVER"),
    BlitzSpecDefinition("blitz-monk-windwalker", "MONK", "WINDWALKER"),
    BlitzSpecDefinition("blitz-paladin-holy", "PALADIN", "HOLY"),
    BlitzSpecDefinition("blitz-paladin-protection", "PALADIN", "PROTECTION"),
    BlitzSpecDefinition("blitz-paladin-retribution", "PALADIN", "RETRIBUTION"),
    BlitzSpecDefinition("blitz-priest-discipline", "PRIEST", "DISCIPLINE"),
    BlitzSpecDefinition("blitz-priest-holy", "PRIEST", "HOLY"),
    BlitzSpecDefinition("blitz-priest-shadow", "PRIEST", "SHADOW"),
    BlitzSpecDefinition("blitz-rogue-assassination", "ROGUE", "ASSASSINATION"),
    BlitzSpecDefinition("blitz-rogue-outlaw", "ROGUE", "OUTLAW"),
    BlitzSpecDefinition("blitz-rogue-subtlety", "ROGUE", "SUBTLETY"),
    BlitzSpecDefinition("blitz-shaman-elemental", "SHAMAN", "ELEMENTAL"),
    BlitzSpecDefinition("blitz-shaman-enhancement", "SHAMAN", "ENHANCEMENT"),
    BlitzSpecDefinition("blitz-shaman-restoration", "SHAMAN", "RESTORATION"),
    BlitzSpecDefinition("blitz-warlock-affliction", "WARLOCK", "AFFLICTION"),
    BlitzSpecDefinition("blitz-warlock-demonology", "WARLOCK", "DEMONOLOGY"),
    BlitzSpecDefinition("blitz-warlock-destruction", "WARLOCK", "DESTRUCTION"),
    BlitzSpecDefinition("blitz-warrior-arms", "WARRIOR", "ARMS"),
    BlitzSpecDefinition("blitz-warrior-fury", "WARRIOR", "FURY"),
    BlitzSpecDefinition("blitz-warrior-protection", "WARRIOR", "PROTECTION"),
)

BLITZ_SPEC_BY_SLUG = {spec.api_slug: spec for spec in BLITZ_SPECS}


def resolve_blitz_spec(api_slug: str) -> BlitzSpecDefinition | None:
    """Resolve a Battle.net bracket slug to a known Blitz spec definition."""

    return BLITZ_SPEC_BY_SLUG.get(api_slug)
