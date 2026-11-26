process HARMONIZATION_STAPLE {
    tag "$subject"
    container 'frheault/sf-lesionflow-segcsvd:rc03'

    input:
    tuple val(subject), val(metas), path(staple_masks)

    output:
    tuple val(subject), path("*_staple_thr90_harmonized_binary.nii.gz")       , emit: harmonized_binary
    tuple val(subject), path("*_staple_thr90_harmonized_labels_uint16.nii.gz"), emit: harmonized_labels
    tuple val(subject), path("${subject}_staple_harmonized_lesion_tracking.csv"), emit: audit_csv
    path "versions.yml"                                                        , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def min_cluster = task.ext.min_cluster_size    ?: 6
    def min_dist    = task.ext.min_distance        ?: 3
    def g_sigma     = task.ext.gaussian_sigma      ?: 0.8
    def pct_thresh  = task.ext.pct_change_threshold ?: 20.0
    """
    harmonize_staple.py --subject ${subject} \
                        --masks ${staple_masks} \
                        --out_csv ${subject}_staple_harmonized_lesion_tracking.csv \
                        --min_cluster_size ${min_cluster} \
                        --min_distance ${min_dist} \
                        --gaussian_sigma ${g_sigma} \
                        --pct_change_threshold ${pct_thresh}

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
    for m in ${staple_masks}; do
        fname=\$(basename \$m)
        ses_name=\$(echo \$fname | grep -o 'ses-[0-9a-zA-Z]*')
        if [ -n "\$ses_name" ]; then
            ses_suffix="_\${ses_name}"
        else
            ses_suffix=""
        fi
        touch ${subject}\${ses_suffix}_staple_thr90_harmonized_binary.nii.gz
        touch ${subject}\${ses_suffix}_staple_thr90_harmonized_labels_uint16.nii.gz
    done
    touch ${subject}_staple_harmonized_lesion_tracking.csv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        harmonization: 1.0
    END_VERSIONS
    """
}
