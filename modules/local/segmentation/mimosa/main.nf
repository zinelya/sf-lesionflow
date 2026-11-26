// MIMoSA (Valcarcel et al. 2018, doi:10.1111/jon.12506): runs the REAL, pretrained
// `mimosa_model_No_PD_T2` model shipped inside the `mimosa` R package itself
// (FLAIR + T1, matching this pipeline's inputs exactly).
process SEGMENTATION_MIMOSA {
    tag "$meta.id"
    container 'frheault/sf-lesionflow-mimosa:1.0.0'

    input:
    tuple val(meta), path(t1_mni), path(flair_mni)

    output:
    tuple val(meta), path("${meta.id}_mimosa_binary.nii.gz"), emit: binary_mask
    tuple val(meta), path("${meta.id}_mimosa_prob.nii.gz")  , emit: probability_map
    path "versions.yml"                                     , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prob_thresh = task.ext.prob_threshold ?: 0.30
    def min_cluster = task.ext.min_cluster_size ?: 3
    """
    export FSLDIR=/opt/fsl-6.0.3
    export PATH="\${FSLDIR}/bin:\${PATH}"
    export FSLOUTPUTTYPE=NIFTI_GZ

    mimosa_predict.R --t1 ${t1_mni} \
                     --flair ${flair_mni} \
                     --output ${meta.id}_mimosa_binary.nii.gz \
                     --prob_threshold ${prob_thresh} \
                     --min_cluster_size ${min_cluster} \
                     --output_prob ${meta.id}_mimosa_prob.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mimosa: 1.0
    END_VERSIONS
    """

    stub:
    """
    touch ${meta.id}_mimosa_binary.nii.gz
    touch ${meta.id}_mimosa_prob.nii.gz
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        mimosa: 1.0
    END_VERSIONS
    """

}
