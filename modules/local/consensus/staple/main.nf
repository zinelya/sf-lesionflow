process CONSENSUS_STAPLE {
    tag "$meta.id"
    container 'frheault/sf-lesionflow-segcsvd:rc03'

    input:
    tuple val(meta), path(ref_image), path(binary_masks)

    output:
    tuple val(meta), path("${meta.id}_staple_probmap.nii.gz")            , emit: staple_probmap
    tuple val(meta), path("${meta.id}_staple_thr90_binary.nii.gz")       , emit: staple_thr90_binary
    tuple val(meta), path("${meta.id}_staple_thr90_labels_uint16.nii.gz"), emit: staple_thr90_labels
    path "versions.yml"                                                   , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def threshold   = task.ext.threshold        ?: 0.90
    def min_cluster = task.ext.min_cluster_size ?: 6
    def min_dist    = task.ext.min_distance     ?: 3
    def g_sigma     = task.ext.gaussian_sigma   ?: 0.8
    """
    staple_consensus.py --ref_image ${ref_image} \
                        --masks ${binary_masks} \
                        --out_probmap ${meta.id}_staple_probmap.nii.gz \
                        --out_binary ${meta.id}_staple_thr90_binary.nii.gz \
                        --out_labels ${meta.id}_staple_thr90_labels_uint16.nii.gz \
                        --threshold ${threshold} \
                        --min_cluster_size ${min_cluster} \
                        --min_distance ${min_dist} \
                        --gaussian_sigma ${g_sigma}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        sf-lesionflow: "${workflow.manifest.version}"
        python: "\$(python3 --version 2>&1 | awk '{print \$2}')"
        SimpleITK: "\$(python3 -c 'import SimpleITK; print(SimpleITK.Version_VersionString())' 2>/dev/null || echo unknown)"
        nibabel: "\$(python3 -c 'import nibabel; print(nibabel.__version__)')"
        scikit-image: "\$(python3 -c 'import skimage; print(skimage.__version__)')"
    END_VERSIONS
    """
    
    stub:
    """
    touch ${meta.id}_staple_probmap.nii.gz
    touch ${meta.id}_staple_thr90_binary.nii.gz
    touch ${meta.id}_staple_thr90_labels_uint16.nii.gz
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        staple: 1.0
    END_VERSIONS
    """

}
