process PREPROC_SYNTHSEG {
    tag "$meta.id"
    label 'process_gpu'
    container 'freesurfer/freesurfer:7.4.1'

    input:
    tuple val(meta), path(flair)

    output:
    tuple val(meta), path("${meta.id}_synthseg.nii.gz"), emit: synthseg
    path "versions.yml"                                , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def threads    = task.cpus ?: 4
    def use_gpu    = task.ext.gpu
    def device_arg = use_gpu ? "" : "--cpu"
    """
    set +u
    export FREESURFER_HOME=/usr/local/freesurfer
    source /usr/local/freesurfer/SetUpFreeSurfer.sh
    set -u

    mri_synthseg --i ${flair} --o ${meta.id}_synthseg.nii.gz --threads ${threads} ${device_arg}

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        synthseg: 2.0
    END_VERSIONS
    """
    stub:
    """
    touch ${meta.id}_synthseg.nii.gz
    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        synthseg: 2.0
    END_VERSIONS
    """
}
