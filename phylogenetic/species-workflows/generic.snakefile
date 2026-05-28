
print("generic.snakefile config:", config)

wildcard_constraints:
    species="|".join(config['species']),

rule qc:
    input:
        sequences=config['sequences'],
        metadata=config['metadata'],
        exclude=config['exclude'],
    output:
        filtered_data="results/{species}/sequences.fasta",
        filtered_metadata="results/{species}/metadata_raw.tsv",
    params:
        min_length=config["qc_min_length"],
        id_column = config['id_column'],
    shell:
        r"""
        augur filter \
            --metadata-id-columns {params.id_column} \
            --metadata {input.metadata} \
            --sequences {input.sequences} \
            --min-length {params.min_length} \
            --exclude {input.exclude} \
            --output-sequences {output.filtered_data} \
            --output-metadata {output.filtered_metadata}
        """


rule add_strain_name:
    input:
        metadata="results/{species}/metadata_raw.tsv",
    output:
        metadata_with_strain="results/{species}/metadata.tsv",
    run:
        import pandas as pd
        metadata = pd.read_csv(input.metadata, sep="\t")
        country_labels = {
            "Democratic Republic of the Congo": "DRC",
        }
        outbreak_labels = {
            "Bdbv-2007": "2007 Outbreak",
            "Bdbv-2012": "2012 Outbreak",
            "Bdbv-2026": "2026 Outbreak",
        }
        metadata["country_label"] = metadata["country"].replace(country_labels)
        metadata["outbreak_label"] = metadata["outbreak"].replace(outbreak_labels)
        metadata["strain"] = metadata.apply(
            lambda row: f"{row['accession']}|{row['strain']}|{row['country']}/{row['date']}",
            axis=1,
        )
        metadata.to_csv(output.metadata_with_strain, sep="\t", index=False)

rule align:
    input:
        data="results/{species}/sequences.fasta",
        reference=config['fasta_reference'],
        pathogen_json=config['nextclade_pathogen_json'],
        annotation_gff=config['gff_annotation'],
    output:
        aligned="results/{species}/aligned.fasta",
    shell:
        """
        nextclade run --input-ref {input.reference} \
                      --input-pathogen-json {input.pathogen_json} \
                      --input-annotation {input.annotation_gff} \
                      --output-fasta {output.aligned} \
                      --output-translations results/{wildcards.species}/translations.{{cds}}.fasta \
                      {input.data}
        """


rule mask:
    input:
        data="results/{species}/aligned.fasta",
    output:
        masked_data="results/{species}/masked.fasta",
    params:
        mask_beginning=50,
        mask_end=50,
    shell:
        """
        augur mask --sequences {input.data} \
                    --mask-from-beginning {params.mask_beginning} \
                    --mask-from-end {params.mask_end} \
                    --output {output.masked_data}
        """

rule tree:
    input:
        aligned="results/{species}/masked.fasta",
    output:
        tree="results/{species}/tree_raw.nwk",
    shell:
        """
        augur tree \
            --alignment {input.aligned} \
            --output {output.tree}
        """


rule refine:
    input:
        tree="results/{species}/tree_raw.nwk",
        aligned="results/{species}/masked.fasta",
        metadata="results/{species}/metadata.tsv",
    output:
        refined_tree="results/{species}/tree.nwk",
        node_data="results/{species}/branch_lengths.json",
    params:
        timetree_args = config['treetime_args'],
        id_column = config['id_column'],
    shell:
        r"""
        augur refine --tree {input.tree} \
                     {params.timetree_args} \
                     --metadata-id-columns {params.id_column} \
                     --metadata {input.metadata} \
                     --alignment {input.aligned} \
                     --keep-polytomies \
                     --output-tree {output.refined_tree} \
                     --output-node-data {output.node_data}
        """

