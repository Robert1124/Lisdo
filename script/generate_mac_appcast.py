#!/usr/bin/env python3
"""Generate a single-item Sparkle-compatible macOS appcast."""

from __future__ import annotations

import argparse
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import urlparse


SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
DMG_MIME_TYPE = "application/x-apple-diskimage"


def non_empty(value: str, field_name: str) -> str:
    stripped = value.strip()
    if not stripped:
        raise argparse.ArgumentTypeError(f"{field_name} must not be empty")
    return stripped


def valid_https_url(value: str, field_name: str) -> str:
    stripped = non_empty(value, field_name)
    parsed = urlparse(stripped)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise argparse.ArgumentTypeError(f"{field_name} must be an http(s) URL")
    return stripped


def existing_file(value: str) -> Path:
    path = Path(value)
    if not path.is_file():
        raise argparse.ArgumentTypeError(f"{value} is not a file")
    return path


def read_release_notes(args: argparse.Namespace) -> str | None:
    if args.release_notes is not None:
        return args.release_notes
    if args.release_notes_file is not None:
        return args.release_notes_file.read_text(encoding="utf-8").strip()
    return None


def build_appcast(
    *,
    version: str,
    build: str,
    release_url: str,
    dmg_url: str,
    dmg_path: Path,
    release_notes: str | None,
    ed_signature: str | None,
) -> ET.ElementTree:
    ET.register_namespace("sparkle", SPARKLE_NS)

    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "Lisdo macOS Updates"
    ET.SubElement(channel, "link").text = release_url
    ET.SubElement(channel, "description").text = "Signed Lisdo macOS releases."
    ET.SubElement(channel, "language").text = "en-us"

    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = f"Lisdo {version}"
    ET.SubElement(item, "link").text = release_url
    if release_notes:
        ET.SubElement(item, "description").text = release_notes
    enclosure_attrs = {
        "url": dmg_url,
        f"{{{SPARKLE_NS}}}shortVersionString": version,
        f"{{{SPARKLE_NS}}}version": build,
        "length": str(dmg_path.stat().st_size),
        "type": DMG_MIME_TYPE,
    }
    if ed_signature is not None:
        enclosure_attrs[f"{{{SPARKLE_NS}}}edSignature"] = ed_signature

    ET.SubElement(item, "enclosure", enclosure_attrs)

    ET.indent(rss, space="  ")
    return ET.ElementTree(rss)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate a deterministic single-item RSS appcast for Lisdo macOS releases."
    )
    parser.add_argument("--version", required=True, type=lambda value: non_empty(value, "version"))
    parser.add_argument("--build", required=True, type=lambda value: non_empty(value, "build"))
    parser.add_argument(
        "--release-url",
        required=True,
        type=lambda value: valid_https_url(value, "release URL"),
    )
    parser.add_argument("--dmg-url", required=True, type=lambda value: valid_https_url(value, "DMG URL"))
    parser.add_argument("--dmg-path", required=True, type=existing_file)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument(
        "--ed-signature",
        type=lambda value: non_empty(value, "edSignature"),
        help="Optional Sparkle EdDSA signature to add to the enclosure as sparkle:edSignature.",
    )

    notes = parser.add_mutually_exclusive_group()
    notes.add_argument("--release-notes", help="Optional release notes text for the appcast item.")
    notes.add_argument(
        "--release-notes-file",
        type=existing_file,
        help="Optional UTF-8 release notes file for the appcast item.",
    )

    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    release_notes = read_release_notes(args)
    appcast = build_appcast(
        version=args.version,
        build=args.build,
        release_url=args.release_url,
        dmg_url=args.dmg_url,
        dmg_path=args.dmg_path,
        release_notes=release_notes,
        ed_signature=args.ed_signature,
    )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    xml = ET.tostring(appcast.getroot(), encoding="utf-8", xml_declaration=True)
    args.output.write_bytes(xml + b"\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
