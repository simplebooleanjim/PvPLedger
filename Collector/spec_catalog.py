"""Class and spec slug mappings for Battle.net PvP leaderboards."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class BracketSpecDefinition:
    """Maps one Battle.net bracket slug to addon aggregate keys."""

    api_slug: str
    class_token: str
    spec_token: str

    @property
    def spec_key(self) -> str:
        """Return the CLASS_SPEC aggregate key used by the addon."""

        return f"{self.class_token}_{self.spec_token}"


# Shared class/spec pairs used by both Blitz and Solo Shuffle ladders.
_BASE_SPEC_ROWS: tuple[tuple[str, str, str, str], ...] = (
    ("deathknight", "blood", "DEATHKNIGHT", "BLOOD"),
    ("deathknight", "frost", "DEATHKNIGHT", "FROST"),
    ("deathknight", "unholy", "DEATHKNIGHT", "UNHOLY"),
    ("demonhunter", "devourer", "DEMONHUNTER", "DEVOURER"),
    ("demonhunter", "havoc", "DEMONHUNTER", "HAVOC"),
    ("demonhunter", "vengeance", "DEMONHUNTER", "VENGEANCE"),
    ("druid", "balance", "DRUID", "BALANCE"),
    ("druid", "feral", "DRUID", "FERAL"),
    ("druid", "guardian", "DRUID", "GUARDIAN"),
    ("druid", "restoration", "DRUID", "RESTORATION"),
    ("evoker", "augmentation", "EVOKER", "AUGMENTATION"),
    ("evoker", "devastation", "EVOKER", "DEVASTATION"),
    ("evoker", "preservation", "EVOKER", "PRESERVATION"),
    ("hunter", "beastmastery", "HUNTER", "BEASTMASTERY"),
    ("hunter", "marksmanship", "HUNTER", "MARKSMANSHIP"),
    ("hunter", "survival", "HUNTER", "SURVIVAL"),
    ("mage", "arcane", "MAGE", "ARCANE"),
    ("mage", "fire", "MAGE", "FIRE"),
    ("mage", "frost", "MAGE", "FROST"),
    ("monk", "brewmaster", "MONK", "BREWMASTER"),
    ("monk", "mistweaver", "MONK", "MISTWEAVER"),
    ("monk", "windwalker", "MONK", "WINDWALKER"),
    ("paladin", "holy", "PALADIN", "HOLY"),
    ("paladin", "protection", "PALADIN", "PROTECTION"),
    ("paladin", "retribution", "PALADIN", "RETRIBUTION"),
    ("priest", "discipline", "PRIEST", "DISCIPLINE"),
    ("priest", "holy", "PRIEST", "HOLY"),
    ("priest", "shadow", "PRIEST", "SHADOW"),
    ("rogue", "assassination", "ROGUE", "ASSASSINATION"),
    ("rogue", "outlaw", "ROGUE", "OUTLAW"),
    ("rogue", "subtlety", "ROGUE", "SUBTLETY"),
    ("shaman", "elemental", "SHAMAN", "ELEMENTAL"),
    ("shaman", "enhancement", "SHAMAN", "ENHANCEMENT"),
    ("shaman", "restoration", "SHAMAN", "RESTORATION"),
    ("warlock", "affliction", "WARLOCK", "AFFLICTION"),
    ("warlock", "demonology", "WARLOCK", "DEMONOLOGY"),
    ("warlock", "destruction", "WARLOCK", "DESTRUCTION"),
    ("warrior", "arms", "WARRIOR", "ARMS"),
    ("warrior", "fury", "WARRIOR", "FURY"),
    ("warrior", "protection", "WARRIOR", "PROTECTION"),
)

SUPPORTED_BRACKETS: tuple[str, ...] = ("blitz", "shuffle", "rbg", "arena2v2", "arena3v3")
PER_SPEC_BRACKETS: tuple[str, ...] = ("blitz", "shuffle")
SINGLE_LADDER_BRACKETS: tuple[str, ...] = ("rbg", "arena2v2", "arena3v3")
SERAMATE_ENRICHED_BRACKETS: tuple[str, ...] = ("rbg", "arena2v2", "arena3v3")
SINGLE_LADDER_API_SLUGS: dict[str, str] = {
    "rbg": "rbg",
    "arena2v2": "2v2",
    "arena3v3": "3v3",
}
SERAMATE_LADDER_SLUGS: dict[str, str] = {
    "rbg": "rbg",
    "arena2v2": "2v2",
    "arena3v3": "3v3",
}
RBG_API_SLUG = SINGLE_LADDER_API_SLUGS["rbg"]


def build_bracket_catalog(prefix: str) -> tuple[BracketSpecDefinition, ...]:
    """Build spec definitions for one Battle.net bracket prefix."""

    return tuple(
        BracketSpecDefinition(
            api_slug=f"{prefix}-{class_slug}-{spec_slug}",
            class_token=class_token,
            spec_token=spec_token,
        )
        for class_slug, spec_slug, class_token, spec_token in _BASE_SPEC_ROWS
    )


BRACKET_CATALOGS: dict[str, tuple[BracketSpecDefinition, ...]] = {
    bracket: build_bracket_catalog(bracket) for bracket in PER_SPEC_BRACKETS
}

BRACKET_SPEC_BY_SLUG: dict[str, dict[str, BracketSpecDefinition]] = {
    bracket: {spec.api_slug: spec for spec in specs}
    for bracket, specs in BRACKET_CATALOGS.items()
}

# Backward-compatible aliases used by earlier collector code.
BLITZ_SPECS = BRACKET_CATALOGS["blitz"]
BLITZ_SPEC_BY_SLUG = BRACKET_SPEC_BY_SLUG["blitz"]
BlitzSpecDefinition = BracketSpecDefinition


def get_bracket_specs(bracket: str) -> tuple[BracketSpecDefinition, ...]:
    """Return the spec catalog for one per-spec bracket."""

    specs = BRACKET_CATALOGS.get(bracket.lower())
    if specs is None:
        raise KeyError(f"Bracket {bracket} does not use a per-spec catalog.")
    return specs


def is_single_ladder_bracket(bracket: str) -> bool:
    """Return True when a bracket uses one combined Battle.net leaderboard slug."""

    return bracket.lower() in SINGLE_LADDER_BRACKETS


def get_single_ladder_api_slug(bracket: str) -> str:
    """Return the Battle.net leaderboard slug for one combined-ladder bracket."""

    api_slug = SINGLE_LADDER_API_SLUGS.get(bracket.lower())
    if api_slug is None:
        raise KeyError(f"Bracket {bracket} does not use a single-ladder API slug.")
    return api_slug


def supports_seramate_enrichment(bracket: str) -> bool:
    """Return True when a bracket can be enriched with Seramate class/spec data."""

    return bracket.lower() in SERAMATE_ENRICHED_BRACKETS


def get_seramate_ladder_slug(bracket: str) -> str:
    """Return the Seramate ladder slug for one combined-ladder bracket."""

    api_slug = SERAMATE_LADDER_SLUGS.get(bracket.lower())
    if api_slug is None:
        raise KeyError(f"Bracket {bracket} does not support Seramate enrichment.")
    return api_slug


def resolve_bracket_spec(bracket: str, api_slug: str) -> BracketSpecDefinition | None:
    """Resolve a Battle.net bracket slug to a known spec definition."""

    return BRACKET_SPEC_BY_SLUG.get(bracket.lower(), {}).get(api_slug)


def resolve_blitz_spec(api_slug: str) -> BracketSpecDefinition | None:
    """Resolve a Battle.net Blitz bracket slug to a known spec definition."""

    return resolve_bracket_spec("blitz", api_slug)
