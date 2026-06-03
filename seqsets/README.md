# Pathoplexus SeqSet payloads

This folder stores generated payloads used to update Pathoplexus SeqSets for the
Ebola workflows in this repository.

## Current payload

`ebola_bdbv_seqset_update.json` updates Pathoplexus SeqSet `PP_SS_2047`:

- Name: `Bundibugyo ebolavirus 2026 outbreak build`
- Focal records: Bundibugyo ebolavirus records annotated as `Bdbv-2026`
- Background records: historical Bundibugyo ebolavirus records included in the
  same build

The payload is generated from the curated BDBV phylogenetic workflow metadata,
not edited by hand. Each record contains:

- `accession`: unversioned Pathoplexus accession, such as `PP_006XCJJ`
- `type`: `Loculus`
- `isFocal`: `true` for focal outbreak records, `false` for background records

## How the payload is generated

The BDBV workflow declares the SeqSet in
`phylogenetic/species-workflows/bdbv.snakefile`:

```py
config['seqset'] = {
    "id": "PP_SS_2047",
    "name": "Bundibugyo ebolavirus 2026 outbreak build",
    "description": "...",
    "focal_outbreak": "Bdbv-2026",
}
```

When the BDBV workflow runs, `phylogenetic/species-workflows/generic.snakefile`
calls `scripts/generate_seqset_payload.py`. That script reads
`results/bdbv/metadata.tsv`, normalizes `PPX_accession` values by removing
version suffixes, and marks records as focal when their `outbreak` field equals
`Bdbv-2026`.

## Regenerating the payload

First update the curated BDBV ingest outputs from Pathoplexus:

```bash
cd ingest
snakemake --cores 4 -pf results/bdbv/{sequences.fasta,metadata.tsv}
```

Then run the BDBV phylogenetic workflow, which includes the SeqSet payload in
its final targets:

```bash
cd ../phylogenetic
snakemake --snakefile species-workflows/bdbv.snakefile --cores 4 -pf
```

The generated payload will be written to:

```text
seqsets/ebola_bdbv_seqset_update.json
```

## Updating Pathoplexus

After reviewing the generated payload, update the Pathoplexus SeqSet from the
repository root:

```bash
node scripts/update_pathoplexus_seqset.mjs
```

The update script expects Pathoplexus credentials in the environment or in a
local `.env` file:

```bash
PATHOPLEXUS_USERNAME=...
PATHOPLEXUS_PASSWORD=...
```

The script authenticates with Pathoplexus, validates the records with
`/validate-seqset-records`, and then submits the update to `/update-seqset`.
If the SeqSet is already current, Pathoplexus may report that there are no
changes; the script treats that as a successful no-op.

## GitHub Actions workflow

The `BDBV build and SeqSet` workflow can be run manually from GitHub Actions.
It always runs the BDBV ingest and phylogenetic build and uploads the generated
SeqSet payload as an artifact. It runs the build directly with
`nextstrain build --docker`, so it does not require the AWS/OIDC permissions
used by the scheduled Nextstrain upload workflow.

After the build, the workflow writes a GitHub Actions job summary with the
generated payload counts, whether the Auspice JSON changed, Auspice terminal
node counts, added accessions, removed accessions, and any focal/background
status changes compared with the committed payload. The same summary is uploaded
as `seqsets/seqset-summary.md` in the build artifact.

The workflow includes an `update_seqset` checkbox. When checked, a second job
downloads the generated payload and runs `scripts/update_pathoplexus_seqset.mjs`.
The repository must have these secrets configured for the update job:

```text
PATHOPLEXUS_USERNAME
PATHOPLEXUS_PASSWORD
```

Leave `update_seqset` unchecked to do a dry build that regenerates and archives
the payload without changing Pathoplexus.

## Reviewing changes

Before pushing an update, inspect the payload diff:

```bash
git diff -- seqsets/ebola_bdbv_seqset_update.json
```

Useful things to check:

- New `Bdbv-2026` outbreak accessions are present with `isFocal: true`
- Historical/background BDBV records are present with `isFocal: false`
- Accessions are unversioned Pathoplexus IDs
- The SeqSet ID remains `PP_SS_2047`
