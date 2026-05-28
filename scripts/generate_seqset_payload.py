#!/usr/bin/env python3

import argparse
import csv
import json
import re
from pathlib import Path


def normalize_accession(value):
    match = re.match(r"^(PP_[A-Z0-9]+)(?:\.\d+)?$", value.strip(), re.IGNORECASE)
    return match.group(1).upper() if match else None


def main():
    parser = argparse.ArgumentParser(
        description="Generate a Pathoplexus SeqSet update payload from tree metadata."
    )
    parser.add_argument("--metadata", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--seqset-id", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--description", required=True)
    parser.add_argument("--focal-outbreak", required=True)
    args = parser.parse_args()

    focal = set()
    background = set()

    with open(args.metadata, newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        for row in reader:
            accession = normalize_accession(row["PPX_accession"])
            if not accession:
                continue

            if row.get("outbreak") == args.focal_outbreak:
                focal.add(accession)
            else:
                background.add(accession)

    records = [
        {"accession": accession, "type": "Loculus", "isFocal": True}
        for accession in sorted(focal)
    ]
    records.extend(
        {"accession": accession, "type": "Loculus", "isFocal": False}
        for accession in sorted(background - focal)
    )

    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(
            {
                "seqSetId": args.seqset_id,
                "name": args.name,
                "description": args.description,
                "records": records,
            },
            indent=2,
        )
        + "\n"
    )

    print(
        f"Wrote {len(records)} SeqSet records "
        f"({len(focal)} focal, {len(records) - len(focal)} background) to {output}"
    )


if __name__ == "__main__":
    main()
