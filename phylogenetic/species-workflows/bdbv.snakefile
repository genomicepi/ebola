# Backward compatibility wrapper for callers targeting species-workflows/bdbv.snakefile
# Directly delegates to the modern modular phylogenetic Snakefile.

import os
from pathlib import Path

# Normalize workflow.basedir so relative paths resolve to the phylogenetic root
if os.path.basename(workflow.basedir) == "species-workflows":
    workflow.basedir = str(Path(workflow.basedir).parent)

config['builds'] = ['bdbv/all-outbreaks']

# Default to local ingest outputs (contains all open and restricted sequences)
if 'inputs' not in config:
    config['inputs'] = [
        {
            "name": "local_ingest",
            "species": "bdbv",
            "metadata": "../ingest/results/bdbv/metadata.tsv",
            "id_field": "accession",
            "sequences": "../ingest/results/bdbv/sequences.fasta",
        }
    ]

include: "../Snakefile"
