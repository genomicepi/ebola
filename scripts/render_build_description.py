#!/usr/bin/env python3

import argparse
import csv
from pathlib import Path


def has_value(value):
    return value is not None and value.strip() not in {"", "missing", "nan", "NaN"}


def pluralize(count, singular, plural=None):
    if count == 1:
        return singular
    return plural or f"{singular}s"


def main():
    parser = argparse.ArgumentParser(
        description="Render a build description from a Markdown template and final build metadata."
    )
    parser.add_argument("--metadata", required=True, help="Final post-QC metadata TSV.")
    parser.add_argument("--template", required=True, help="Markdown template with count placeholders.")
    parser.add_argument("--output", required=True, help="Rendered Markdown description.")
    args = parser.parse_args()

    metadata_path = Path(args.metadata)
    template_path = Path(args.template)
    output_path = Path(args.output)

    with metadata_path.open(newline="") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))

    total_count = len(rows)
    insdc_count = sum(1 for row in rows if has_value(row.get("INSDC_accession")))
    direct_pathoplexus_count = total_count - insdc_count

    template = template_path.read_text()
    rendered = template.format(
        total_sequences=total_count,
        total_sequence_word=pluralize(total_count, "record"),
        direct_pathoplexus_sequences=direct_pathoplexus_count,
        direct_pathoplexus_sequence_word=pluralize(direct_pathoplexus_count, "sequence"),
        insdc_sequences=insdc_count,
        insdc_sequence_word=pluralize(insdc_count, "sequence"),
    )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(rendered)


if __name__ == "__main__":
    main()
