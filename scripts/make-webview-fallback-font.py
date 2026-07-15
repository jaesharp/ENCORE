#!/usr/bin/env python3

"""Create and verify the prefix-local Arial fallback used by Chromium."""

from hashlib import sha256
from pathlib import Path
import sys

from fontTools.ttLib import TTFont, TTLibError


TARGET_NAMES = {
    1: "Arial",
    2: "Regular",
    4: "Arial",
    6: "ArialMT",
    16: "Arial",
    17: "Regular",
    21: "Arial",
    22: "Regular",
}
LICENSE_NAME_IDS = (0, 13, 14)


def family_names(font: TTFont) -> set[str]:
    names: set[str] = set()
    for record in font["name"].names:
        if record.nameID not in (1, 16):
            continue
        try:
            names.add(record.toUnicode())
        except UnicodeDecodeError:
            continue
    return names


def name_values(font: TTFont, name_id: int) -> set[str]:
    values: set[str] = set()
    for record in font["name"].names:
        if record.nameID != name_id:
            continue
        try:
            values.add(record.toUnicode())
        except UnicodeDecodeError:
            continue
    return values


def license_records(font: TTFont) -> set[tuple[int, int, int, int, str]]:
    records: set[tuple[int, int, int, int, str]] = set()
    for record in font["name"].names:
        if record.nameID not in LICENSE_NAME_IDS:
            continue
        try:
            value = record.toUnicode()
        except UnicodeDecodeError:
            continue
        records.add(
            (
                record.nameID,
                record.platformID,
                record.platEncID,
                record.langID,
                value,
            )
        )
    return records


def generated_names(source: Path) -> dict[int, str]:
    source_hash = sha256(source.read_bytes()).hexdigest()
    names = dict(TARGET_NAMES)
    names[3] = f"ENCORE Arial Regular; source-sha256={source_hash}; generator=1"
    names[10] = (
        "ENCORE Chromium fallback generated from Liberation Sans; "
        f"source SHA-256 {source_hash}; generator format 1"
    )
    return names


def load_font(path: Path) -> TTFont:
    return TTFont(path, lazy=False, recalcTimestamp=False)


def verify_source(font: TTFont, source: Path) -> None:
    if "Liberation Sans" not in family_names(font):
        raise ValueError(f"expected Liberation Sans source, got {source}")
    for name_id in LICENSE_NAME_IDS:
        if not name_values(font, name_id):
            raise ValueError(
                f"Liberation Sans source is missing required name ID {name_id}"
            )


def generate(source: Path, destination: Path) -> None:
    font = load_font(source)
    try:
        verify_source(font, source)

        # Chromium's Windows fallback path needs a real Arial family. Wine's
        # replacement aliases are not visible to that path, so create a local
        # face while retaining Liberation Sans' original license records.
        name_table = font["name"]
        for name_id, value in generated_names(source).items():
            name_table.removeNames(nameID=name_id)
            name_table.setName(value, name_id, 3, 1, 0x409)
            name_table.setName(value, name_id, 1, 0, 0)

        if "DSIG" in font:
            del font["DSIG"]
        font.recalcTimestamp = False
        font.save(destination, reorderTables=False)
    finally:
        font.close()


def verify_generated(source: Path, generated: Path) -> None:
    source_font = load_font(source)
    generated_font = load_font(generated)
    try:
        verify_source(source_font, source)
        expected_names = generated_names(source)
        for name_id, expected in expected_names.items():
            actual = name_values(generated_font, name_id)
            if actual != {expected}:
                raise ValueError(
                    f"unexpected name ID {name_id}: {sorted(actual)!r}"
                )
        if "DSIG" in generated_font:
            raise ValueError("generated font still contains a DSIG table")
        if license_records(generated_font) != license_records(source_font):
            raise ValueError("generated font did not preserve license metadata")
    finally:
        generated_font.close()
        source_font.close()


def has_family(path: Path, expected: str) -> None:
    font = load_font(path)
    try:
        if expected not in family_names(font):
            raise ValueError(f"{path} does not contain family {expected!r}")
    finally:
        font.close()


def main() -> int:
    try:
        if len(sys.argv) == 3 and sys.argv[1] not in ("--verify", "--has-family"):
            generate(Path(sys.argv[1]), Path(sys.argv[2]))
            return 0
        if len(sys.argv) == 4 and sys.argv[1] == "--verify":
            verify_generated(Path(sys.argv[2]), Path(sys.argv[3]))
            return 0
        if len(sys.argv) == 4 and sys.argv[1] == "--has-family":
            has_family(Path(sys.argv[2]), sys.argv[3])
            return 0
    except (KeyError, OSError, TTLibError, UnicodeError, ValueError) as error:
        print(f"ENCORE: {error}", file=sys.stderr)
        return 1

    print(
        f"usage: {sys.argv[0]} SOURCE DESTINATION\n"
        f"       {sys.argv[0]} --verify SOURCE GENERATED\n"
        f"       {sys.argv[0]} --has-family FONT FAMILY",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