rule ancestral:
    input:
        tree="results/{species}/tree.nwk",
        aligned="results/{species}/aligned.fasta", # use the un-masked alignment
        reference=config['genbank_reference'],
    output:
        ancestral_seqs="results/{species}/muts.json",
    params:
        cds=config['cds']
    shell:
        r"""
        augur ancestral --tree {input.tree} \
                        --annotation {input.reference} \
                        --translations results/{wildcards.species}/translations.%GENE.fasta \
                        --genes {params.cds} \
                       --alignment {input.aligned} \
                       --output-node-data {output.ancestral_seqs}
        """


# rule sampling_year:
#     input:
#         metadata = "results/{species}/metadata.tsv",
#     output:
#         node_data = "results/{species}/sampling-year.json"
#     params:
#         id_column = config['id_column'],
#     run:
#         from augur.io import read_metadata
#         import json
#         m = read_metadata(input.metadata, id_columns=[params.id_column])
#         nodes = {name: {'year': date.split('-')[0]} for name,date in zip(m.index, m['date']) if date and not date.startswith('X')}
#         with open(output.node_data, 'w') as fh:
#             json.dump({"nodes": nodes}, fh)

rule sampling_year:
    input:
        metadata = "results/{species}/metadata.tsv",
    output:
        node_data = "results/{species}/sampling-year.json",
        config_block = "results/{species}/sampling-year.config.json",
    params:
        id_column = config['id_column'],
    shell:
        r"""
        exec &> >(tee {log:q})

        python scripts/get_year.py \
            --id-columns {params.id_column:q} \
            --metadata {input.metadata:q} \
            --output {output.node_data:q} \
            --output-config {output.config_block:q}
        """


rule modify_auspice_config:
    input:
        auspice_config="species-workflows/auspice-config_{species}.json",
        sampling_year_coloring = lambda w: "results/{species}/sampling-year.config.json" if "results/{species}/sampling-year.json" in node_data_files(w) else [],
    output:
        auspice_config="results/{species}/auspice_config.json",
    run:
        import json
        with open(input.auspice_config) as f:
            auspice_config = json.load(f)
        if input.sampling_year_coloring:
            with open(input.sampling_year_coloring) as f:
                sampling_year = json.load(f)
            auspice_config['colorings'].insert(1, sampling_year)
        with open(output.auspice_config, "w") as f:
            json.dump(auspice_config, f, indent=2)

rule build_description:
    input:
        metadata="results/{species}/metadata.tsv",
        template=f"{REPO}/nextclade/defaults/description.md",
    output:
        description="results/{species}/description.md",
    shell:
        r"""
        python {REPO}/scripts/render_build_description.py \
            --metadata {input.metadata:q} \
            --template {input.template:q} \
            --output {output.description:q}
        """

rule export:
    input:
        tree="results/{species}/tree.nwk",
        metadata="results/{species}/metadata.tsv",
        node_data = lambda w: node_data_files(w),
        lat_longs = "defaults/lat_longs.tsv",
        description = "results/{species}/description.md",
        auspice_config="results/{species}/auspice_config.json",
    output:
        auspice_tree="auspice/ebola_{species}.json",
    params:
        id_column = config['id_column'],
        warning = f"--warning \"{config['warning']}\"" if 'warning' in config else "",
    shell:
        r"""
        augur export v2 --tree {input.tree} \
                    --metadata {input.metadata} \
                    --metadata-id-columns {params.id_column} \
                    --lat-longs {input.lat_longs} \
                    --auspice-config {input.auspice_config} \
                    --description {input.description} \
                    {params.warning} \
                    --node-data {input.node_data} \
                    --include-root-sequence-inline \
                    --output {output.auspice_tree}
        """

if 'seqset' in config:
    rule seqset_payload:
        input:
            metadata="results/{species}/metadata.tsv",
        output:
            payload=f"{REPO}/seqsets/ebola_{{species}}_seqset_update.json",
        params:
            seqset_id=lambda w: config['seqset']['id'],
            name=lambda w: config['seqset']['name'],
            description=lambda w: config['seqset']['description'],
            focal_outbreak=lambda w: config['seqset']['focal_outbreak'],
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
