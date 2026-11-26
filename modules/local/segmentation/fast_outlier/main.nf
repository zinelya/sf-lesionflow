process SEGMENTATION_FAST_OUTLIER {
    tag "$meta.id"
    container 'frheault/sf-lesionflow-fast_outlier:1.0.0'

    input:
    tuple val(meta), path(t1_mni), path(flair_mni)

    output:
    tuple val(meta), path("${meta.id}_fast-outlier_binary.nii.gz"), emit: binary_mask
    tuple val(meta), path("${meta.id}_fast-outlier_zscore.nii.gz"), emit: probability_map
    path "versions.yml"                                           , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def sigma      = task.ext.sigma ?: 2.5
    def pve_thresh = task.ext.pve_threshold ?: 0.95
    def dwm_thresh = task.ext.dwm_threshold ?: 0.50
    """
    export FSLDIR=/usr/local/fsl
    export PATH=\${FSLDIR}/bin:\$PATH
    export FSLOUTPUTTYPE=NIFTI_GZ

    mkdir -p fast_out
    fast -t 1 -n 3 -H 0.1 -I 4 -l 20.0 -o fast_out/fast ${t1_mni}

    fast_outlier.py --flair ${flair_mni} \
                    --wm_pve fast_out/fast_pve_2.nii.gz \
                    --output ${meta.id}_fast-outlier_binary.nii.gz \
                    --sigma ${sigma} \
                    --pve_threshold ${pve_thresh} \
                    --dwm_threshold ${dwm_thresh} \
                    --output_zscore ${meta.id}_fast-outlier_zscore.nii.gz

    rm -rf fast_out

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fast: 6.0
        fast_outlier: 1.0
    END_VERSIONS
    """

    stub:
    """
    touch ${meta.id}_fast-outlier_binary.nii.gz
    touch ${meta.id}_fast-outlier_zscore.nii.gz
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        fast: 6.0
        fast_outlier: 1.0
    END_VERSIONS
    """
}
