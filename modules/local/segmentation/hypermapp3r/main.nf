process SEGMENTATION_HYPERMAPP3R {
    tag "$meta.id"
    container 'mgoubran/hypermapper:latest'

    input:
    tuple val(meta), path(t1_mni), path(flair_mni)

    output:
    tuple val(meta), path("${meta.id}_hypermapp3r_binary.nii.gz"), emit: binary_mask
    tuple val(meta), path("${meta.id}_hypermapp3r_prob.nii.gz")  , emit: probability_map
    path "versions.yml"                                          , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def threshold  = task.ext.threshold ?: 0.5
    def mc_samples = task.ext.mc_samples ?: 20
    """
    export OMP_NUM_THREADS=2
    export OPENBLAS_NUM_THREADS=2
    export MKL_NUM_THREADS=2
    export TMPDIR="\$(pwd)/tmp_hyper"
    export APPTAINERENV_TMPDIR="\$(pwd)/tmp_hyper"
    export SINGULARITYENV_TMPDIR="\$(pwd)/tmp_hyper"

    mkdir -p tmp_hyper
    create_nonzero_mask.py --input ${t1_mni} --output brain_mask.nii.gz --dilate 4

    set +e
    hypermapper seg_wmh \
        -s tmp_hyper \
        -t1 ${t1_mni} \
        -fl ${flair_mni} \
        -m brain_mask.nii.gz \
        -o pred.nii.gz \
        -n ${mc_samples} \
        -th ${threshold} \
        -f
    hyper_status=\$?
    set -e
    if [ \$hyper_status -ne 0 ]; then
        echo "hypermapper exited with status \$hyper_status (likely OOM-killed)" >&2
        exit \$hyper_status
    fi

    mv pred.nii.gz ${meta.id}_hypermapp3r_binary.nii.gz
    prob_file=\$(ls tmp_hyper/pred_process_wmh/tmp_hyper_*_pred_prob.nii.gz | head -n 1)
    conform_synthseg.py --input "\$prob_file" --ref ${t1_mni} --output ${meta.id}_hypermapp3r_prob.nii.gz --continuous
    rm -rf tmp_hyper brain_mask.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        hypermapper: 1.0
    END_VERSIONS
    """


    stub:
    """
    touch ${meta.id}_hypermapp3r_binary.nii.gz
    touch ${meta.id}_hypermapp3r_prob.nii.gz
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        hypermapper: 1.0
    END_VERSIONS
    """
}
