# Backward compatibility wrapper for callers targeting species-workflows/bdbv.snakefile
# Directly delegates to the modern modular phylogenetic Snakefile.

config['builds'] = ['bdbv/all-outbreaks']

include: "../Snakefile"
