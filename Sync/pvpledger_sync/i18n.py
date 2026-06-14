"""Localization helpers for the PvPLedger Sync desktop apps."""

from __future__ import annotations

import ctypes
import json
import locale
from pathlib import Path

from .paths import bundle_dir, is_frozen

_BASE_LOCALE = "enUS"
_SUPPORTED_LOCALES = frozenset(
    {
        "enUS",
        "deDE",
        "frFR",
        "esES",
        "esMX",
        "ptBR",
        "ruRU",
        "koKR",
        "zhCN",
        "zhTW",
        "itIT",
    }
)

_WINDOWS_LOCALE_PREFIXES: tuple[tuple[str, str], ...] = (
    ("zh-hans", "zhCN"),
    ("zh-cn", "zhCN"),
    ("zh-sg", "zhCN"),
    ("zh-hant", "zhTW"),
    ("zh-tw", "zhTW"),
    ("zh-hk", "zhTW"),
    ("zh-mo", "zhTW"),
    ("pt-br", "ptBR"),
    ("es-mx", "esMX"),
    ("es-419", "esMX"),
    ("en-", "enUS"),
    ("de-", "deDE"),
    ("fr-", "frFR"),
    ("es-", "esES"),
    ("pt-", "ptBR"),
    ("ru-", "ruRU"),
    ("ko-", "koKR"),
    ("it-", "itIT"),
)

_base_strings: dict[str, str] = {}
_overlay_strings: dict[str, str] = {}
_active_locale = _BASE_LOCALE
_initialized = False


def locales_dir() -> Path:
    """
    Return the directory containing bundled locale JSON files.

    Returns
    -------
    Path
        ``pvpledger_sync/locales`` in dev mode or inside a PyInstaller bundle.
    """

    if is_frozen():
        return bundle_dir() / "pvpledger_sync" / "locales"
    return Path(__file__).resolve().parent / "locales"


def normalize_locale(code: str | None) -> str:
    """
    Normalize one locale identifier to a supported PvPLedger Sync locale code.

    Parameters
    ----------
    code:
        Locale code such as ``en-US``, ``de``, or ``frFR``.

    Returns
    -------
    str
        Supported locale code, defaulting to ``enUS``.
    """

    if not code:
        return _BASE_LOCALE

    normalized = code.strip().replace("-", "").replace("_", "")
    if not normalized:
        return _BASE_LOCALE

    if normalized in _SUPPORTED_LOCALES:
        return normalized

    lowered = code.strip().lower()
    for prefix, mapped in _WINDOWS_LOCALE_PREFIXES:
        if lowered.startswith(prefix):
            return mapped

    language = normalized[:2].lower()
    language_map = {
        "en": "enUS",
        "de": "deDE",
        "fr": "frFR",
        "es": "esES",
        "pt": "ptBR",
        "ru": "ruRU",
        "ko": "koKR",
        "zh": "zhCN",
        "it": "itIT",
    }
    return language_map.get(language, _BASE_LOCALE)


def detect_windows_locale() -> str:
    """
    Detect the active Windows UI language.

    Returns
    -------
    str
        Supported locale code for the current Windows profile.
    """

    try:
        kernel32 = ctypes.windll.kernel32  # type: ignore[attr-defined]
        get_locale_name = kernel32.GetUserDefaultLocaleName
        get_locale_name.argtypes = [ctypes.c_wchar_p, ctypes.c_int]
        get_locale_name.restype = ctypes.c_int
        buffer = ctypes.create_unicode_buffer(86)
        if get_locale_name(buffer, 86):
            return normalize_locale(buffer.value)
    except Exception:
        pass

    try:
        ui_language = locale.getlocale()[0]
        if ui_language:
            return normalize_locale(ui_language)
    except Exception:
        pass

    try:
        default_locale = locale.getdefaultlocale()[0]
        if default_locale:
            return normalize_locale(default_locale)
    except Exception:
        pass

    return _BASE_LOCALE


def _load_locale_file(locale_code: str) -> dict[str, str]:
    """
    Load one locale JSON file when present.

    Parameters
    ----------
    locale_code:
        Locale file stem such as ``deDE``.

    Returns
    -------
    dict[str, str]
        String table from disk, or an empty dict when missing.
    """

    path = locales_dir() / f"{locale_code}.json"
    if not path.exists():
        return {}

    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        return {}

    return {str(key): str(value) for key, value in payload.items()}


def init_i18n(locale_code: str | None = None) -> str:
    """
    Load base and overlay locale tables for the active Windows language.

    Parameters
    ----------
    locale_code:
        Optional locale override for tests or future settings UI.

    Returns
    -------
    str
        Active locale code after initialization.
    """

    global _base_strings, _overlay_strings, _active_locale, _initialized

    _active_locale = normalize_locale(locale_code or detect_windows_locale())
    _base_strings = _load_locale_file(_BASE_LOCALE)
    _overlay_strings = (
        _load_locale_file(_active_locale) if _active_locale != _BASE_LOCALE else {}
    )
    _initialized = True
    return _active_locale


def active_locale() -> str:
    """
    Return the locale loaded by the most recent ``init_i18n`` call.

    Returns
    -------
    str
        Active locale code.
    """

    if not _initialized:
        init_i18n()
    return _active_locale


def t(key: str, *args: object, **kwargs: object) -> str:
    """
    Return one localized string with optional ``str.format`` placeholders.

    Parameters
    ----------
    key:
        Locale lookup key.
    *args:
        Positional format arguments.
    **kwargs:
        Named format arguments.

    Returns
    -------
    str
        Localized string, falling back to English and then the key itself.
    """

    if not _initialized:
        init_i18n()

    template = _overlay_strings.get(key) or _base_strings.get(key) or key
    if not args and not kwargs:
        return template

    try:
        return template.format(*args, **kwargs)
    except (KeyError, ValueError, IndexError):
        return template
