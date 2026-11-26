process SEGMENTATION_WMH_SYNTHSEG {
    tag "$meta.id"
    label 'process_gpu'
    container "docker.io/stanislasthoumyre/wmh-synthseg-minimal:1.0.0"

    input:
    tuple val(meta), path(flair)

    output:
    tuple val(meta), path("${meta.id}_wmh-synthseg_binary.nii.gz"), emit: binary_mask
    tuple val(meta), path("${meta.id}_wmh-synthseg_prob.nii.gz")  , emit: probability_map
    path "versions.yml"                                           , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def label_id    = task.ext.label_id ?: 77
    def use_gpu     = task.ext.gpu
    def device_args = use_gpu ? "--device cuda --crop" : "--device cpu --crop --threads 1"
    """
    # Resolve conform_synthseg.py from Nextflow bin/ before FreeSurfer modifies PATH
    _CONFORM_SCRIPT=\$(which conform_synthseg.py)

    set +u
    export FREESURFER_HOME=/usr/local/freesurfer
    source /usr/local/freesurfer/SetUpFreeSurfer.sh
    set -u

    export PATH=/usr/local/freesurfer/python/bin:\${PATH}
    export HOME="\$(pwd)"
    export TORCH_HOME="\$(pwd)/.cache/torch"
    export MPLCONFIGDIR="\$(pwd)/.cache/matplotlib"

    mri_WMHsynthseg --i ${flair} \
                    --o multiclass.nii.gz \
                    --save_lesion_probabilities \
                    ${device_args}

    fspython \$_CONFORM_SCRIPT --input multiclass.nii.gz --ref ${flair} \
             --output ${meta.id}_wmh-synthseg_binary.nii.gz --label_id ${label_id}

    fspython \$_CONFORM_SCRIPT --input multiclass.lesion_probs.nii.gz \
             --ref ${flair} --output ${meta.id}_wmh-synthseg_prob.nii.gz --continuous

    rm -f multiclass.nii.gz multiclass.lesion_probs.nii.gz

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        Freesurfer: \$(cat /usr/local/freesurfer/build-stamp.txt | grep -oP '\\d+\\.\\d+\\.\\d+' | head -1)
    END_VERSIONS
    """

    stub:
    """
    touch ${meta.id}_wmh-synthseg_binary.nii.gz
    touch ${meta.id}_wmh-synthseg_prob.nii.gz
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        Freesurfer: \$(cat /usr/local/freesurfer/build-stamp.txt | grep -oP '\\d+\\.\\d+\\.\\d+' | head -1)
    END_VERSIONS
    """
}
