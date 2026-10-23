import os
from pathlib import Path

REPO = Path(workflow.basedir).parent

rule build_description:
    input:
        metadata="results/{species}/{build}/metadata.tsv",
        template=str(REPO / "nextclade" / "defaults" / "description.md"),
    output:
        description="results/{species}/{build}/description.md",
    shell:
        r"""
        python {REPO}/scripts/render_build_description.py \
            --metadata {input.metadata:q} \
            --template {input.template:q} \
            --output {output.description:q}
        """

rule seqset_payload:
    input:
        metadata="results/bdbv/all-outbreaks/metadata.tsv",
    output:
        payload=str(REPO / "seqsets" / "ebola_bdbv_seqset_update.json"),
    params:
        seqset_id=lambda w: config.get('seqset', {}).get('id', 'PP_SS_2047'),
        name=lambda w: config.get('seqset', {}).get('name', 'Bundibugyo ebolavirus 2026 outbreak build'),
        description=lambda w: config.get('seqset', {}).get('description', 'Bundibugyo ebolavirus sequences used in the GenomicEpi 2026 outbreak community build. Bdbv-2026 records are focal; historical BDBV records are background.'),
        focal_outbreak=lambda w: config.get('seqset', {}).get('focal_outbreak', 'Bdbv-2026'),
    shell:
        r"""
        python {REPO}/scripts/generate_seqset_payload.py \
            --metadata {input.metadata:q} \
            --output {output.payload:q} \
            --seqset-id {params.seqset_id:q} \
            --name {params.name:q} \
            --description {params.description:q} \
            --focal-outbreak {params.focal_outbreak:q}
        """

rule copy_community_auspice:
    input:
        auspice="auspice/ebola_bdbv_all-outbreaks.json",
    output:
        phylo_auspice="auspice/ebola_bdbv.json",
        root_auspice=str(REPO / "auspice" / "ebola_bdbv.json"),
    shell:
        r"""
        cp {input.auspice:q} {output.phylo_auspice:q}
        cp {input.auspice:q} {output.root_auspice:q}
        """
